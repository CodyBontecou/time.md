import SwiftUI

/// Brutalist card container — sharp corners, precise border, no shadows, no blur.
struct GlassCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(BrutalTheme.cardPadding)
            .background(BrutalTheme.surface)
            .overlay(
                Rectangle()
                    .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
            )
    }
}
