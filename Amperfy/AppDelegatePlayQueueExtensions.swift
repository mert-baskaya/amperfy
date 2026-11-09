//
//  AppDelegatePlayQueueExtensions.swift
//  Amperfy
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

import AmperfyKit
import Foundation
import UIKit

// MARK: - BackgroundTask

@MainActor
private final class BackgroundTask {
  private var id = UIBackgroundTaskIdentifier.invalid

  init(name: String) {
    self.id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
      self?.end()
    }
  }

  func end() {
    guard id != .invalid else { return }
    UIApplication.shared.endBackgroundTask(id)
    id = .invalid
  }
}

// MARK: - AppDelegate + Play Queue Handoff

extension AppDelegate {
  private static weak var remotePlayQueueAlert: UIAlertController?

  func configurePlayQueueHandoff() {
    notificationHandler.register(
      self,
      selector: #selector(remotePlayQueueAvailable(notification:)),
      name: .remotePlayQueueAvailable,
      object: nil
    )
  }

  /// Offers the server play queue of the active account, if another client saved a new one.
  /// When the scene only becomes active again, the check waits for the minimum interval.
  func checkRemotePlayQueue(isEnteringForeground: Bool) {
    guard let activeAccountInfo = storage.settings.accounts.active,
          let syncer = getMeta(activeAccountInfo).playQueueSyncer
    else { return }
    Task { await syncer.checkRemoteQueue(isIntervalIgnored: isEnteringForeground) }
  }

  /// Saves the play queue of each account before iOS suspends Amperfy
  func savePlayQueuesBeforeSuspension() {
    let syncers = AmperKit.shared.allActiveMetas.values.compactMap { $0.playQueueSyncer }
    guard !syncers.isEmpty else { return }
    let backgroundTask = BackgroundTask(name: "Save Play Queue")
    Task {
      for syncer in syncers {
        await syncer.saveNow(reason: .background)
      }
      backgroundTask.end()
    }
  }

  @objc
  private func remotePlayQueueAvailable(notification: Notification) {
    guard let syncer = notification.object as? PlayQueueSyncer,
          let remote = notification
          .userInfo?[PlayQueueSyncer.remotePlayQueueKey] as? RemotePlayQueue
    else { return }
    offerToContinue(remote, syncer: syncer, retryCount: 0)
  }

  /// The top view controller, also a presented one such as the player or a settings sheet
  private static var playQueueAlertPresenter: UIViewController? {
    var presenter = window?.rootViewController
    while let presented = presenter?.presentedViewController, !presented.isBeingDismissed {
      presenter = presented
    }
    guard let presenter, !(presenter is UIAlertController), !presenter.isBeingDismissed,
          presenter.viewIfLoaded?.window != nil
    else { return nil }
    return presenter
  }

  private func offerToContinue(
    _ remote: RemotePlayQueue,
    syncer: PlayQueueSyncer,
    retryCount: Int
  ) {
    guard Self.remotePlayQueueAlert == nil else { return }
    guard let presenter = Self.playQueueAlertPresenter else {
      // right after launch the main window is not ready, or another alert is open
      guard retryCount < 5 else { return }
      Task {
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        offerToContinue(remote, syncer: syncer, retryCount: retryCount + 1)
      }
      return
    }

    let source = switch remote.changedBy {
    case "": "Another client"
    case "Amperfy": "Amperfy on another device"
    default: remote.changedBy
    }
    var message = "\(source) saved a queue of \(remote.songs.count) songs."
    if let currentSong = remote.currentSong {
      message +=
        " It continues with \"\(currentSong.title)\" at \((remote.positionMs / 1000).asColonDurationString)."
    }
    let alert = UIAlertController(
      title: "Continue Playback?",
      message: message,
      preferredStyle: .alert
    )
    alert.addAction(UIAlertAction(title: "Not Now", style: .cancel) { _ in
      syncer.dismiss(remote)
    })
    let continueAction = UIAlertAction(title: "Continue", style: .default) { _ in
      syncer.restore(remote)
    }
    alert.addAction(continueAction)
    alert.preferredAction = continueAction
    Self.remotePlayQueueAlert = alert
    presenter.present(alert, animated: true)
  }
}
