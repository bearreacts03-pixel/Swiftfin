//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

// swiftlint:disable hard_coded_display_string

/// Text for Bearfin's own features. Kept apart from Swiftfin's
/// Localizable.strings so Swiftfin's translation updates never conflict.
enum BearfinStrings {

    static let playIntros = String(localized: "bearfin.playIntros", defaultValue: "Play intros")
    static let skipCredits = String(localized: "bearfin.skipCredits", defaultValue: "Skip credits")
    static let playThemeSongs = String(localized: "bearfin.playThemeSongs", defaultValue: "Play theme songs")

    static let settingsFooter = String(
        localized: "bearfin.settingsFooter",
        defaultValue: """
        Play intros plays your server's intros, such as from Local Intros or Projectionist, before movies and when you start an episode. \
        Skip credits counts down to the next episode when the end credits start, using a plugin such as Intro Skipper. \
        Play theme songs plays a movie's or show's theme on its page, such as from Themerr.
        """
    )

    static let skipIntro = String(localized: "bearfin.skipIntro", defaultValue: "Skip intro")

    static func startingIn(_ seconds: Int) -> String {
        String(localized: "bearfin.startingIn", defaultValue: "Starting in \(seconds)")
    }
}

// swiftlint:enable hard_coded_display_string
