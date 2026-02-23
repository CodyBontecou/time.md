import SwiftUI

struct DistractingHoursView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var cells: [HeatmapCell] = []
    @State private var loadError: Error?

    var body: some View {
        @Bindable var bindableFilters = filters

        VStack(alignment: .leading, spacing: 16) {
            Text("Distracting Hours")
                .font(.largeTitle.bold())

            Text("Tap cells to seed cross-filter selection.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let loadError {
                DataLoadErrorView(error: loadError)
            }

            selectionControls(bindableFilters: bindableFilters)

            GlassCard {
                ScrollView([.horizontal, .vertical]) {
                    LazyVGrid(columns: Array(repeating: GridItem(.fixed(24), spacing: 4), count: 24), spacing: 4) {
                        ForEach(cells) { cell in
                            let coordinate = HeatmapCellCoordinate(weekday: cell.weekday, hour: cell.hour)
                            Button {
                                toggleCell(coordinate, filters: bindableFilters)
                            } label: {
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(color(for: cell, isSelected: bindableFilters.selectedHeatmapCells.contains(coordinate)))
                                    .frame(width: 24, height: 24)
                            }
                            .buttonStyle(.plain)
                            .help("Weekday: \(cell.weekday), Hour: \(cell.hour), Duration: \(DurationFormatter.short(cell.totalSeconds))")
                        }
                    }
                    .padding(6)
                }
                .frame(height: 270)
            }

            Spacer()
        }
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    private func selectionControls(bindableFilters: GlobalFilterStore) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Selection")
                    .font(.headline)

                Text(bindableFilters.selectedHeatmapCells.isEmpty ? "No heatmap cells selected (all cells active)." : "\(bindableFilters.selectedHeatmapCells.count) heatmap cell(s) selected")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Button("Clear Selection") {
                        bindableFilters.selectedHeatmapCells.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .disabled(bindableFilters.selectedHeatmapCells.isEmpty)

                    Button("Select Work Hours") {
                        applyPresetWorkHours(filters: bindableFilters)
                    }
                    .buttonStyle(.bordered)

                    Button("Select Evening") {
                        applyPresetEvening(filters: bindableFilters)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private func toggleCell(_ coordinate: HeatmapCellCoordinate, filters: GlobalFilterStore) {
        if filters.selectedHeatmapCells.contains(coordinate) {
            filters.selectedHeatmapCells.remove(coordinate)
        } else {
            filters.selectedHeatmapCells.insert(coordinate)
        }
    }

    private func applyPresetWorkHours(filters: GlobalFilterStore) {
        var next: Set<HeatmapCellCoordinate> = []
        for weekday in 1...5 {
            for hour in 9...17 {
                next.insert(HeatmapCellCoordinate(weekday: weekday, hour: hour))
            }
        }
        filters.selectedHeatmapCells = next
    }

    private func applyPresetEvening(filters: GlobalFilterStore) {
        var next: Set<HeatmapCellCoordinate> = []
        for weekday in 0...6 {
            for hour in 18...23 {
                next.insert(HeatmapCellCoordinate(weekday: weekday, hour: hour))
            }
        }
        filters.selectedHeatmapCells = next
    }

    private func color(for cell: HeatmapCell, isSelected: Bool) -> Color {
        let normalized = min(max(cell.totalSeconds / 3_600, 0), 1)
        if isSelected {
            return .indigo
        }
        return Color(hue: 0.58, saturation: 0.6, brightness: 0.35 + (normalized * 0.55))
    }

    private func load() async {
        do {
            loadError = nil
            cells = try await appEnvironment.dataService.fetchHeatmap(filters: filters.snapshot)
        } catch {
            loadError = error
            cells = []
        }
    }
}
