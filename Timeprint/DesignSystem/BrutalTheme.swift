import SwiftUI

// MARK: - Brutal + Teenage Engineering Design System
// Light blue & white palette, monospace typography, sharp edges, industrial precision.

enum BrutalTheme {
    // MARK: Colors
    static let background = Color(red: 0.92, green: 0.95, blue: 0.98)       // #EBF2FA — pale ice blue
    static let surface = Color.white
    static let surfaceAlt = Color(red: 0.96, green: 0.98, blue: 1.0)        // barely-blue white
    static let border = Color.black.opacity(0.12)
    static let borderStrong = Color.black.opacity(0.85)
    static let accent = Color(red: 0.22, green: 0.52, blue: 0.90)           // bright utility blue
    static let accentMuted = Color(red: 0.22, green: 0.52, blue: 0.90).opacity(0.12)
    static let textPrimary = Color(red: 0.08, green: 0.08, blue: 0.10)      // near-black
    static let textSecondary = Color(red: 0.35, green: 0.38, blue: 0.42)    // cool gray
    static let textTertiary = Color(red: 0.55, green: 0.58, blue: 0.62)
    static let danger = Color(red: 0.90, green: 0.25, blue: 0.20)
    static let warning = Color(red: 0.95, green: 0.65, blue: 0.10)

    // Intensity scale for heatmaps / bars
    static let intensity0 = Color(red: 0.94, green: 0.96, blue: 0.98)
    static let intensity1 = Color(red: 0.78, green: 0.88, blue: 0.96)
    static let intensity2 = Color(red: 0.55, green: 0.75, blue: 0.92)
    static let intensity3 = Color(red: 0.32, green: 0.60, blue: 0.88)
    static let intensity4 = Color(red: 0.15, green: 0.42, blue: 0.78)

    // MARK: Typography
    static let displayFont: Font = .system(size: 28, weight: .black, design: .monospaced)
    static let headingFont: Font = .system(size: 13, weight: .bold, design: .monospaced)
    static let bodyMono: Font = .system(size: 12, weight: .regular, design: .monospaced)
    static let captionMono: Font = .system(size: 10, weight: .medium, design: .monospaced)
    static let metricFont: Font = .system(size: 22, weight: .black, design: .monospaced)
    static let metricSmall: Font = .system(size: 16, weight: .bold, design: .monospaced)
    static let tableHeader: Font = .system(size: 10, weight: .heavy, design: .monospaced)
    static let tableBody: Font = .system(size: 11, weight: .regular, design: .monospaced)

    // MARK: App Color Palette (for stacked charts)
    static let appColors: [Color] = [
        Color(red: 0.22, green: 0.52, blue: 0.90),   // utility blue (accent)
        Color(red: 0.90, green: 0.35, blue: 0.25),   // warm red
        Color(red: 0.18, green: 0.72, blue: 0.53),   // teal green
        Color(red: 0.95, green: 0.60, blue: 0.10),   // amber
        Color(red: 0.58, green: 0.34, blue: 0.80),   // purple
        Color(red: 0.92, green: 0.42, blue: 0.58),   // coral pink
        Color(red: 0.20, green: 0.65, blue: 0.78),   // cyan
        Color(red: 0.68, green: 0.58, blue: 0.20),   // olive
    ]
    static let appColorOther = Color(red: 0.72, green: 0.74, blue: 0.76) // neutral gray for "Other"

    /// Returns a consistent color for an app name given the ordered list of top apps.
    static func color(for appName: String, in orderedApps: [String]) -> Color {
        if appName == "Other" { return appColorOther }
        guard let index = orderedApps.firstIndex(of: appName) else { return appColorOther }
        return appColors[index % appColors.count]
    }

    // MARK: Layout
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let borderWidth: CGFloat = 1.5

    // MARK: Numbered Section Label
    static func sectionLabel(_ number: Int, _ title: String) -> String {
        let padded = String(format: "%02d", number)
        return "\(padded) / \(title.uppercased())"
    }
}

// MARK: - View Extensions

extension View {
    /// Brutal section header with numbered prefix
    func brutalSectionHeader(_ number: Int, _ title: String) -> some View {
        HStack(spacing: 0) {
            Text(BrutalTheme.sectionLabel(number, title))
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)
        }
    }
}
