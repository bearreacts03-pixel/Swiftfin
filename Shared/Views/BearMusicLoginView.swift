//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import SwiftUI

struct BearMusicLoginView: View {

    @ObservedObject
    var viewModel: BearMusicViewModel

    @State
    private var username = ""
    @State
    private var password = ""

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "music.note.house.fill")
                .font(.system(size: 80))
                .foregroundStyle(.green)

            Text("Bear Music")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Sign in with your Navidrome account")
                .foregroundStyle(.secondary)

            VStack(spacing: 12) {
                TextField("Username", text: $username)
                    
                    .autocorrectionDisabled()
                    .frame(maxWidth: 400)

                SecureField("Password", text: $password)
                    
                    .frame(maxWidth: 400)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            Button {
                Task { await viewModel.login(username: username, password: password) }
            } label: {
                Group {
                    if viewModel.isLoading {
                        ProgressView()
                    } else {
                        Text("Sign In")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: 400)
                .padding()
                .background(Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .disabled(username.isEmpty || password.isEmpty || viewModel.isLoading)
        }
        .padding()
    }
}
