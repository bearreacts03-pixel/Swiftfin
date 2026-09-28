//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import Foundation

extension Defaults.Keys {

    /// Bearfin's settings. The key names match earlier Bearfin builds,
    /// so saved choices carry over. Stored per user, like Swiftfin's own
    /// user settings.
    enum Bearfin {

        static var playIntros: Key<Bool> {
            userKey("playIntros", default: true)
        }

        static var skipCredits: Key<Bool> {
            userKey("skipCredits", default: true)
        }

        static var playThemeSongs: Key<Bool> {
            userKey("playThemeSongs", default: true)
        }

        /// Same as Swiftfin's private `UserKey` helper: a setting saved
        /// for the signed-in user.
        private static func userKey<Value: Defaults.Serializable>(
            _ name: String,
            default defaultValue: Value
        ) -> Key<Value> {
            Key(name, default: defaultValue, suite: .currentUserSuite)
        }
    }
}
