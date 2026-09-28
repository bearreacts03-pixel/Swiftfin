//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Defaults
import FactoryKit
import Foundation
import JellyfinAPI

// Bearfin's intro and end-credits features for the player.
//
// Swiftfin's MediaPlayerManager.swift only calls the `bearfin...` hooks below,
// each marked with a "Bearfin" comment there. Everything else lives here.

// MARK: - Public API

extension MediaPlayerManager {

    /// The item waiting to play once the current intro finishes.
    var pendingFeatureProvider: MediaPlayerItemProvider? {
        bearfin.pendingFeatureProvider
    }

    /// Whether an intro is currently playing ahead of the requested item.
    var isPlayingIntro: Bool {
        bearfin.pendingFeatureProvider != nil
    }

    /// Seconds left in the end-credits countdown, or `nil` when none is running.
    var creditsCountdown: Int? {
        bearfin.creditsCountdown
    }

    /// What the Up Next card should show right now, if anything.
    var upNextContent: UpNextContent? {
        if let feature = bearfin.pendingFeatureProvider?.item {
            return UpNextContent(
                item: feature,
                actionTitle: BearfinStrings.skipIntro,
                actionSystemImage: "forward.end.fill"
            )
        }

        if let countdown = bearfin.creditsCountdown, let nextItem = queue?.nextItem?.item {
            return UpNextContent(
                item: nextItem,
                actionTitle: BearfinStrings.startingIn(countdown),
                actionSystemImage: "play.fill"
            )
        }

        return nil
    }

    var isShowingUpNext: Bool {
        upNextContent != nil
    }

    /// Skips the current intro and starts the requested item.
    func skipIntro() {
        guard let featureProvider = bearfin.pendingFeatureProvider else { return }
        playNewItem(provider: featureProvider)
    }

    /// Plays the next item in the queue right away, from the credits countdown.
    func playNextFromCredits() {
        guard let nextItem = queue?.nextItem else {
            cancelCreditsCountdown()
            return
        }

        cancelCreditsCountdown()
        // Keep the countdown from restarting while the next item loads.
        bearfin.isCreditsCountdownDismissed = true

        // Report the current item as finished so the server marks it played
        // instead of saving a resume position in the credits.
        if let runtime = item.runtime {
            seconds = runtime
        }

        playNewItem(provider: nextItem)
    }

    /// Hides the countdown and lets the credits keep playing.
    func dismissCreditsCountdown() {
        cancelCreditsCountdown()
        bearfin.isCreditsCountdownDismissed = true
    }
}

// MARK: - Hooks called from MediaPlayerManager

extension MediaPlayerManager {

    /// Called from both initializers.
    func bearfinSetUp() {
        bearfin.secondsCancellable = secondsBox.$value
            .sink { [weak self] seconds in
                self?.creditsSecondsDidChange(seconds)
            }
    }

    /// Called whenever a new playback item is set.
    func bearfinPlaybackItemDidChange(_ playbackItem: MediaPlayerItem) {
        resetCredits(for: playbackItem)
    }

    /// Called at the start of `playNewItem`.
    func bearfinWillPlayNewItem() {
        cancelCreditsCountdown()

        // Intros only play when a playback session starts, so anything
        // played within the session (autoplay, next/previous, the episode
        // picker, or the feature after its intro) starts directly.
        bearfin.pendingFeatureProvider = nil
    }

    /// Called when playback stops.
    func bearfinWillStop() {
        cancelCreditsCountdown()
    }

    /// Called after an item is rebuilt (audio, subtitle, or bitrate change).
    func bearfinDidRebuild(_ newItem: MediaPlayerItem) {
        // A rebuilt intro must stay unreported, like the original.
        if isPlayingIntro {
            newItem.observers.removeAll { $0 is MediaProgressObserver }
        }
    }

    /// Called when playback ends. Returns `true` if Bearfin handled it.
    ///
    /// An intro always continues into its feature, regardless of the
    /// autoplay setting or whether the intro reports a runtime.
    func bearfinHandleEnded() async -> Bool {
        guard let featureProvider = bearfin.pendingFeatureProvider else { return false }

        // Ended early (VLC can report this before the real end): ignore.
        if let runtime = item.runtime, (runtime - seconds) > .seconds(1) {
            return true
        }

        await playNewItem(provider: featureProvider)
        return true
    }

    /// Builds the first item of a playback session: an intro when one should
    /// play, otherwise the item itself.
    ///
    /// Intros are skipped when disabled in settings, when resuming partway
    /// through, or when the server has none or the intro fails to load.
    func bearfinStartingPlaybackItem(for provider: MediaPlayerItemProvider) async throws -> MediaPlayerItem {
        ThemeSongPlayer.shared.stop()

        let isResuming = (provider.resolvedItem.startSeconds ?? .zero) > .zero

        if !isResuming,
           let introProvider = await Self.introProvider(for: provider.item),
           let introItem = try? await introProvider()
        {
            // Intros are not reported to the server, so they never
            // gain a play count, a resume position, or "played" status.
            introItem.observers.removeAll { $0 is MediaProgressObserver }

            bearfin.pendingFeatureProvider = provider
            return introItem
        }

        bearfin.pendingFeatureProvider = nil
        return try await provider()
    }

    /// Handles the center click on tvOS. Returns `true` if Bearfin handled it.
    func bearfinHandleSelect() -> Bool {
        if isPlayingIntro {
            skipIntro()
            return true
        }

        if creditsCountdown != nil {
            playNextFromCredits()
            return true
        }

        return false
    }

    /// Handles the Back button on tvOS. Returns `true` if Bearfin handled it.
    func bearfinHandleMenu() -> Bool {
        guard creditsCountdown != nil else { return false }
        dismissCreditsCountdown()
        return true
    }
}

// MARK: - Intros

extension MediaPlayerManager {

    /// Returns a provider for the first intro the server has for `item`, or `nil`
    /// if intros are disabled, the server has none, or the request fails.
    private static func introProvider(for item: BaseItemDto) async -> MediaPlayerItemProvider? {
        guard Defaults[.Bearfin.playIntros] else { return nil }
        guard let itemID = item.id, let userSession = Container.shared.currentUserSession() else { return nil }

        do {
            let request = Paths.getIntros(itemID: itemID, userID: userSession.user.id)
            let response = try await userSession.client.send(request)

            guard let introItem = response.value.items?.first else { return nil }

            return MediaPlayerItemProvider(item: introItem) { item, modifyItem in
                try await MediaPlayerItem.build(for: item) { item in
                    // Always start an intro from the beginning.
                    item.userData?.playbackPositionTicks = .zero
                    modifyItem?(&item)
                }
            }
        } catch {
            return nil
        }
    }
}

// MARK: - Credits

extension MediaPlayerManager {

    /// How long the Up Next countdown runs once the end credits start.
    private static let creditsCountdownLength = 5

    /// The countdown has an on-screen card only on tvOS so far.
    private static let supportsCreditsCountdown: Bool = {
        #if os(tvOS)
        true
        #else
        false
        #endif
    }()

    // Only touch `bearfin` when something actually changes: every write
    // republishes the manager, and this runs on every playback tick.
    private func cancelCreditsCountdown() {
        if let task = bearfin.creditsCountdownTask {
            task.cancel()
            bearfin.creditsCountdownTask = nil
        }

        if bearfin.creditsCountdown != nil {
            bearfin.creditsCountdown = nil
        }
    }

    /// Looks up where the credits start for a newly playing item.
    private func resetCredits(for playbackItem: MediaPlayerItem) {
        bearfin.creditsLookupTask?.cancel()
        cancelCreditsCountdown()
        bearfin.creditsStart = nil
        bearfin.isCreditsCountdownDismissed = false

        guard Self.supportsCreditsCountdown,
              Defaults[.Bearfin.skipCredits],
              !isPlayingIntro,
              let itemID = playbackItem.baseItem.id,
              let userSession = Container.shared.currentUserSession()
        else { return }

        bearfin.creditsLookupTask = Task { [weak self] in
            let request = Paths.getItemSegments(itemID: itemID, includeSegmentTypes: [.outro])
            guard let response = try? await userSession.client.send(request) else { return }
            guard !Task.isCancelled, let self else { return }

            let start = response.value.items?
                .compactMap(\.startTicks)
                .min()
                .map { Duration.ticks($0) }

            self.bearfin.creditsStart = start

            self.logger.info(
                "Credits lookup",
                metadata: [
                    "itemID": .stringConvertible(itemID),
                    "creditsStart": .stringConvertible(start.map { "\($0)" } ?? "none"),
                ]
            )
        }
    }

    private func creditsSecondsDidChange(_ seconds: Duration) {
        guard let creditsStart = bearfin.creditsStart, !isPlayingIntro else { return }

        guard seconds >= creditsStart else {
            // Moved back before the credits: re-arm the countdown.
            cancelCreditsCountdown()

            if bearfin.isCreditsCountdownDismissed {
                bearfin.isCreditsCountdownDismissed = false
            }
            return
        }

        guard bearfin.creditsCountdown == nil,
              !bearfin.isCreditsCountdownDismissed,
              playbackRequestStatus == .playing,
              queue?.nextItem != nil,
              (try? authenticatedUser.data.configuration?.enableNextEpisodeAutoPlay) == true
        else { return }

        startCreditsCountdown()
    }

    private func startCreditsCountdown() {
        bearfin.creditsCountdown = Self.creditsCountdownLength

        bearfin.creditsCountdownTask = Task { [weak self] in
            while let self, let remaining = self.bearfin.creditsCountdown, remaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }

                // Pausing holds the countdown.
                if self.playbackRequestStatus == .paused {
                    continue
                }

                self.bearfin.creditsCountdown = remaining - 1
            }

            guard !Task.isCancelled else { return }
            self?.playNextFromCredits()
        }
    }
}
