//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI
import SwiftUI

extension VideoPlayer {

    struct PlaybackControls: View {

        @Default(.VideoPlayer.jumpBackwardInterval)
        var jumpBackwardInterval
        @Default(.VideoPlayer.jumpForwardInterval)
        var jumpForwardInterval

        @EnvironmentObject
        var containerState: VideoPlayerContainerState
        @EnvironmentObject
        var manager: MediaPlayerManager

        @Toaster
        var toaster: ToastProxy

        @FocusState
        private var isPlaybackProgressFocused: Bool

        @State
        var speedBoostTimer: Timer?
        @State
        var isSpeedBoosting: Bool = false
        @State
        var pendingJumpWork: DispatchWorkItem?

        var body: some View {
            VStack(spacing: 30) {

                if let feature = manager.pendingFeatureProvider?.item {
                    // While an intro plays, show what's coming up instead of
                    // the intro's own title, timeline, and controls.
                    IntroOverlay(feature: feature)
                        .transition(.opacity)
                } else {
                    Toolbar()
                        .isVisible(
                            containerState.isPresentingOverlay &&
                                !containerState.isScrubbing &&
                                !containerState.isPresentingSupplement
                        )
                        .disabled(containerState.isPresentingSupplement)

                    PlaybackProgress()
                        .focused($isPlaybackProgressFocused)
                        .fixedSize(horizontal: false, vertical: true)
                        .isVisible(
                            (containerState.isPresentingOverlay || containerState.isScrubbing) &&
                                !containerState.isPresentingSupplement
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .edgePadding(.horizontal)
            .focusSection()
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingSupplement)
            .animation(.easeInOut(duration: 0.25), value: containerState.isPresentingOverlay)
            .animation(.linear(duration: 0.1), value: containerState.isScrubbing)
            .animation(.easeInOut(duration: 0.25), value: manager.isPlayingIntro)
            .alert(L10n.closePlayer, isPresented: $containerState.isPresentingCloseConfirmation) {
                Button(L10n.cancel, role: .cancel) {}

                Button(L10n.ok, role: .destructive) {
                    manager.stop()
                }
            } message: {
                Text(L10n.closePlayerWarning)
            }
            .onChange(of: containerState.isPresentingOverlay) {
                isPlaybackProgressFocused = true
            }
            .onChange(of: manager.playbackRequestStatus) {
                if manager.playbackRequestStatus == .paused, !containerState.isPresentingOverlay {
                    containerState.isPresentingOverlay = true
                }
            }
            .onReceive(containerState.containerView?.onPressEvent ?? .init()) { press in
                handlePressEvent(press)
            }
            .onChange(of: containerState.isProgressBarFocused) {
                if !containerState.isProgressBarFocused {
                    containerState.cancelScrub()

                    if isSpeedBoosting {
                        stopSpeedBoost()
                    }
                }
            }
        }
    }
}

extension VideoPlayer.PlaybackControls {

    /// Shown in place of the playback controls while an intro plays.
    /// Pressing select skips the intro.
    struct IntroOverlay: View {

        let feature: BaseItemDto

        var body: some View {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(L10n.nextUp)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.secondary)

                    Text(feature.seriesName ?? feature.displayTitle)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(1)

                    if feature.type == .episode, let seasonEpisodeLabel = feature.seasonEpisodeLabel {
                        Text("\(seasonEpisodeLabel) • \(feature.displayTitle)")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .shadow(color: .black.opacity(0.6), radius: 8)

                Spacer()

                Label(L10n.skipIntro, systemImage: "forward.end.fill")
                    .font(.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .padding(.bottom, 40)
        }
    }
}
