//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI
import Logging

/// Plays an item's theme song while its page is open, such as the songs
/// the Themerr plugin downloads for movies and shows.
///
/// The song fades in when a page opens and fades out when you leave. Moving
/// between pages that share a song (a show, its seasons, and its episodes)
/// keeps it playing without restarting. Video playback stops it right away.
@MainActor
final class ThemeSongPlayer {

    static let shared = ThemeSongPlayer()

    private static let volume: Float = 0.5
    private static let fadeSteps = 15
    private static let fadeStepDuration: Duration = .milliseconds(100)

    private let logger = Logger.swiftfin()

    private var player: AVPlayer?
    private var statusObservation: NSKeyValueObservation?
    private var currentSongID: String?

    private var loadTask: Task<Void, Never>?
    private var stopTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?

    private init() {}

    /// Plays the theme song for `item`, or keeps the current song going
    /// if `item` shares it.
    func play(for item: BaseItemDto) {
        stopTask?.cancel()
        stopTask = nil

        guard Defaults[.Customization.playThemeSongs],
              let itemID = item.id,
              let userSession = Container.shared.currentUserSession()
        else {
            stop()
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            let parameters = Paths.GetThemeSongsParameters(
                userID: userSession.user.id,
                isInheritFromParent: true
            )
            let request = Paths.getThemeSongs(itemID: itemID, parameters: parameters)

            let response: ThemeMediaResult
            do {
                response = try await userSession.client.send(request).value
            } catch {
                logger.error(
                    "Theme song lookup failed",
                    metadata: [
                        "item": .stringConvertible(item.displayTitle),
                        "error": .stringConvertible(error.localizedDescription),
                    ]
                )
                return
            }

            guard !Task.isCancelled else { return }

            let songs = response.items ?? []

            logger.info(
                "Theme song lookup",
                metadata: [
                    "item": .stringConvertible(item.displayTitle),
                    "found": .stringConvertible(songs.count),
                    "file": .stringConvertible(songs.first?.path ?? "none"),
                ]
            )

            guard let songID = songs.first?.id else {
                fadeOutAndStop()
                return
            }

            // Same song as the page we came from: keep it playing.
            guard songID != currentSongID else { return }

            let streamRequest = Paths.getAudioStream(
                itemID: songID,
                parameters: .init(isStatic: true)
            )

            guard let url = userSession.client.url(with: streamRequest, queryAPIKey: true) else { return }

            start(url: url, songID: songID)
        }
    }

    /// Fades out shortly, unless another page with the same song opens first.
    func stopSoon() {
        stopTask?.cancel()
        stopTask = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            fadeOutAndStop()
        }
    }

    /// Stops immediately, such as when video playback starts.
    func stop() {
        loadTask?.cancel()
        stopTask?.cancel()
        fadeTask?.cancel()
        loadTask = nil
        stopTask = nil
        fadeTask = nil

        statusObservation = nil
        player?.pause()
        player = nil
        currentSongID = nil
    }

    private func start(url: URL, songID: String) {
        fadeTask?.cancel()
        player?.pause()

        let newPlayer = AVPlayer(url: url)
        newPlayer.volume = 0
        player = newPlayer
        currentSongID = songID

        // Report files the Apple TV can't play (for example .ogg or .opus).
        statusObservation = newPlayer.currentItem?.observe(\.status) { [logger] item, _ in
            guard item.status == .failed else { return }
            logger.error(
                "Theme song failed to play",
                metadata: [
                    "songID": .stringConvertible(songID),
                    "error": .stringConvertible(item.error?.localizedDescription ?? "unknown"),
                ]
            )
        }

        newPlayer.play()
        fade(to: Self.volume)
    }

    private func fadeOutAndStop() {
        guard player != nil else {
            stop()
            return
        }

        fade(to: 0) { [weak self] in
            self?.stop()
        }
    }

    private func fade(to target: Float, completion: (() -> Void)? = nil) {
        fadeTask?.cancel()

        guard let player else {
            completion?()
            return
        }

        let startVolume = player.volume

        fadeTask = Task {
            for step in 1 ... Self.fadeSteps {
                try? await Task.sleep(for: Self.fadeStepDuration)
                guard !Task.isCancelled else { return }

                let progress = Float(step) / Float(Self.fadeSteps)
                player.volume = startVolume + (target - startVolume) * progress
            }

            completion?()
        }
    }
}
