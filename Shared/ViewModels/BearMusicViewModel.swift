//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import AVFoundation
import Combine
import CryptoKit
import Foundation
import SwiftUI

class BearMusicViewModel: ObservableObject {

    private let baseURL = "https://music.bearreacts.com"
    private let clientName = "Bearfin"
    private let clientVersion = "1.1"

    @AppStorage("bearmusic_username")
    var savedUsername: String = ""
    @AppStorage("bearmusic_token")
    var savedToken: String = ""
    @AppStorage("bearmusic_salt")
    var savedSalt: String = ""

    @Published
    var isLoggedIn: Bool = false
    @Published
    var isLoading: Bool = false
    @Published
    var errorMessage: String? = nil

    @Published
    var albums: [BearMusicAlbum] = []
    @Published
    var artists: [BearMusicArtist] = []
    @Published
    var playlists: [BearMusicPlaylist] = []
    @Published
    var recentAlbums: [BearMusicAlbum] = []
    @Published
    var randomAlbums: [BearMusicAlbum] = []

    @Published
    var currentSong: BearMusicSong? = nil
    @Published
    var isPlaying: Bool = false
    @Published
    var queue: [BearMusicSong] = []
    @Published
    var queueIndex: Int = 0

    private var player: AVPlayer?
    private var playerObserver: Any?

    init() {
        isLoggedIn = !savedUsername.isEmpty && !savedToken.isEmpty
        if isLoggedIn {
            Task { await loadHome() }
        }
    }

    // MARK: - Auth

    func login(username: String, password: String) async {
        await MainActor.run { isLoading = true
            errorMessage = nil
        }

        let salt = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let token = md5(password + salt)

        let params = authParams(username: username, token: token, salt: salt)
        guard let url = URL(string: "\(baseURL)/rest/ping?\(params)&f=json") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(SubsonicResponse.self, from: data)

            if response.subsonic_response.status == "ok" {
                await MainActor.run {
                    self.savedUsername = username
                    self.savedToken = token
                    self.savedSalt = salt
                    self.isLoggedIn = true
                    self.isLoading = false
                }
                await loadHome()
            } else {
                await MainActor.run {
                    self.errorMessage = response.subsonic_response.error?.message ?? "Login failed"
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = "Could not connect to Bear Music"
                self.isLoading = false
            }
        }
    }

    func logout() {
        savedUsername = ""
        savedToken = ""
        savedSalt = ""
        isLoggedIn = false
        albums = []
        artists = []
        playlists = []
        currentSong = nil
    }

    // MARK: - Data Loading

    func loadHome() async {
        async let recent = fetchAlbums(type: "newest", size: 20)
        async let random = fetchAlbums(type: "random", size: 20)
        let (r, rnd) = await (recent, random)
        await MainActor.run {
            self.recentAlbums = r
            self.randomAlbums = rnd
        }
    }

    func fetchAlbums(type: String = "alphabeticalByName", size: Int = 50) async -> [BearMusicAlbum] {
        guard let url = URL(string: "\(baseURL)/rest/getAlbumList2?\(authParams())&type=\(type)&size=\(size)&f=json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AlbumListResponse.self, from: data)
            return response.subsonic_response.albumList2?.album ?? []
        } catch { return [] }
    }

    func fetchArtists() async -> [BearMusicArtist] {
        guard let url = URL(string: "\(baseURL)/rest/getArtists?\(authParams())&f=json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ArtistsResponse.self, from: data)
            return response.subsonic_response.artists?.index.flatMap(\.artist) ?? []
        } catch { return [] }
    }

    func fetchAlbumSongs(albumId: String) async -> [BearMusicSong] {
        guard let url = URL(string: "\(baseURL)/rest/getAlbum?\(authParams())&id=\(albumId)&f=json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AlbumResponse.self, from: data)
            return response.subsonic_response.album?.song ?? []
        } catch { return [] }
    }

    func fetchArtistAlbums(artistId: String) async -> [BearMusicAlbum] {
        let urlString = "\(baseURL)/rest/getArtist?\(authParams())&id=\(artistId)&f=json"
        print("BEARMUSIC ARTIST URL: \(urlString)")
        guard let url = URL(string: urlString) else {
            print("BEARMUSIC ARTIST URL FAILED TO BUILD")
            return []
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AlbumListResponse.self, from: data)
            return response.subsonic_response.albumList2?.album ?? []
        } catch { return [] }
    }

    func fetchPlaylists() async -> [BearMusicPlaylist] {
        guard let url = URL(string: "\(baseURL)/rest/getPlaylists?\(authParams())&f=json") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(PlaylistsResponse.self, from: data)
            return response.subsonic_response.playlists?.playlist ?? []
        } catch { return [] }
    }

    // MARK: - Playback

    func play(song: BearMusicSong, queue: [BearMusicSong] = []) {
        self.queue = queue.isEmpty ? [song] : queue
        self.queueIndex = queue.firstIndex(where: { $0.id == song.id }) ?? 0
        self.currentSong = song
        startPlayback(song: song)
    }

    private func startPlayback(song: BearMusicSong) {
        guard let url = streamURL(for: song.id) else { return }
        player?.pause()
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        player?.play()
        isPlaying = true

        // Auto advance to next song when done
        if let observer = playerObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        playerObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            self?.playNext()
        }
    }

    func playNext() {
        guard queueIndex + 1 < queue.count else {
            isPlaying = false
            return
        }
        queueIndex += 1
        let next = queue[queueIndex]
        currentSong = next
        startPlayback(song: next)
    }

    func playPrevious() {
        guard queueIndex > 0 else { return }
        queueIndex -= 1
        let prev = queue[queueIndex]
        currentSong = prev
        startPlayback(song: prev)
    }

    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else {
            player?.play()
            isPlaying = true
        }
    }

    func streamURL(for songId: String) -> URL? {
        URL(string: "\(baseURL)/rest/stream?\(authParams())&id=\(songId)&format=mp3&maxBitRate=320")
    }

    func coverArtURL(for coverArtId: String, size: Int = 300) -> URL? {
        URL(string: "\(baseURL)/rest/getCoverArt?\(authParams())&id=\(coverArtId)&size=\(size)")
    }

    // MARK: - Helpers

    private func authParams(username: String? = nil, token: String? = nil, salt: String? = nil) -> String {
        let u = username ?? savedUsername
        let t = token ?? savedToken
        let s = salt ?? savedSalt
        return "u=\(u)&t=\(t)&s=\(s)&v=1.16.1&c=\(clientName)"
    }

    private func md5(_ string: String) -> String {
        let digest = Insecure.MD5.hash(data: Data(string.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Models

struct BearMusicAlbum: Codable, Identifiable {
    let id: String
    let name: String
    let artist: String?
    let artistId: String?
    let coverArt: String?
    let songCount: Int?
    let duration: Int?
    let year: Int?
    var song: [BearMusicSong]?
}

struct BearMusicArtist: Codable, Identifiable {
    let id: String
    let name: String
    let coverArt: String?
    let albumCount: Int?
}

struct BearMusicSong: Codable, Identifiable {
    let id: String
    let title: String
    let artist: String?
    let album: String?
    let coverArt: String?
    let duration: Int?
    let track: Int?
}

struct BearMusicPlaylist: Codable, Identifiable {
    let id: String
    let name: String
    let songCount: Int?
    let duration: Int?
    let coverArt: String?
}

// MARK: - API Response Models

struct SubsonicResponse: Codable {
    let subsonic_response: SubsonicStatus
    enum CodingKeys: String, CodingKey {
        case subsonic_response = "subsonic-response"
    }
}

struct SubsonicStatus: Codable {
    let status: String
    let error: SubsonicError?
    let albumList2: AlbumList2?
    let artists: ArtistsContainer?
    let album: BearMusicAlbum?
    let artist: ArtistDetail?
    let playlists: PlaylistsContainer?
}

struct SubsonicError: Codable {
    let message: String
}

struct AlbumList2: Codable {
    let album: [BearMusicAlbum]?
}

struct ArtistsContainer: Codable {
    let index: [ArtistIndex]
}

struct ArtistIndex: Codable {
    let artist: [BearMusicArtist]
}

struct PlaylistsContainer: Codable {
    let playlist: [BearMusicPlaylist]?
}

struct AlbumListResponse: Codable {
    let subsonic_response: SubsonicStatus
    enum CodingKeys: String, CodingKey {
        case subsonic_response = "subsonic-response"
    }
}

struct ArtistsResponse: Codable {
    let subsonic_response: SubsonicStatus
    enum CodingKeys: String, CodingKey {
        case subsonic_response = "subsonic-response"
    }
}

struct AlbumResponse: Codable {
    let subsonic_response: SubsonicStatus
    enum CodingKeys: String, CodingKey {
        case subsonic_response = "subsonic-response"
    }
}

struct ArtistDetailStatus: Codable {
    let status: String
    let artist: ArtistDetail?
}

struct ArtistDetailResponse: Codable {
    let subsonicResponse: ArtistDetailStatus
    enum CodingKeys: String, CodingKey {
        case subsonicResponse = "subsonic-response"
    }
}

struct ArtistDetail: Codable {
    let id: String
    let name: String
    let albumCount: Int?
    let album: [BearMusicAlbum]?
}

struct PlaylistsResponse: Codable {
    let subsonic_response: SubsonicStatus
    enum CodingKeys: String, CodingKey {
        case subsonic_response = "subsonic-response"
    }
}
