//
// Bearfin
// FocusBorderOverlay.swift
//
// Green focus border for tvOS poster cards
//

import SwiftUI

#if os(tvOS)
struct FocusBorderOverlay: View {

    @Environment(\.isFocused)
    private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(Color.green, lineWidth: 4)
            .opacity(isFocused ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
#else
struct FocusBorderOverlay: View {
    var body: some View { EmptyView() }
}
#endif
