//
// Bearfin
// FocusBorderOverlay.swift
//

import SwiftUI

struct FocusBorderModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(tvOS)
        content
            .overlay(FocusedBorderView())
        #else
        content
        #endif
    }
}

#if os(tvOS)
private struct FocusedBorderView: View {

    @Environment(\.isFocused)
    private var isFocused

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(isFocused ? Color.green : Color.clear, lineWidth: 4)
            .animation(.easeInOut(duration: 0.15), value: isFocused)
    }
}
#endif

extension View {
    func focusBorder() -> some View {
        modifier(FocusBorderModifier())
    }
}
