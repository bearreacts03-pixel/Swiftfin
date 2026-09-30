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
import Logging

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
                actionSystemImage: "forward.end.fill",
                action: { [weak self] in self?.skipIntro() },
                dismissAction: nil
            )
        }

        if let countdown = bearfin.creditsCountdown, let nextItem = queue?.nextItem?.item {
            return UpNextContent(
                item: nextItem,
                actionTitle: BearfinStrings.startingIn(countdown),
                actionSystemImage: "play.fill",
                action: { [weak self] in self?.playNextFromCredits() },
                dismissAction: { [weak self] in self?.dismissCreditsCountdown() }
            )
        }

        return nil
    }

    var isShowingUpNext: Bool {
        upNextContent != nil
    }

    /// Skips the rest of the intro chain — however many trailers or
    /// bumpers are left — and starts the requested item right away.
    func skipIntro() {
        guard let featureProvider = bearfin.pendingFeatureProvider else { return }
        // Goes through the normal (non-chain) path in bearfinWillPlayNewItem,
        // which clears pendingIntroQueue too — one skip always means
        // straight to the feature, not just the next intro.
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
        if isPlayingIntro {
            // Every intro in the chain stays unreported — no play count,
            // no resume position, no "played" status — not just the one
            // played first. Done here (rather than inside the provider's
            // build closure) because that closure is Sendable and can't
            // touch this main-actor-only property directly.
            playbackItem.observers.removeAll { $0 is MediaProgressObserver }
        }

        resetCredits(for: playbackItem)
    }

    /// Called at the start of `playNewItem`.
    func bearfinWillPlayNewItem() {
        cancelCreditsCountdown()

        // Covers every item played in this session — the intro, the
        // feature, and any autoplay after it — so a page reappearing
        // behind the player (which happens on iOS/iPadOS) can't sneak
        // a theme song in over the video's audio.
        ThemeSongPlayer.shared.suspendForVideoPlayback()

        if bearfin.isAdvancingIntroChain {
            // Bearfin itself is hopping from one intro to the next in a
            // chain (trailer → trailer → bumper). Leave the feature and
            // the rest of the queue alone — only a genuinely new play
            // below should clear them.
            bearfin.isAdvancingIntroChain = false
        } else {
            // Intros only play when a playback session starts, so anything
            // played within the session (autoplay, next/previous, the
            // episode picker, or the feature after its intro chain) starts
            // directly.
            bearfin.pendingFeatureProvider = nil
            bearfin.pendingIntroQueue = []
        }
    }

    /// Called when playback stops.
    func bearfinWillStop() {
        cancelCreditsCountdown()
        ThemeSongPlayer.shared.resumeAfterVideoPlayback()
        bearfin.pendingFeatureProvider = nil
        bearfin.pendingIntroQueue = []
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
    /// An intro chain always continues — into the next intro, or into the
    /// feature once the chain is done — regardless of the autoplay setting
    /// or whether the intro reports a runtime.
    func bearfinHandleEnded() async -> Bool {
        guard bearfin.pendingFeatureProvider != nil else { return false }

        // Ended early (VLC can report this before the real end): ignore.
        if let runtime = item.runtime, (runtime - seconds) > .seconds(1) {
            return true
        }

        // More intros queued (a trailer reel): play the next one instead
        // of jumping to the feature yet.
        if !bearfin.pendingIntroQueue.isEmpty {
            let nextIntro = bearfin.pendingIntroQueue.removeFirst()
            bearfin.isAdvancingIntroChain = true
            await playNewItem(provider: nextIntro)
            return true
        }

        guard let featureProvider = bearfin.pendingFeatureProvider else { return false }
        await playNewItem(provider: featureProvider)
        return true
    }

    /// Builds the first item of a playback session: the first intro in the
    /// chain when there is one, otherwise the item itself.
    ///
    /// Intros are skipped when disabled in settings, when resuming partway
    /// through, or when the server has none or the first fails to load.
    func bearfinStartingPlaybackItem(for provider: MediaPlayerItemProvider) async throws -> MediaPlayerItem {
        ThemeSongPlayer.shared.suspendForVideoPlayback()

        let isResuming = (provider.resolvedItem.startSeconds ?? .zero) > .zero

        if !isResuming {
            let introProviders = await Self.introProviders(for: provider.item)

            if let firstIntro = introProviders.first, let firstItem = try? await firstIntro() {
                bearfin.pendingFeatureProvider = provider
                // Everything after the first plays in order as each one ends.
                bearfin.pendingIntroQueue = Array(introProviders.dropFirst())
                return firstItem
            }
        }

        bearfin.pendingFeatureProvider = nil
        bearfin.pendingIntroQueue = []
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

    private static let introLogger = Logger.swiftfin()

    /// Returns providers for every intro the server has for `item`, in the
    /// order they should play — a trailer reel, ending with a bumper — or
    /// an empty list if intros are disabled, the server has none, or the
    /// request fails.
    private static func introProviders(for item: BaseItemDto) async -> [MediaPlayerItemProvider] {
        guard Defaults[.Bearfin.playIntros] else {
            introLogger.info("Intro lookup skipped: Play intros is off in Settings")
            return []
        }
        guard let itemID = item.id, let userSession = Container.shared.currentUserSession() else {
            introLogger.info("Intro lookup skipped: no item ID or no active server session")
            return []
        }

        do {
            let request = Paths.getIntros(itemID: itemID, userID: userSession.user.id)
            let response = try await userSession.client.send(request)
            let items = response.value.items ?? []
            let files = items.map { $0.path ?? "?" }.joined(separator: ", ")

            introLogger.info(
                "Intro lookup",
                metadata: [
                    "item": .stringConvertible(item.displayTitle),
                    "found": .stringConvertible(items.count),
                    "files": .stringConvertible(files.isEmpty ? "none" : files),
                ]
            )

            return items.map { introItem in
                MediaPlayerItemProvider(item: introItem) { item, modifyItem in
                    try await MediaPlayerItem.build(for: item) { item in
                        // Always start each intro in the chain from the beginning.
                        item.userData?.playbackPositionTicks = .zero
                        modifyItem?(&item)
                    }
                    // Not reporting this to the server happens once the
                    // item is actually playing — see bearfinPlaybackItemDidChange.
                }
            }
        } catch {
            // Previously silent: a failed request (bad response, wrong
            // endpoint, plugin not responding) looked identical to "no
            // intro found." Log it so the two are distinguishable.
            introLogger.error(
                "Intro lookup failed",
                metadata: [
                    "item": .stringConvertible(item.displayTitle),
                    "error": .stringConvertible(error.localizedDescription),
                ]
            )
            return []
        }
    }
}

// MARK: - Credits

extension MediaPlayerManager {

    /// How long the Up Next countdown runs once the end credits start.
    private static let creditsCountdownLength = 5

    /// The Up Next card now renders on tvOS, iOS, and iPadOS.
    private static let supportsCreditsCountdown = true

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
