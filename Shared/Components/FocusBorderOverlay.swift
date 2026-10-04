//
// Bearfin
// FocusBorderOverlay.swift
//

import SwiftUI

#if os(tvOS)
struct FocusBorderButtonStyle: PrimitiveButtonStyle {

    @Environment(\.isFocused)
    private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(isFocused ? Color.green : Color.clear, lineWidth: 4)
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            )
            .onTapGesture { configuration.trigger() }
    }
}
#endif
