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

    /// The item waiting to play once the current intro finishes.
    /// Non-nil only while an intro is playing.
    var pendingFeatureProvider: MediaPlayerItemProvider?

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
