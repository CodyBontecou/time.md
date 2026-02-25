import SwiftUI

/// Card container with padding only — no background to blend seamlessly with the window.
struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(BrutalTheme.cardPadding)
    }
}

/// A tinted card variant — just padding, no background.
struct TintedGlassCard<Content: View>: View {
    private let tint: Color
    private let content: Content

    init(tint: Color = BrutalTheme.accent, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        content
            .padding(BrutalTheme.cardPadding)
    }
}
