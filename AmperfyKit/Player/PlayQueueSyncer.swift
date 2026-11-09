//
//  PlayQueueSyncer.swift
//  AmperfyKit
//
//  This program is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 3 of the License, or
//  (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program.  If not, see <http://www.gnu.org/licenses/>.
//

import Foundation
import os.log

// MARK: - PlayQueueSyncer

/// Saves the music queue of the player to the server of one account, and offers the queue that
/// another client or another device saved there.
///
/// The server keeps one queue without a user queue and without a shuffle state. The saved queue is
/// the order in which the songs play: the user queue comes after the current song. A restore puts
/// all songs into the context queue.
@MainActor
public class PlayQueueSyncer {
  public enum SaveReason: String {
    case pause
    case stop
    case trackChange
    case queueChange
    case background
  }

  public static let remotePlayQueueKey = "remotePlayQueue"

  /// Seconds to wait after a track change or a queue change, so that quick changes give one save
  public var debounceDelay: TimeInterval = 3
  /// Seconds to wait after a pause. A new queue starts with a pause, its queue change then wins.
  public var pauseDebounceDelay: TimeInterval = 0.5
  /// Seconds between two reads of the server queue. On macOS, each focus of the window asks for one.
  public var minimumCheckInterval: TimeInterval = 30

  private let log = OSLog(subsystem: "Amperfy", category: "PlayQueueSyncer")
  private let player: PlayerFacade
  private let account: Account
  private let storage: PersistentStorage
  private let networkMonitor: NetworkMonitorFacade
  private let librarySyncer: LibrarySyncer
  private let eventLogger: EventLogger
  private let notificationHandler: EventNotificationHandler

  private var isRunning = false
  /// The queue or the position changed since the last save
  private var isDirty = false
  private var lastUpload: PlayQueueUpload?
  private var debounceTask: Task<(), Never>?
  private var saveTask: Task<(), Never>?
  /// `changed` of the server queue that waits for an answer of the user
  private var offeredChanged: String?
  /// After a restore, the position to seek to when the restored song starts
  private var restoreSeek: (songId: String, seconds: Double)?
  /// After a restore that did not start playback, the server already has the queue
  private var isRestoredQueueNotPlayed = false
  private var isOtherAccountQueueLogged = false
  private var lastCheckDate: Date?

  init(
    player: PlayerFacade,
    account: Account,
    storage: PersistentStorage,
    networkMonitor: NetworkMonitorFacade,
    librarySyncer: LibrarySyncer,
    eventLogger: EventLogger,
    notificationHandler: EventNotificationHandler
  ) {
    self.player = player
    self.account = account
    self.storage = storage
    self.networkMonitor = networkMonitor
    self.librarySyncer = librarySyncer
    self.eventLogger = eventLogger
    self.notificationHandler = notificationHandler
  }

  public func start() {
    isRunning = true
  }

  public func stop() {
    isRunning = false
    debounceTask?.cancel()
    debounceTask = nil
  }

  private var accountSetting: AccountSetting {
    storage.settings.accounts.getSetting(account.info).read
  }

  private var isActive: Bool {
    isRunning && accountSetting.isPlayQueueSyncEnabled && storage.settings.user.isOnlineMode &&
      networkMonitor.isConnectedToNetwork
  }

  // MARK: - Save

  /// The music queue in the order it plays, or nil if the queue can not go to this server
  func createUpload() -> PlayQueueUpload? {
    guard player.playerMode == .music, let currentlyPlaying = player.currentlyPlaying
    else { return nil }
    let prevItems = player.getAllPrevQueueItems()
    let playables = prevItems + [currentlyPlaying] + player.getAllUserQueueItems() + player
      .getAllNextQueueItems()
    let songs = playables.compactMap { $0.asSong }
    guard songs.count == playables.count, !songs.contains(where: { $0.id.isEmpty })
    else { return nil }
    guard songs.allSatisfy({ $0.account == account }) else {
      if !isOtherAccountQueueLogged {
        isOtherAccountQueueLogged = true
        os_log(
          "Queue has songs of other accounts, it is not saved to %s",
          log: log,
          type: .info,
          account.ident
        )
      }
      return nil
    }
    let elapsedTime = player.elapsedTime.isFinite ? max(player.elapsedTime, 0) : 0
    return PlayQueueUpload(
      songIds: songs.map { $0.id },
      currentIndex: prevItems.count,
      positionMs: Int((elapsedTime * 1000).rounded())
    )
  }

  /// Saves the queue at once if it changed since the last save
  public func saveNow(reason: SaveReason) async {
    debounceTask?.cancel()
    debounceTask = nil
    await enqueueSave(reason: reason)
  }

  private func scheduleSave(reason: SaveReason, delay: TimeInterval) {
    debounceTask?.cancel()
    debounceTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
      guard !Task.isCancelled else { return }
      await enqueueSave(reason: reason)
    }
  }

  /// Saves one after the other, so that an older queue never overwrites a newer one on the server
  private func enqueueSave(reason: SaveReason) async {
    let previousSave = saveTask
    let save = Task { @MainActor in
      await previousSave?.value
      await self.save(reason: reason)
    }
    saveTask = save
    await save.value
  }

  private func save(reason: SaveReason) async {
    // do not overwrite a queue that the user can still continue
    guard isActive, isDirty, offeredChanged == nil, !isRestoredQueueNotPlayed,
          let upload = createUpload()
    else { return }
    isDirty = false
    guard upload != lastUpload else { return }
    do {
      try await librarySyncer.syncUpload(playQueue: upload)
      lastUpload = upload
      storage.settings.accounts.updateSetting(account.info) { setting in
        setting.savedPlayQueueMark = upload.mark
      }
      os_log("Saved play queue (%s)", log: log, type: .info, reason.rawValue)
    } catch {
      isDirty = true
      eventLogger.report(topic: "Play Queue Sync", error: error, displayPopup: false)
    }
  }

  /// Waits for the save that a track change or a queue change scheduled
  func waitForScheduledSave() async {
    await debounceTask?.value
    await saveTask?.value
  }

  // MARK: - Handoff

  /// Reads the server queue and posts `remotePlayQueueAvailable` if another client or another
  /// device saved a queue that this device did not see yet
  public func checkRemoteQueue() async {
    guard isActive, !player.isPlaying else { return }
    if let lastCheckDate, Date().timeIntervalSince(lastCheckDate) < minimumCheckInterval { return }
    lastCheckDate = Date()
    let remote: RemotePlayQueue?
    do {
      remote = try await librarySyncer.syncDownPlayQueue()
    } catch {
      lastCheckDate = nil
      eventLogger.report(topic: "Play Queue Sync", error: error, displayPopup: false)
      return
    }
    guard isActive, let remote, let remoteMark = remote.mark,
          remote.changed != accountSetting.knownServerPlayQueueChanged
    else { return }

    if remoteMark == accountSetting.savedPlayQueueMark || isSameAsLocalQueue(remote) {
      remember(remote)
      return
    }
    guard !player.isPlaying else { return }
    offeredChanged = remote.changed
    os_log(
      "Offer play queue of %s (%s)",
      log: log,
      type: .info,
      remote.changedBy,
      remote.changed
    )
    notificationHandler.post(
      name: .remotePlayQueueAvailable,
      object: self,
      userInfo: [Self.remotePlayQueueKey: remote]
    )
  }

  private func isSameAsLocalQueue(_ remote: RemotePlayQueue) -> Bool {
    guard let local = createUpload() else { return false }
    return local.songIds == remote.songs.map { $0.id } && local.currentIndex == remote
      .currentIndex && abs(local.positionMs - remote.positionMs) < 2000
  }

  /// Replaces the music queue with the server queue and continues at its position
  public func restore(_ remote: RemotePlayQueue) {
    remember(remote)
    guard let currentSong = remote.currentSong else { return }
    let seconds = Double(remote.positionMs) / 1000
    // the setting "Resume Playback" seeks to the play progress of the song
    currentSong.playProgress = Int(seconds)
    restoreSeek = (songId: currentSong.id, seconds: seconds)
    isRestoredQueueNotPlayed = true
    os_log("Restore play queue of %s", log: log, type: .info, remote.changedBy)
    player.clearUserQueue()
    player.play(context: PlayContext(
      name: "Play Queue",
      index: remote.currentIndex,
      playables: remote.songs
    ))
    lastUpload = PlayQueueUpload(
      songIds: remote.songs.map { $0.id },
      currentIndex: remote.currentIndex,
      positionMs: remote.positionMs
    )
  }

  /// The user does not want to continue this server queue
  public func dismiss(_ remote: RemotePlayQueue) {
    remember(remote)
  }

  private func remember(_ remote: RemotePlayQueue) {
    offeredChanged = nil
    storage.settings.accounts.updateSetting(account.info) { setting in
      setting.knownServerPlayQueueChanged = remote.changed
    }
  }
}

// MARK: MusicPlayable

extension PlayQueueSyncer: MusicPlayable {
  public func didStartPlayingFromBeginning() {
    if let restoreSeek {
      self.restoreSeek = nil
      // a seek before the song is prepared gets lost, so it waits until now
      if player.currentlyPlaying?.id == restoreSeek.songId, restoreSeek.seconds > 0 {
        player.seek(toSecond: restoreSeek.seconds)
      }
    }
    isDirty = true
    scheduleSave(reason: .trackChange, delay: debounceDelay)
  }

  public func didStartPlaying() {
    if player.isPlaying {
      isRestoredQueueNotPlayed = false
      // the user plays the local queue instead of the offered one
      offeredChanged = nil
    }
    isDirty = true
  }

  public func didPause() {
    isDirty = true
    scheduleSave(reason: .pause, delay: pauseDebounceDelay)
  }

  public func didStopPlaying() {
    isDirty = true
    scheduleSave(reason: .stop, delay: pauseDebounceDelay)
  }

  public func didPlaylistChange() {
    isDirty = true
    scheduleSave(reason: .queueChange, delay: debounceDelay)
  }

  public func didElapsedTimeChange() {}
  public func didArtworkChange() {}
  public func didShuffleChange() {}
  public func didRepeatChange() {}
  public func didPlaybackRateChange() {}
}
