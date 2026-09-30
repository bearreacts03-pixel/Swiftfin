//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Combine
import Foundation

/// Everything Bearfin adds to the player's state, kept in one place so
/// `MediaPlayerManager` only needs a single stored property for it.
struct BearfinPlaybackState {

    // MARK: Intros

    /// The item waiting to play once every intro in the current chain
    /// finishes. Non-nil for as long as any intro is playing — the first
    /// trailer through the last.
    var pendingFeatureProvider: MediaPlayerItemProvider?

    /// Intros still to play after the current one, in order (a trailer
    /// reel: trailer, trailer, bumper, then the feature).
    var pendingIntroQueue: [MediaPlayerItemProvider] = []

    /// Set just before Bearfin hands off from one intro to the next in the
    /// chain, so the "a new play session always clears pending intros"
    /// rule doesn't wipe out the chain it's in the middle of running.
    var isAdvancingIntroChain = false

    // MARK: Credits

    /// When the current item's end credits begin, from the server's media segments.
    var creditsStart: Duration?

    /// Seconds left before the next item starts, while the end-credits
    /// countdown is running. `nil` when no countdown is showing.
    var creditsCountdown: Int?

    /// Set when the viewer backs out of the countdown, so it stays hidden
    /// until playback moves back before the credits.
    var isCreditsCountdownDismissed = false

    var creditsLookupTask: Task<Void, Never>?
    var creditsCountdownTask: Task<Void, Never>?
    var secondsCancellable: AnyCancellable?
}
