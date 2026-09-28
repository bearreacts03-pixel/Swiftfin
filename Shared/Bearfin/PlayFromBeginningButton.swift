//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import JellyfinAPI
import SwiftUI

/// A round button next to Play that restarts an item from 0:00.
/// Only shown when the item has a saved spot to resume from.
struct PlayFromBeginningButton: View {

    private static let focusID = "itemView-playFromBeginning"

    @ObservedObject
    var provider: ItemContentGroupProvider

    let focusedButton: FocusState<String?>.Binding

    @Router
    private var router

    private var hasResumePosition: Bool {
        (provider.mediaPlayerItemProvider?.item.userData?.playbackPositionTicks ?? 0) > 0
    }

    var body: some View {
        if hasResumePosition {
            Button {
                play()
            } label: {
                Label(L10n.playFromBeginning, systemImage: "gobackward")
                    .labelStyle(ItemActionButtonLabelStyle())
            }
            .buttonBorderShape(.capsule)
            .buttonStyle(BasicHoverButtonStyle())
            .font(.title3)
            .fontWeight(.semibold)
            .disabled(provider.mediaPlayerItemProvider == nil)
            .coordinatedFocus(Self.focusID, selection: focusedButton)
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func play() {
        guard let mediaPlayerItemProvider = provider.mediaPlayerItemProvider?.modifyingItem({
            $0.userData?.playbackPositionTicks = 0
        }) else { return }

        let queue: (any MediaPlayerQueue)? = mediaPlayerItemProvider.item.type == .episode ?
            EpisodeMediaPlayerQueue(episode: mediaPlayerItemProvider.item) : nil

        router.route(
            to: .videoPlayer(
                provider: mediaPlayerItemProvider,
                queue: queue
            )
        )
    }
}
