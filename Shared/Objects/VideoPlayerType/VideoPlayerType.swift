//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Defaults
import JellyfinAPI

enum VideoPlayerType: String, CaseIterable, Displayable, SupportedCaseIterable, Storable {

    case native
    case vlc

    var displayTitle: String {
        switch self {
        case .native:
            L10n.native
        case .vlc:
            L10n.vlc
        }
    }

    var directPlayProfiles: [DirectPlayProfile] {
        switch self {
        case .native:
            Self._nativeDirectPlayProfiles
        case .vlc:
            Self._vlcDirectPlayProfiles
        }
    }

    var transcodingProfiles: [TranscodingProfile] {
        switch self {
        case .native:
            Self._nativeTranscodingProfiles
        case .vlc:
            Self._vlcTranscodingProfiles
        }
    }

    var subtitleProfiles: [SubtitleProfile] {
        switch self {
        case .native:
            Self._nativeSubtitleProfiles
        case .vlc:
            Self._vlcSubtitleProfiles
        }
    }

    @ArrayBuilder<VideoPlayerType>
    static var supportedCases: [VideoPlayerType] {
        VideoPlayerType.native
        VideoPlayerType.vlc
    }
}
