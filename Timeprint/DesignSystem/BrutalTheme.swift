import SwiftUI

// MARK: - Timeprint Design System
// Liquid Glass foundation with monospace typography tokens.
// BrutalTheme is kept as the namespace for backward compatibility.

enum BrutalTheme {
    // MARK: Colors — semantic tokens
    /// Window background — let the system draw it for glass to refract properly.
    static let background = Color(nsColor: .windowBackgroundColor)
    /// Card / elevated surface — translucent for glass compositing.
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let surfaceAlt = Color(nsColor: .unemphasizedSelectedContentBackgroundColor)
    static let border = Color.primary.opacity(0.10)
    static let borderStrong = Color.primary.opacity(0.6)
    static let accent = Color.accentColor
    static let accentMuted = Color.accentColor.opacity(0.12)
    static let textPrimary = Color.primary
    static let textSecondary = Color.secondary
    static let textTertiary = Color(nsColor: .tertiaryLabelColor)
    static let danger = Color.red
    static let warning = Color.orange

    // Intensity scale for heatmaps / bars
    static let intensity0 = Color.accentColor.opacity(0.05)
    static let intensity1 = Color.accentColor.opacity(0.20)
    static let intensity2 = Color.accentColor.opacity(0.40)
    static let intensity3 = Color.accentColor.opacity(0.65)
    static let intensity4 = Color.accentColor.opacity(0.90)

    // MARK: Typography — monospace precision tokens (unchanged)
    static let displayFont: Font = .system(size: 28, weight: .black, design: .monospaced)
    static let headingFont: Font = .system(size: 13, weight: .bold, design: .monospaced)
    static let bodyMono: Font = .system(size: 12, weight: .regular, design: .monospaced)
    static let captionMono: Font = .system(size: 10, weight: .medium, design: .monospaced)
    static let metricFont: Font = .system(size: 22, weight: .black, design: .monospaced)
    static let metricSmall: Font = .system(size: 16, weight: .bold, design: .monospaced)
    static let tableHeader: Font = .system(size: 10, weight: .heavy, design: .monospaced)
    static let tableBody: Font = .system(size: 11, weight: .regular, design: .monospaced)

    // MARK: App Color Palette — colorblind-safe, 12-color ring
    /// 12 hues evenly spaced around the color wheel, tuned for colorblind safety.
    static let appColors: [Color] = [
        Color(red: 0.22, green: 0.52, blue: 0.90),   // blue
        Color(red: 0.90, green: 0.35, blue: 0.25),   // red
        Color(red: 0.18, green: 0.72, blue: 0.53),   // teal
        Color(red: 0.95, green: 0.60, blue: 0.10),   // amber
        Color(red: 0.58, green: 0.34, blue: 0.80),   // purple
        Color(red: 0.92, green: 0.42, blue: 0.58),   // coral
        Color(red: 0.20, green: 0.65, blue: 0.78),   // cyan
        Color(red: 0.68, green: 0.58, blue: 0.20),   // olive
        Color(red: 0.40, green: 0.72, blue: 0.35),   // green
        Color(red: 0.82, green: 0.30, blue: 0.60),   // magenta
        Color(red: 0.35, green: 0.48, blue: 0.68),   // steel
        Color(red: 0.78, green: 0.56, blue: 0.32),   // tan
    ]
    static let appColorOther = Color(red: 0.72, green: 0.74, blue: 0.76)

    /// Deterministic color for an app name. Same app always gets the same color
    /// regardless of sort order, across all charts and sessions.
    static func color(for appName: String) -> Color {
        if appName == "Other" { return appColorOther }
        let hash = appName.utf8.reduce(0) { ($0 &* 31) &+ UInt(Int8(bitPattern: $1)) }
        return appColors[Int(hash % UInt(appColors.count))]
    }

    /// Legacy overload — positional fallback when ordered list matters (stacked charts).
    static func color(for appName: String, in orderedApps: [String]) -> Color {
        if appName == "Other" { return appColorOther }
        guard let index = orderedApps.firstIndex(of: appName) else { return color(for: appName) }
        return appColors[index % appColors.count]
    }

    // MARK: Semantic Colors
    static let positive = Color.green
    static let negative = Color.red
    static let neutral = Color.gray

    // MARK: Heatmap gradient — 7-stop smooth scale
    static let heatmapGradient: [Color] = [
        Color(red: 0.12, green: 0.14, blue: 0.18),  // level 0 — near-dark
        Color(red: 0.10, green: 0.24, blue: 0.36),  // level 1
        Color(red: 0.08, green: 0.36, blue: 0.50),  // level 2
        Color(red: 0.08, green: 0.50, blue: 0.60),  // level 3
        Color(red: 0.10, green: 0.64, blue: 0.56),  // level 4
        Color(red: 0.22, green: 0.78, blue: 0.46),  // level 5
        Color(red: 0.40, green: 0.90, blue: 0.40),  // level 6 — vivid green
    ]

    /// Interpolated heatmap color for a 0.0–1.0 intensity value.
    static func heatmapColor(intensity: Double) -> Color {
        let clamped = min(max(intensity, 0), 1)
        let scaled = clamped * Double(heatmapGradient.count - 1)
        let lower = Int(scaled)
        let upper = min(lower + 1, heatmapGradient.count - 1)
        let frac = scaled - Double(lower)

        // SwiftUI Color doesn't expose lerp, so we use the two-stop approach
        return lower == upper ? heatmapGradient[lower] :
            Color(
                red: lerp(heatmapGradient[lower], heatmapGradient[upper], frac, \.redComponent),
                green: lerp(heatmapGradient[lower], heatmapGradient[upper], frac, \.greenComponent),
                blue: lerp(heatmapGradient[lower], heatmapGradient[upper], frac, \.blueComponent)
            )
    }

    /// Linear interpolation helper for NSColor component extraction.
    private static func lerp(_ a: Color, _ b: Color, _ t: Double, _ component: KeyPath<NSColor, CGFloat>) -> Double {
        let nsA = NSColor(a).usingColorSpace(.deviceRGB) ?? NSColor(a)
        let nsB = NSColor(b).usingColorSpace(.deviceRGB) ?? NSColor(b)
        return Double(nsA[keyPath: component]) * (1 - t) + Double(nsB[keyPath: component]) * t
    }

    // MARK: Layout
    static let cardPadding: CGFloat = 16
    static let sectionSpacing: CGFloat = 20
    static let borderWidth: CGFloat = 1.0

    // MARK: Glass corner radii
    static let cardCornerRadius: CGFloat = 16
    static let pillCornerRadius: CGFloat = 12

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
