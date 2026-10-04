//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct BearMusicHomeView: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    @State
    private var selectedTab = 0
    @State
    private var selectedArtist: BearMusicArtist? = nil
    @State
    private var selectedAlbum: BearMusicAlbum? = nil

    var body: some View {
        if let album = selectedAlbum {
            BearMusicAlbumDetailView(
                album: album,
                viewModel: viewModel,
                onBack: { selectedAlbum = nil }
            )
        } else if let artist = selectedArtist {
            BearMusicArtistDetailView(
                artist: artist,
                viewModel: viewModel,
                onBack: { selectedArtist = nil },
                selectedAlbum: $selectedAlbum
            )
        } else {
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    Text("Home").tag(0)
                    Text("Albums").tag(1)
                    Text("Artists").tag(2)
                    Text("Playlists").tag(3)
                }
                .pickerStyle(.segmented)
                .padding()

                switch selectedTab {
                case 0: BearMusicDiscoverView(viewModel: viewModel, selectedAlbum: $selectedAlbum)
                case 1: BearMusicAlbumsView(viewModel: viewModel, selectedAlbum: $selectedAlbum)
                case 2: BearMusicArtistsView(viewModel: viewModel, selectedArtist: $selectedArtist)
                case 3: BearMusicPlaylistsView(viewModel: viewModel)
                default: EmptyView()
                }

                if let song = viewModel.currentSong {
                    BearMusicNowPlayingBar(viewModel: viewModel, song: song)
                }
            }
            .task { await viewModel.loadHome() }
        }
    }
}

struct BearMusicDiscoverView: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    @Binding
    var selectedAlbum: BearMusicAlbum?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !viewModel.recentAlbums.isEmpty {
                    BearMusicAlbumRow(
                        title: "Recently Added",
                        albums: viewModel.recentAlbums,
                        viewModel: viewModel,
                        selectedAlbum: $selectedAlbum
                    )
                }
                if !viewModel.randomAlbums.isEmpty {
                    BearMusicAlbumRow(
                        title: "Random Pick",
                        albums: viewModel.randomAlbums,
                        viewModel: viewModel,
                        selectedAlbum: $selectedAlbum
                    )
                }
            }
            .padding()
        }
    }
}

struct BearMusicAlbumRow: View {
    let title: String
    let albums: [BearMusicAlbum]
    @ObservedObject
    var viewModel: BearMusicViewModel
    @Binding
    var selectedAlbum: BearMusicAlbum?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.title2).fontWeight(.bold)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(albums) { album in
                        Button { selectedAlbum = album } label: {
                            BearMusicAlbumCard(album: album, viewModel: viewModel)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

struct BearMusicAlbumCard: View {
    let album: BearMusicAlbum
    @ObservedObject
    var viewModel: BearMusicViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AsyncImage(url: album.coverArt.flatMap { viewModel.coverArtURL(for: $0) }) { image in
                image.resizable().aspectRatio(1, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.3))
                    .overlay(Image(systemName: "music.note").font(.title))
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(album.name).font(.caption).fontWeight(.semibold).lineLimit(1)
            Text(album.artist ?? "Unknown").font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(width: 150)
    }
}

struct BearMusicAlbumsView: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    @Binding
    var selectedAlbum: BearMusicAlbum?
    @State
    private var albums: [BearMusicAlbum] = []
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(albums) { album in
                    Button { selectedAlbum = album } label: {
                        BearMusicAlbumCard(album: album, viewModel: viewModel)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .task { albums = await viewModel.fetchAlbums() }
    }
}

struct BearMusicArtistsView: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    @Binding
    var selectedArtist: BearMusicArtist?
    @State
    private var artists: [BearMusicArtist] = []
    let columns = [GridItem(.adaptive(minimum: 200), spacing: 16)]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(artists) { artist in
                    Button {
                        selectedArtist = artist
                    } label: {
                        VStack(spacing: 8) {
                            AsyncImage(url: artist.coverArt.flatMap { viewModel.coverArtURL(for: $0, size: 150) }) { image in
                                image.resizable().aspectRatio(1, contentMode: .fill)
                            } placeholder: {
                                Circle().fill(Color.secondary.opacity(0.3))
                                    .overlay(Image(systemName: "music.mic").font(.title))
                            }
                            .frame(width: 150, height: 150)
                            .clipShape(Circle())

                            Text(artist.name).fontWeight(.semibold).lineLimit(1)
                            if let count = artist.albumCount {
                                Text("\(count) albums").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding()
        }
        .task { artists = await viewModel.fetchArtists() }
    }
}

struct BearMusicPlaylistsView: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    @State
    private var playlists: [BearMusicPlaylist] = []

    var body: some View {
        List(playlists) { playlist in
            HStack {
                AsyncImage(url: playlist.coverArt.flatMap { viewModel.coverArtURL(for: $0, size: 60) }) { image in
                    image.resizable().aspectRatio(1, contentMode: .fill)
                } placeholder: {
                    RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.3))
                        .overlay(Image(systemName: "music.note.list").font(.caption))
                }
                .frame(width: 50, height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                VStack(alignment: .leading) {
                    Text(playlist.name).fontWeight(.semibold)
                    if let count = playlist.songCount {
                        Text("\(count) songs").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .task { playlists = await viewModel.fetchPlaylists() }
    }
}

struct BearMusicAlbumDetailView: View {
    let album: BearMusicAlbum
    @ObservedObject
    var viewModel: BearMusicViewModel
    let onBack: () -> Void
    @State
    private var songs: [BearMusicSong] = []

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: album.coverArt.flatMap { viewModel.coverArtURL(for: $0, size: 400) }) { image in
                        image.resizable().aspectRatio(1, contentMode: .fit)
                    } placeholder: {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.secondary.opacity(0.3))
                            .overlay(Image(systemName: "music.note").font(.largeTitle))
                    }
                    .frame(maxWidth: 300)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                    VStack(spacing: 4) {
                        Text(album.name).font(.title2).fontWeight(.bold)
                        Text(album.artist ?? "Unknown Artist").foregroundStyle(.secondary)
                        if let year = album.year {
                            Text(String(year)).foregroundStyle(.secondary).font(.caption)
                        }
                    }

                    Button {
                        if !songs.isEmpty {
                            viewModel.play(song: songs[0], queue: songs)
                        }
                    } label: {
                        Label("Play All", systemImage: "play.fill")
                            .padding(.horizontal, 24).padding(.vertical, 12)
                            .background(Color.green).foregroundStyle(.white)
                            .clipShape(Capsule())
                    }

                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(songs.enumerated()), id: \.element.id) { index, song in
                            Button {
                                viewModel.play(song: song, queue: songs)
                            } label: {
                                HStack {
                                    Text("\(index + 1)").font(.caption).foregroundStyle(.secondary).frame(width: 24)
                                    VStack(alignment: .leading) {
                                        Text(song.title).fontWeight(.medium)
                                        if let artist = song.artist {
                                            Text(artist).font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if let duration = song.duration {
                                        Text(String(format: "%d:%02d", duration / 60, duration % 60))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 10).padding(.horizontal)
                            }
                            .buttonStyle(.plain)
                            Divider().padding(.leading)
                        }
                    }
                }
                .padding()
                .padding(.top, 100)
            }

            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 100)
            .padding(.leading)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        #if os(tvOS)
        .onExitCommand { onBack() }
        #endif
        .task { songs = await viewModel.fetchAlbumSongs(albumId: album.id) }
    }
}

struct BearMusicArtistDetailView: View {
    let artist: BearMusicArtist
    @ObservedObject
    var viewModel: BearMusicViewModel
    let onBack: () -> Void
    @Binding
    var selectedAlbum: BearMusicAlbum?
    @State
    private var albums: [BearMusicAlbum] = []
    let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        ZStack(alignment: .topLeading) {
            ScrollView {
                VStack(spacing: 20) {
                    AsyncImage(url: artist.coverArt.flatMap { viewModel.coverArtURL(for: $0, size: 300) }) { image in
                        image.resizable().aspectRatio(1, contentMode: .fill)
                    } placeholder: {
                        Circle().fill(Color.secondary.opacity(0.3))
                            .overlay(Image(systemName: "music.mic").font(.largeTitle))
                    }
                    .frame(width: 200, height: 200)
                    .clipShape(Circle())

                    Text(artist.name).font(.title).fontWeight(.bold)

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums) { album in
                            Button { selectedAlbum = album } label: {
                                BearMusicAlbumCard(album: album, viewModel: viewModel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
                .padding()
                .padding(.top, 100)
            }

            Button(action: onBack) {
                Label("Back", systemImage: "chevron.left")
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .padding(.top, 100)
            .padding(.leading)
        }
        .background(Color.black)
        .ignoresSafeArea()
        .toolbar(.hidden, for: .navigationBar)
        #if os(tvOS)
        .onExitCommand { onBack() }
        #endif
        .task {
            albums = await viewModel.fetchArtistAlbums(artistId: artist.id)
        }
    }
}

struct BearMusicNowPlayingBar: View {
    @ObservedObject
    var viewModel: BearMusicViewModel
    let song: BearMusicSong

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: song.coverArt.flatMap { viewModel.coverArtURL(for: $0, size: 60) }) { image in
                image.resizable().aspectRatio(1, contentMode: .fill)
            } placeholder: {
                RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.3))
            }
            .frame(width: 44, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(song.title).fontWeight(.semibold).lineLimit(1)
                Text(song.artist ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Button { viewModel.togglePlayPause() } label: {
                Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill").font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal).padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }
}
