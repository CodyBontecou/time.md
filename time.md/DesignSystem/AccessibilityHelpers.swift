import SwiftUI

// MARK: - Reduced Motion Modifier

/// Conditionally applies animation based on user's Reduce Motion preference.
struct ReducedMotionModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? .none : animation)
    }
}

extension View {
    /// Applies animation only when Reduce Motion is off.
    func accessibleAnimation(_ animation: Animation = .easeInOut(duration: 0.3)) -> some View {
        modifier(ReducedMotionModifier(animation: animation))
    }
}

// MARK: - Chart Accessibility Description

/// Generates a VoiceOver summary for a set of chart data points.
enum ChartAccessibility {
    static func trendSummary(points: [(Date, Double)], label: String = "Usage") -> String {
        guard !points.isEmpty else { return "\(label): no data" }
        let total = points.map(\.1).reduce(0, +)
        let avg = total / Double(points.count)
        let maxVal = points.map(\.1).max() ?? 0
        let minVal = points.map(\.1).min() ?? 0
        return "\(label) chart: \(points.count) data points. Average \(DurationFormatter.short(avg)), range \(DurationFormatter.short(minVal)) to \(DurationFormatter.short(maxVal)), total \(DurationFormatter.short(total))"
    }

    static func heatmapSummary(cells: [HeatmapCell]) -> String {
        guard !cells.isEmpty else { return "Heatmap: no data" }
        let total = cells.map(\.totalSeconds).reduce(0, +)
        let busiest = cells.max(by: { $0.totalSeconds < $1.totalSeconds })
        let weekdays = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        if let b = busiest {
            let day = b.weekday < weekdays.count ? weekdays[b.weekday] : "?"
            return "Activity heatmap: \(cells.count) cells, total \(DurationFormatter.short(total)). Busiest: \(day) at \(b.hour):00 (\(DurationFormatter.short(b.totalSeconds)))"
        }
        return "Activity heatmap: \(cells.count) cells, total \(DurationFormatter.short(total))"
    }

    static func barChartSummary(items: [(String, Int)]) -> String {
        guard !items.isEmpty else { return "Bar chart: no data" }
        let total = items.map(\.1).reduce(0, +)
        if let peak = items.max(by: { $0.1 < $1.1 }) {
            return "Bar chart: \(items.count) bars, total \(total). Peak: \(peak.0) with \(peak.1)"
        }
        return "Bar chart: \(items.count) bars, total \(total)"
    }
}
