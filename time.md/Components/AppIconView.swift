import SwiftUI

#if os(macOS)
import AppKit

/// Displays a macOS app icon resolved from a bundle identifier.
/// Shows a placeholder SF Symbol when the icon can't be resolved.
struct AppIconView: View {
    let bundleID: String
    var size: CGFloat = 20

    var body: some View {
        Group {
            if bundleID.contains("."),
               let nsImage = AppIconProvider.shared.icon(for: bundleID, size: size) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: size, height: size)
    }
}

/// Combines an app icon and its resolved display name in a horizontal stack.
struct AppIconLabel: View {
    let bundleID: String
    var iconSize: CGFloat = 16

    @Environment(\.appNameDisplayMode) private var mode

    var body: some View {
        HStack(spacing: 6) {
            AppIconView(bundleID: bundleID, size: iconSize)
            Text(AppNameDisplay.displayName(for: bundleID, mode: mode))
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
#endif
