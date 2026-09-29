//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import SwiftUI

/// Switches for all of Bearfin's features, shown in Settings → Customize.
struct BearfinSettingsSection: View {

    @Default(.Bearfin.playIntros)
    private var playIntros
    @Default(.Bearfin.skipCredits)
    private var skipCredits
    @Default(.Bearfin.playThemeSongs)
    private var playThemeSongs

    var body: some View {
        Section {
            Toggle(BearfinStrings.playIntros, isOn: $playIntros)

            Toggle(BearfinStrings.skipCredits, isOn: $skipCredits)

            Toggle(BearfinStrings.playThemeSongs, isOn: $playThemeSongs)
        } header: {
            Text(verbatim: "Bearfin")
        } footer: {
            Text(BearfinStrings.settingsFooter)
        }
    }
}
