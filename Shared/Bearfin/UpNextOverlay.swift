//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// What the Up Next card shows: the item coming up, and the action its
/// button performs — the center click on tvOS, a tap everywhere else.
struct UpNextContent {
    let item: BaseItemDto
    let actionTitle: String
    let actionSystemImage: String
    let action: () -> Void

    /// Only set during the end-credits countdown: lets the viewer dismiss
    /// the card and keep watching the credits instead. tvOS handles this
    /// with the remote's Back button; other platforms show an X.
    let dismissAction: (() -> Void)?
}

/// The card shown in place of the playback controls while an intro plays
/// or the end-credits countdown runs. Shows nothing otherwise.
///
/// On tvOS the card's button is a visual label only — the center click and
/// Back button (handled in VideoPlayerContainerView) drive it. On iOS and
/// iPadOS the button and the X are directly tappable, since there's no
/// remote to press.
struct UpNextOverlay: View {

    @EnvironmentObject
    private var manager: MediaPlayerManager

    var body: some View {
        ZStack {
            if let content = manager.upNextContent {
                card(content)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: manager.isShowingUpNext)
    }

    private func card(_ content: UpNextContent) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.nextUp)
                    .font(.callout)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.bearfinYellow)

                Text(content.item.seriesName ?? content.item.displayTitle)
                    .font(.title2)
                    .fontWeight(.bold)
                    .lineLimit(1)

                if content.item.type == .episode, let seasonEpisodeLabel = content.item.seasonEpisodeLabel {
                    Text("\(seasonEpisodeLabel) • \(content.item.displayTitle)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .shadow(color: .black.opacity(0.6), radius: 8)

            Spacer()

            HStack(spacing: 12) {
                #if !os(tvOS)
                if let dismissAction = content.dismissAction {
                    Button(action: dismissAction) {
                        Image(systemName: "xmark")
                            .font(.headline)
                            .padding(14)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                #endif

                #if os(tvOS)
                Label(content.actionTitle, systemImage: content.actionSystemImage)
                    .font(.headline)
                    .padding(.horizontal, 30)
                    .padding(.vertical, 16)
                    .background(.ultraThinMaterial, in: Capsule())
                #else
                Button(action: content.action) {
                    Label(content.actionTitle, systemImage: content.actionSystemImage)
                        .font(.headline)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 14)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                #endif
            }
        }
        .padding(.bottom, 40)
    }
}
