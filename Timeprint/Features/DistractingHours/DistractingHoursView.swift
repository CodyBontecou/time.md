import Charts
import SwiftUI

// MARK: - Heatmap presets

private enum HeatmapPreset: String, CaseIterable, Identifiable {
    case all = "All"
    case workHours = "Work"
    case evening = "Evening"
    case weekend = "Weekend"

    var id: String { rawValue }

    func cells() -> Set<HeatmapCellCoordinate>? {
        switch self {
        case .all: return nil
        case .workHours:
            var set: Set<HeatmapCellCoordinate> = []
            for wd in 1...5 { for h in 9...17 { set.insert(.init(weekday: wd, hour: h)) } }
            return set
        case .evening:
            var set: Set<HeatmapCellCoordinate> = []
            for wd in 0...6 { for h in 18...23 { set.insert(.init(weekday: wd, hour: h)) } }
            return set
        case .weekend:
            var set: Set<HeatmapCellCoordinate> = []
            for wd in [0, 6] { for h in 0...23 { set.insert(.init(weekday: wd, hour: h)) } }
            return set
        }
    }
}

// MARK: - Heatmap Grid Content

private struct HeatmapGridContent: View {
    let cells: [HeatmapCell]
    let weekdayLabels: [String]
    let cellSpacing: CGFloat
    let maxSeconds: Double
    let selectedCells: Set<HeatmapCellCoordinate>
    @Binding var hoveredCell: HeatmapCellCoordinate?
    let onToggleCell: (HeatmapCellCoordinate) -> Void
    let heatmapColor: (Double, Bool) -> Color
    let hourHeader: (Int) -> String

    private let cellSize: CGFloat = 32
    private let labelWidth: CGFloat = 36

    var body: some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            // Hour header — show every 3rd label
            HStack(spacing: cellSpacing) {
                Text("")
                    .frame(width: labelWidth)

                ForEach(0..<24, id: \.self) { hour in
                    Text(hour % 3 == 0 ? hourHeader(hour) : "")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: cellSize, alignment: .center)
                }
            }

            // Rows
            ForEach(0..<7, id: \.self) { weekday in
                HStack(spacing: cellSpacing) {
                    Text(weekdayLabels[weekday])
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: labelWidth, alignment: .leading)

                    ForEach(0..<24, id: \.self) { hour in
                        let cell = cells.first { $0.weekday == weekday && $0.hour == hour }
                        let coord = HeatmapCellCoordinate(weekday: weekday, hour: hour)
                        let isSelected = selectedCells.contains(coord)
                        let isHovered = hoveredCell == coord

                        Button {
                            onToggleCell(coord)
                        } label: {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(heatmapColor(cell?.totalSeconds ?? 0, isSelected))
                                .frame(width: cellSize, height: cellSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(isSelected ? BrutalTheme.accent : isHovered ? Color.white.opacity(0.4) : .clear, lineWidth: isSelected ? 2 : 1)
                                )
                                .scaleEffect(isHovered ? 1.2 : 1.0)
                                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isHovered)
                                .zIndex(isHovered ? 1 : 0)
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            hoveredCell = hovering ? coord : (hoveredCell == coord ? nil : hoveredCell)
                        }
                        .help("\(weekdayLabels[weekday]) \(hourHeader(hour)) — \(DurationFormatter.short(cell?.totalSeconds ?? 0))")
                        .accessibilityLabel("\(weekdayLabels[weekday]) \(hourHeader(hour)), \(DurationFormatter.short(cell?.totalSeconds ?? 0))")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                }
            }
        }
    }
}

// MARK: - View

struct DistractingHoursView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var cells: [HeatmapCell] = []
    @State private var cellAppUsage: [HeatmapCellAppUsage] = []
    @State private var loadError: Error?
    @State private var selectedPreset: HeatmapPreset = .all
    @State private var hoveredCell: HeatmapCellCoordinate?

    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let cellSpacing: CGFloat = 3

    // Max value for color scaling
    private var maxSeconds: Double {
        cells.map(\.totalSeconds).max() ?? 1
    }

    // Selected cell apps (from selected heatmap cells)
    private var selectedCellApps: [(appName: String, totalSeconds: Double)] {
        guard !filters.selectedHeatmapCells.isEmpty else { return [] }

        var totals: [String: Double] = [:]
        for app in cellAppUsage {
            let coord = HeatmapCellCoordinate(weekday: app.weekday, hour: app.hour)
            if filters.selectedHeatmapCells.contains(coord) {
                totals[app.appName, default: 0] += app.totalSeconds
            }
        }
        return totals.sorted { $0.value > $1.value }.prefix(10).map { ($0.key, $0.value) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Heatmap")
                            .font(.system(size: 26, weight: .bold))
                            .foregroundColor(BrutalTheme.textPrimary)
                        Text("WEEKDAY × HOUR ACTIVITY")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(0.8)
                    }
                    Spacer()
                }

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // Preset controls
                presetsRow

                HStack(alignment: .top, spacing: 20) {
                    // Main heatmap
                    VStack(alignment: .leading, spacing: 16) {
                        heatmapGrid
                        colorLegend

                        // Hovered cell tooltip
                        if let hc = hoveredCell,
                           let cell = cells.first(where: { $0.weekday == hc.weekday && $0.hour == hc.hour }),
                           cell.totalSeconds > 0 {
                            HStack(spacing: 12) {
                                Image(systemName: "square.fill")
                                    .foregroundColor(BrutalTheme.heatmapColor(intensity: maxSeconds > 0 ? cell.totalSeconds / maxSeconds : 0))
                                    .font(.system(size: 14))
                                Text("\(weekdayLabels[hc.weekday]) \(hourHeader(hc.hour))")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                Text(DurationFormatter.short(cell.totalSeconds))
                                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textSecondary)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.95)))
                        }
                    }

                    // Side panel: selected cell apps
                    if !filters.selectedHeatmapCells.isEmpty {
                        sidePanelApps
                    }
                }

                // Selection info
                selectionInfo
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    // MARK: - Presets

    private var presetsRow: some View {
        HStack(spacing: 6) {
            ForEach(HeatmapPreset.allCases) { preset in
                let isActive = selectedPreset == preset
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        selectedPreset = preset
                        if let cells = preset.cells() {
                            filters.selectedHeatmapCells = cells
                        } else {
                            filters.selectedHeatmapCells.removeAll()
                        }
                    }
                } label: {
                    Text(preset.rawValue)
                        .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .monospaced))
                        .foregroundColor(isActive ? .white : BrutalTheme.textTertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glass)
                .tint(isActive ? BrutalTheme.accent : .clear)
            }

            Spacer()

            if !filters.selectedHeatmapCells.isEmpty {
                Text("\(filters.selectedHeatmapCells.count) cells")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)

                Button("Clear") {
                    withAnimation {
                        filters.selectedHeatmapCells.removeAll()
                        selectedPreset = .all
                    }
                }
                .buttonStyle(.glass)
                .tint(BrutalTheme.danger)
            }
        }
    }

    // MARK: - Heatmap Grid

    private var heatmapGrid: some View {
        GlassCard {
            HeatmapGridContent(
                cells: cells,
                weekdayLabels: weekdayLabels,
                cellSpacing: cellSpacing,
                maxSeconds: maxSeconds,
                selectedCells: filters.selectedHeatmapCells,
                hoveredCell: $hoveredCell,
                onToggleCell: toggleCell,
                heatmapColor: heatmapColor,
                hourHeader: hourHeader
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ChartAccessibility.heatmapSummary(cells: cells))
    }

    private func hourHeader(_ hour: Int) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ha"
        var components = DateComponents()
        components.hour = hour
        let date = Calendar.current.date(from: components) ?? .now
        return formatter.string(from: date).lowercased()
    }

    // MARK: - Color Legend

    private var colorLegend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)

            ForEach(0..<BrutalTheme.heatmapGradient.count, id: \.self) { step in
                RoundedRectangle(cornerRadius: 3)
                    .fill(BrutalTheme.heatmapGradient[step])
                    .frame(width: 16, height: 12)
            }

            Text("More")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)

            Spacer()
        }
    }

    // MARK: - Side Panel

    private var sidePanelApps: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("TOP APPS IN SELECTION")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                if selectedCellApps.isEmpty {
                    Text("No data for selected cells.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                } else {
                    ForEach(Array(selectedCellApps.enumerated()), id: \.element.appName) { idx, app in
                        HStack(spacing: 8) {
                            Text(String(format: "%02d", idx + 1))
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                                .frame(width: 20)

                            AppNameText(app.appName)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BrutalTheme.textPrimary)
                                .lineLimit(1)

                            Spacer()

                            Text(DurationFormatter.short(app.totalSeconds))
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(BrutalTheme.textSecondary)
                        }
                        .padding(.vertical, 3)

                        if idx < selectedCellApps.count - 1 {
                            Rectangle()
                                .fill(BrutalTheme.border)
                                .frame(height: 0.5)
                        }
                    }
                }
            }
            .frame(minWidth: 240)
        }
    }

    // MARK: - Selection Info

    private var selectionInfo: some View {
        Group {
            if !filters.selectedHeatmapCells.isEmpty {
                let totalSelected = cells
                    .filter { filters.selectedHeatmapCells.contains(HeatmapCellCoordinate(weekday: $0.weekday, hour: $0.hour)) }
                    .reduce(0.0) { $0 + $1.totalSeconds }

                GlassCard {
                    HStack(spacing: 16) {
                        HStack(spacing: 8) {
                            Image(systemName: "square.grid.3x3.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.indigo)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("SELECTED CELLS")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                Text("\(filters.selectedHeatmapCells.count)")
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.teal)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("TOTAL TIME")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                Text(DurationFormatter.short(totalSelected))
                                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                                    .foregroundColor(BrutalTheme.textPrimary)
                            }
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toggleCell(_ coord: HeatmapCellCoordinate) {
        if filters.selectedHeatmapCells.contains(coord) {
            filters.selectedHeatmapCells.remove(coord)
        } else {
            filters.selectedHeatmapCells.insert(coord)
        }
        selectedPreset = .all // Reset preset label on manual selection
    }

    private func heatmapColor(seconds: Double, isSelected: Bool) -> Color {
        let intensity = maxSeconds > 0 ? min(seconds / maxSeconds, 1.0) : 0

        if isSelected {
            // Purple-shifted tint for selected cells
            return Color(hue: 0.7, saturation: 0.6, brightness: 0.3 + intensity * 0.6)
        }

        return BrutalTheme.heatmapColor(intensity: intensity)
    }

    private func load() async {
        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let cellsFetch = appEnvironment.dataService.fetchHeatmap(filters: snapshot)
            async let appUsageFetch = appEnvironment.dataService.fetchHeatmapCellAppUsage(filters: snapshot)

            cells = try await cellsFetch
            cellAppUsage = try await appUsageFetch
        } catch {
            loadError = error
            cells = []
            cellAppUsage = []
        }
    }
}
