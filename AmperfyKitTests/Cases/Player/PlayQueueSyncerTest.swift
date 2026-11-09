//
//  PlayQueueSyncerTest.swift
//  AmperfyKitTests
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

@testable import AmperfyKit
import XCTest

@MainActor
class PlayQueueSyncerTest: XCTestCase {
  private let accountKey = PersistentStorage.UserDefaultsKey.SettingsAccount.rawValue
  private let userKey = PersistentStorage.UserDefaultsKey.SettingsUser.rawValue
  private var savedAccountData: Data?
  private var savedUserData: Data?

  var cdHelper: CoreDataHelper!
  var library: LibraryStorage!
  var account: Account!
  var storage: PersistentStorage!
  var playerData: PlayerData!
  var queueHandler: PlayQueueHandler!
  var player: PlayerFacade!
  var mockAudioStreamingPlayer: MOCK_AudioStreamingPlayer!
  var mockMusicPlayable: MOCK_MusicPlayable!
  var librarySyncer: MOCK_LibrarySyncer!
  var syncer: PlayQueueSyncer!
  var offeredQueues = [RemotePlayQueue]()

  var songs: [Song]!
  var otherAccountSong: Song!

  override func setUp() async throws {
    savedAccountData = UserDefaults.standard.data(forKey: accountKey)
    savedUserData = UserDefaults.standard.data(forKey: userKey)

    cdHelper = CoreDataHelper()
    library = cdHelper.createSeededStorage()
    account = library.getAccount(info: TestAccountInfo.create1())
    storage = PersistentStorage(
      coreDataManager: MOCK_CoreDataManager(persistentContainer: cdHelper.persistentContainer)
    )
    storage.settings.user.isOfflineMode = false
    storage.settings.accounts.updateSetting(account.info) { setting in
      setting.isPlayQueueSyncEnabled = true
      setting.knownServerPlayQueueChanged = nil
      setting.savedPlayQueueMark = nil
    }

    let eventLogger = EventLogger(storage: storage)
    let userStatistics = library.getUserStatistics(appVersion: "")
    let backendApi = MOCK_BackendApi()
    let songDownloader = MOCK_SongDownloader()
    mockAudioStreamingPlayer = MOCK_AudioStreamingPlayer()
    let backendPlayer = BackendAudioPlayer(
      createAudioStreamingPlayerCB: { self.mockAudioStreamingPlayer },
      audioSessionHandler: AudioSessionHandler(),
      eventLogger: eventLogger,
      getBackendApiCB: { _ in backendApi },
      networkMonitor: MOCK_NetworkMonitor(),
      getPlayableDownloaderCB: { _ in songDownloader },
      cacheProxy: library,
      userStatistics: userStatistics
    )
    playerData = library.getPlayerData()
    queueHandler = PlayQueueHandler(playerData: playerData)
    let musicPlayer = AudioPlayer(
      coreData: playerData,
      queueHandler: queueHandler,
      backendAudioPlayer: backendPlayer,
      settings: storage.settings,
      userStatistics: userStatistics
    )
    player = PlayerFacadeImpl(
      playerStatus: playerData,
      queueHandler: queueHandler,
      musicPlayer: musicPlayer,
      library: library,
      backendAudioPlayer: backendPlayer,
      userStatistics: userStatistics
    )
    mockMusicPlayable = MOCK_MusicPlayable()
    player.addNotifier(notifier: mockMusicPlayable)

    librarySyncer = MOCK_LibrarySyncer()
    let notificationHandler = EventNotificationHandler()
    syncer = PlayQueueSyncer(
      player: player,
      account: account,
      storage: storage,
      networkMonitor: MOCK_NetworkMonitor(),
      librarySyncer: librarySyncer,
      eventLogger: eventLogger,
      notificationHandler: notificationHandler
    )
    syncer.debounceDelay = 0
    syncer.pauseDebounceDelay = 0
    syncer.minimumCheckInterval = 0
    player.addNotifier(notifier: syncer)
    syncer.start()
    notificationHandler.register(
      self,
      selector: #selector(remotePlayQueueAvailable(notification:)),
      name: .remotePlayQueueAvailable,
      object: syncer
    )

    songs = cdHelper.seeder.songs.filter { $0.accountIndex == 0 }.prefix(7).map {
      library.getSong(for: account, id: $0.id)!
    }
    let otherAccount = library.getAccount(info: TestAccountInfo.create2())
    otherAccountSong = library.getSong(
      for: otherAccount,
      id: cdHelper.seeder.songs.first(where: { $0.accountIndex == 1 })!.id
    )
    playerData.removeAllItems()
  }

  override func tearDown() async throws {
    syncer.stop()
    NotificationCenter.default.removeObserver(self)
    UserDefaults.standard.set(savedAccountData, forKey: accountKey)
    UserDefaults.standard.set(savedUserData, forKey: userKey)
  }

  @objc
  private func remotePlayQueueAvailable(notification: Notification) {
    guard let remote = notification
      .userInfo?[PlayQueueSyncer.remotePlayQueueKey] as? RemotePlayQueue
    else { XCTFail(); return }
    offeredQueues.append(remote)
  }

  /// Sets the queue without player notifications: context songs 0 to 4, `current` plays
  private func setContextQueue(current: Int) {
    queueHandler.appendContextQueue(playables: Array(songs[0 ... 4]))
    playerData.setCurrentIndex(current)
  }

  private func save(reason: PlayQueueSyncer.SaveReason = .pause) async {
    await syncer.saveNow(reason: reason)
  }

  private func makeRemote(
    songIndexes: [Int] = [0, 1, 2],
    currentIndex: Int = 1,
    positionMs: Int = 63000,
    changed: String = "2026-11-09T18:01:02.123456789Z",
    changedBy: String = "Feishin"
  )
    -> RemotePlayQueue {
    RemotePlayQueue(
      songs: songIndexes.map { songs[$0] },
      currentIndex: currentIndex,
      positionMs: positionMs,
      changed: changed,
      changedBy: changedBy
    )
  }

  /// The player applies a seek when the stream has started, which happens a moment later
  private func waitForElapsedTime(_ seconds: Double) async {
    let deadline = Date().addingTimeInterval(2)
    while abs(player.elapsedTime - seconds) > 0.001, Date() < deadline {
      try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTAssertEqual(player.elapsedTime, seconds, accuracy: 0.001)
  }

  private func startPlayback(context: PlayContext) async {
    mockMusicPlayable.expectationDidStartPlaying = expectation(description: "playback started")
    player.play(context: context)
    await fulfillment(of: [mockMusicPlayable.expectationDidStartPlaying!], timeout: 2)
    mockMusicPlayable.expectationDidStartPlaying = nil
  }

  // MARK: - Save

  func testUploadWindow_KeepsCurrentSongAndMark() {
    let upload = PlayQueueUpload(
      songIds: (0 ..< 500).map { "id\($0)" },
      currentIndex: 450,
      positionMs: 7000
    )
    let window = upload.window(maxCount: 200)
    XCTAssertEqual(window.songIds.count, 200)
    XCTAssertEqual(window.songIds.first, "id300")
    XCTAssertEqual(window.currentSongId, "id450")
    XCTAssertEqual(window.positionMs, 7000)
    XCTAssertEqual(window.mark, upload.mark)
  }

  func testPause_SavesQueueAndPosition() async {
    syncer.debounceDelay = 60 // the save of the track change waits
    await startPlayback(context: PlayContext(name: "", index: 2, playables: Array(songs[0 ... 4])))
    player.seek(toSecond: 42)
    await waitForElapsedTime(42)
    player.pause()
    await syncer.waitForScheduledSave()

    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 1)
    let upload = librarySyncer.uploadedPlayQueues.first
    XCTAssertEqual(upload?.songIds, songs[0 ... 4].map { $0.id })
    XCTAssertEqual(upload?.currentIndex, 2)
    XCTAssertEqual(upload?.positionMs, 42000)
    XCTAssertEqual(
      storage.settings.accounts.getSetting(account.info).read.savedPlayQueueMark,
      "\(songs[2].id)@42000"
    )
  }

  func testPause_WithoutChange_SavesOnce() async {
    setContextQueue(current: 1)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 1)
  }

  func testSave_WithoutPlayerEvent_DoesNothing() async {
    // a queue of an earlier session must not overwrite the server queue
    setContextQueue(current: 1)
    await save(reason: .background)
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)
  }

  func testQuickChanges_GiveOneSave() async {
    syncer.debounceDelay = 0.2
    setContextQueue(current: 1)
    syncer.didPlaylistChange()
    syncer.didStartPlayingFromBeginning()
    syncer.didPlaylistChange()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 1)
  }

  func testSave_UserQueue_PlaysAfterCurrentSong() async {
    setContextQueue(current: 1)
    queueHandler.appendUserQueue(playables: [songs[5], songs[6]])
    syncer.didPlaylistChange()
    await syncer.waitForScheduledSave()

    let upload = librarySyncer.uploadedPlayQueues.last
    XCTAssertEqual(
      upload?.songIds,
      [songs[0], songs[1], songs[5], songs[6], songs[2], songs[3], songs[4]].map { $0.id }
    )
    XCTAssertEqual(upload?.currentIndex, 1)
  }

  func testSave_UserQueuePlaying() async {
    setContextQueue(current: 1)
    queueHandler.appendUserQueue(playables: [songs[5], songs[6]])
    playerData.setUserQueuePlaying(true)
    syncer.didPlaylistChange()
    await syncer.waitForScheduledSave()

    let upload = librarySyncer.uploadedPlayQueues.last
    XCTAssertEqual(
      upload?.songIds,
      [songs[0], songs[1], songs[5], songs[6], songs[2], songs[3], songs[4]].map { $0.id }
    )
    XCTAssertEqual(upload?.currentIndex, 2)
  }

  func testSave_EmptyQueue_IsNotSaved() async {
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)
  }

  func testSave_SongOfOtherAccount_IsNotSaved() async {
    queueHandler.appendContextQueue(playables: [songs[0], otherAccountSong, songs[1]])
    playerData.setCurrentIndex(0)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)
  }

  func testSave_SyncDisabled_IsNotSaved() async {
    storage.settings.accounts.updateSetting(account.info) { $0.isPlayQueueSyncEnabled = false }
    setContextQueue(current: 1)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)
  }

  func testSave_OfflineMode_IsNotSaved() async {
    storage.settings.user.isOfflineMode = true
    setContextQueue(current: 1)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)
  }

  // MARK: - Handoff

  func testCheck_QueueOfOtherClient_IsOffered() async {
    librarySyncer.remotePlayQueue = makeRemote()
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 1)
    XCTAssertEqual(offeredQueues.first?.changedBy, "Feishin")
  }

  func testCheck_DismissedQueue_IsNotOfferedAgain() async {
    let remote = makeRemote()
    librarySyncer.remotePlayQueue = remote
    await syncer.checkRemoteQueue()
    syncer.dismiss(remote)
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 1)
    XCTAssertEqual(
      storage.settings.accounts.getSetting(account.info).read.knownServerPlayQueueChanged,
      remote.changed
    )
  }

  func testCheck_NewChangeAfterDismiss_IsOffered() async {
    let remote = makeRemote()
    librarySyncer.remotePlayQueue = remote
    await syncer.checkRemoteQueue()
    syncer.dismiss(remote)
    librarySyncer.remotePlayQueue = makeRemote(changed: "2026-11-09T18:05:00.5Z")
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 2)
  }

  func testCheck_QueueSavedByThisDevice_IsNotOffered() async {
    setContextQueue(current: 1)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 1)
    // the local queue changed later, but the server still has the saved one
    queueHandler.appendContextQueue(playables: [songs[5]])

    librarySyncer.remotePlayQueue = makeRemote(
      songIndexes: [0, 1, 2, 3, 4],
      currentIndex: 1,
      positionMs: 0,
      changedBy: "Amperfy"
    )
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 0)
    XCTAssertEqual(
      storage.settings.accounts.getSetting(account.info).read.knownServerPlayQueueChanged,
      "2026-11-09T18:01:02.123456789Z"
    )
  }

  func testCheck_QueueOfOtherAmperfyDevice_IsOffered() async {
    librarySyncer.remotePlayQueue = makeRemote(changedBy: "Amperfy")
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 1)
  }

  func testCheck_SameQueueAsLocal_IsNotOffered() async {
    setContextQueue(current: 1)
    librarySyncer.remotePlayQueue = makeRemote(
      songIndexes: [0, 1, 2, 3, 4],
      currentIndex: 1,
      positionMs: 500
    )
    await syncer.checkRemoteQueue()
    XCTAssertEqual(offeredQueues.count, 0)
  }

  func testCheck_WithinMinimumInterval_OnlyForegroundRequests() async {
    syncer.minimumCheckInterval = 30
    await syncer.checkRemoteQueue()
    await syncer.checkRemoteQueue()
    XCTAssertEqual(librarySyncer.remotePlayQueueRequestCount, 1)
    await syncer.checkRemoteQueue(isIntervalIgnored: true)
    XCTAssertEqual(librarySyncer.remotePlayQueueRequestCount, 2)
  }

  func testCheck_WhilePlaying_DoesNotRequest() async {
    await startPlayback(context: PlayContext(name: "", index: 0, playables: Array(songs[0 ... 2])))
    librarySyncer.remotePlayQueue = makeRemote()
    await syncer.checkRemoteQueue()
    XCTAssertEqual(librarySyncer.remotePlayQueueRequestCount, 0)
    XCTAssertEqual(offeredQueues.count, 0)
  }

  func testCheck_SyncDisabled_DoesNotRequest() async {
    storage.settings.accounts.updateSetting(account.info) { $0.isPlayQueueSyncEnabled = false }
    librarySyncer.remotePlayQueue = makeRemote()
    await syncer.checkRemoteQueue()
    XCTAssertEqual(librarySyncer.remotePlayQueueRequestCount, 0)
  }

  func testOpenOffer_BlocksSave() async {
    let remote = makeRemote()
    librarySyncer.remotePlayQueue = remote
    await syncer.checkRemoteQueue()
    setContextQueue(current: 1)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 0)

    syncer.dismiss(remote)
    syncer.didPause()
    await syncer.waitForScheduledSave()
    XCTAssertEqual(librarySyncer.uploadedPlayQueues.count, 1)
  }

  func testRestore_PlaysServerQueueAtPosition() async {
    queueHandler.appendContextQueue(playables: [songs[6]])
    queueHandler.appendUserQueue(playables: [songs[5]])
    let remote = makeRemote(songIndexes: [0, 1, 2, 3, 4], currentIndex: 3, positionMs: 63000)

    mockMusicPlayable.expectationDidStartPlaying = expectation(description: "playback started")
    syncer.restore(remote)
    await fulfillment(of: [mockMusicPlayable.expectationDidStartPlaying!], timeout: 2)

    XCTAssertEqual(player.currentlyPlaying?.id, songs[3].id)
    XCTAssertEqual(player.getAllPrevQueueItems().map { $0.id }, songs[0 ... 2].map { $0.id })
    XCTAssertEqual(player.getAllNextQueueItems().map { $0.id }, [songs[4].id])
    XCTAssertEqual(player.userQueueCount, 0)
    XCTAssertFalse(player.isShuffle)
    await waitForElapsedTime(63)
    XCTAssertEqual(
      storage.settings.accounts.getSetting(account.info).read.knownServerPlayQueueChanged,
      remote.changed
    )
  }

  func testRestore_DuplicateSong_PlaysSecondOccurrence() async {
    let remote = makeRemote(songIndexes: [0, 1, 0, 2], currentIndex: 2, positionMs: 1000)

    mockMusicPlayable.expectationDidStartPlaying = expectation(description: "playback started")
    syncer.restore(remote)
    await fulfillment(of: [mockMusicPlayable.expectationDidStartPlaying!], timeout: 2)

    XCTAssertEqual(player.currentlyPlaying?.id, songs[0].id)
    XCTAssertEqual(player.prevQueueCount, 2)
    XCTAssertEqual(player.nextQueueCount, 1)
  }
}
