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
import JellyfinAPI
import SwiftUI

/// Plays a single intro (preroll) item served by `/Items/{id}/Intros`,
/// then hands playback off to the queue the feature item would have used.
@MainActor
final class IntroMediaPlayerQueue: MediaPlayerQueue {

    static let identifier = "IntroMediaPlayerQueue"

    let displayTitle: String = ""
    let id: String = IntroMediaPlayerQueue.identifier

    @Published
    var nextItem: MediaPlayerItemProvider?
    @Published
    var previousItem: MediaPlayerItemProvider? = nil

    @Published
    var hasNextItem: Bool = true
    @Published
    var hasPreviousItem: Bool = false

    lazy var hasNextItemPublisher: Published<Bool>.Publisher = $hasNextItem
    lazy var hasPreviousItemPublisher: Published<Bool>.Publisher = $hasPreviousItem
    lazy var nextItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $nextItem
    lazy var previousItemPublisher: Published<MediaPlayerItemProvider?>.Publisher = $previousItem

    weak var manager: MediaPlayerManager? {
        didSet {
            cancellables = []
            guard let manager else { return }

            // Observe `item` rather than `playbackItem`: `item` changes at the start of
            // `playNewItem`, before supplements are rebuilt and before `playbackItem` is set,
            // so the inner queue is in place in time to receive the feature item.
            // `dropFirst` skips the value emitted on subscription.
            manager.$item
                .dropFirst()
                .sink { [weak self] newItem in
                    self?.didReceive(newItem: newItem)
                }
                .store(in: &cancellables)
        }
    }

    private let featureItemID: String
    private let innerQueue: (any MediaPlayerQueue)?
    private var cancellables: [AnyCancellable] = []
    private var hasHandedOff = false

    init(featureProvider: MediaPlayerItemProvider, innerQueue: (any MediaPlayerQueue)?) {
        self.featureItemID = featureProvider.item.id ?? ""
        self.innerQueue = innerQueue
        self.nextItem = featureProvider
    }

    var videoPlayerBody: some PlatformView {
        InlinePlatformView {
            EmptyView()
        } tvOSView: {
            EmptyView()
        }
    }

    private func didReceive(newItem: BaseItemDto) {
        // `item` is set again when `playbackItem` changes, so only hand off once.
        guard !hasHandedOff, newItem.id == featureItemID, let manager else { return }
        hasHandedOff = true

        if let innerQueue {
            let wrapped = AnyMediaPlayerQueue(innerQueue)
            manager.queue = wrapped
            wrapped.manager = manager
        } else {
            manager.queue = nil
        }
    }
}

extension IntroMediaPlayerQueue {

    /// Returns a provider for the first intro the server has for `item`, or `nil`
    /// if intros are disabled, the server has none, or the request fails.
    static func introProvider(for item: BaseItemDto) async -> MediaPlayerItemProvider? {
        guard Defaults[.VideoPlayer.playIntros] else { return nil }
        guard let itemID = item.id, let userSession = Container.shared.currentUserSession() else { return nil }

        do {
            let request = Paths.getIntros(itemID: itemID, userID: userSession.user.id)
            let response = try await userSession.client.send(request)

            guard let introItem = response.value.items?.first else { return nil }

            return MediaPlayerItemProvider(item: introItem) { item, modifyItem in
                try await MediaPlayerItem.build(for: item, modifyItem: modifyItem)
            }
        } catch {
            return nil
        }
    }
}
