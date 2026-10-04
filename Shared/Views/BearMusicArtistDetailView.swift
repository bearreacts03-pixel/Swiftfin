//
// Bearfin
// BearMusicArtistDetailView.swift
//

import SwiftUI

struct BearMusicArtistDetailView: View {
    let artist: BearMusicArtist
    @ObservedObject var viewModel: BearMusicViewModel
    @State private var albums: [BearMusicAlbum] = []

    let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
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

                Text(artist.name)
                    .font(.title)
                    .fontWeight(.bold)

                if !albums.isEmpty {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(albums) { album in
                            NavigationLink {
                                BearMusicAlbumDetailView(album: album, viewModel: viewModel)
                            } label: {
                                BearMusicAlbumCard(album: album, viewModel: viewModel)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .padding()
        }
        .navigationTitle(artist.name)
        .task {
            albums = await viewModel.fetchArtistAlbums(artistId: artist.id)
        }
    }
}
