import Charts
import SwiftUI

private enum TrendZoomPreset: String, CaseIterable, Identifiable {
    case all = "All"
    case sevenDays = "7D"
    case thirtyDays = "30D"
    case ninetyDays = "90D"

    var id: String { rawValue }

    var visibleDays: Int? {
        switch self {
        case .all:
            return nil
        case .sevenDays:
            return 7
        case .thirtyDays:
            return 30
        case .ninetyDays:
            return 90
        }
    }
}

struct TrendsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var trend: [TrendPoint] = []
    @State private var loadError: Error?
    @State private var hoveredDate: Date?
    @State private var brushedRange: ClosedRange<Date>?
    @State private var zoomPreset: TrendZoomPreset = .all
    @State private var manualZoomRange: ClosedRange<Date>?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Trends")
                .font(.largeTitle.bold())

            if let loadError {
                DataLoadErrorView(error: loadError)
            }

            controls

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(filters.granularity.title) Usage")
                        .font(.headline)

                    Chart(trend) { point in
                        AreaMark(
                            x: .value("Date", point.date),
                            y: .value("Seconds", point.totalSeconds)
                        )
                        .foregroundStyle(.teal.opacity(0.25).gradient)

                        LineMark(
                            x: .value("Date", point.date),
                            y: .value("Seconds", point.totalSeconds)
                        )
                        .foregroundStyle(.teal)

                        if let hoveredPoint,
                           hoveredPoint.id == point.id {
                            PointMark(
                                x: .value("Date", point.date),
                                y: .value("Seconds", point.totalSeconds)
                            )
                            .symbolSize(80)
                            .foregroundStyle(.teal)
                        }
                    }
                    .chartYScale(domain: 0...(trend.map(\.totalSeconds).max() ?? 0) * 1.1)
                    .chartYAxis {
                        AxisMarks(position: .leading)
                    }
                    .chartXScale(domain: effectiveDomain)
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        updateHoveredDate(locationX: location.x, proxy: proxy, geometry: geometry)
                                    case .ended:
                                        hoveredDate = nil
                                    }
                                }
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            updateBrush(
                                                startX: value.startLocation.x,
                                                currentX: value.location.x,
                                                proxy: proxy,
                                                geometry: geometry
                                            )
                                        }
                                )
                        }
                    }
                    .frame(height: 320)

                    if let hoveredPoint {
                        Text("Hover: \(label(for: hoveredPoint.date)) • \(DurationFormatter.short(hoveredPoint.totalSeconds))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let brushedRange {
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Brush Selection")
                            .font(.headline)
                        Text("\(label(for: brushedRange.lowerBound)) → \(label(for: brushedRange.upperBound))")
                            .font(.footnote)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            Button("Apply to Global Date Range") {
                                applyBrushToGlobalFilters(brushedRange)
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Zoom to Brush") {
                                manualZoomRange = brushedRange
                            }
                            .buttonStyle(.bordered)

                            Button("Clear Brush", role: .destructive) {
                                self.brushedRange = nil
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Text("Hover + drag-brush + zoom controls are active. Applying a brush updates global filters used across views.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .task(id: reloadKey) {
            await loadTrend()
        }
    }

    private var controls: some View {
        GlassCard {
            HStack(spacing: 12) {
                Text("Zoom")
                    .font(.headline)

                Picker("Zoom", selection: $zoomPreset) {
                    ForEach(TrendZoomPreset.allCases) { preset in
                        Text(preset.rawValue).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 340)
                .onChange(of: zoomPreset) {
                    manualZoomRange = nil
                }

                Button("Reset Zoom") {
                    zoomPreset = .all
                    manualZoomRange = nil
                }
                .buttonStyle(.bordered)

                Spacer()
            }
        }
    }

    private var reloadKey: String {
        [
            String(filters.startDate.timeIntervalSince1970),
            String(filters.endDate.timeIntervalSince1970),
            filters.granularity.rawValue,
            filters.selectedApps.sorted().joined(separator: "|"),
            filters.selectedCategories.sorted().joined(separator: "|"),
            filters.selectedHeatmapCells
                .sorted {
                    if $0.weekday == $1.weekday {
                        return $0.hour < $1.hour
                    }
                    return $0.weekday < $1.weekday
                }
                .map { "\($0.weekday)-\($0.hour)" }
                .joined(separator: "|")
        ].joined(separator: "::")
    }

    private var hoveredPoint: TrendPoint? {
        guard let hoveredDate else { return nil }

        return trend.min { lhs, rhs in
            abs(lhs.date.timeIntervalSince(hoveredDate)) < abs(rhs.date.timeIntervalSince(hoveredDate))
        }
    }

    private var effectiveDomain: ClosedRange<Date> {
        if let manualZoomRange {
            return manualZoomRange
        }

        let sorted = trend.map(\.date).sorted()
        let fallback = filters.startDate...filters.endDate

        guard let minDate = sorted.first,
              let maxDate = sorted.last else {
            return fallback
        }

        guard let visibleDays = zoomPreset.visibleDays else {
            return minDate...maxDate
        }

        let calendar = Calendar.current
        let candidateStart = calendar.date(byAdding: .day, value: -(visibleDays - 1), to: maxDate) ?? minDate
        let boundedStart = max(candidateStart, minDate)
        return boundedStart...maxDate
    }

    private func updateHoveredDate(locationX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredDate = nil
            return
        }

        let plotRect = geometry[plotFrame]
        let relativeX = locationX - plotRect.origin.x

        guard relativeX >= 0, relativeX <= plotRect.width,
              let date: Date = proxy.value(atX: relativeX) else {
            hoveredDate = nil
            return
        }

        hoveredDate = date
    }

    private func updateBrush(startX: CGFloat, currentX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            return
        }

        let plotRect = geometry[plotFrame]
        let startRelative = startX - plotRect.origin.x
        let currentRelative = currentX - plotRect.origin.x

        guard let startDate: Date = proxy.value(atX: startRelative),
              let currentDate: Date = proxy.value(atX: currentRelative) else {
            return
        }

        let lower = min(startDate, currentDate)
        let upper = max(startDate, currentDate)

        if abs(upper.timeIntervalSince(lower)) < 60 {
            brushedRange = nil
        } else {
            brushedRange = lower...upper
        }
    }

    private func applyBrushToGlobalFilters(_ range: ClosedRange<Date>) {
        let calendar = Calendar.current
        filters.startDate = calendar.startOfDay(for: range.lowerBound)
        filters.endDate = calendar.startOfDay(for: range.upperBound)
    }

    private func label(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func loadTrend() async {
        do {
            loadError = nil
            trend = try await appEnvironment.dataService.fetchTrend(filters: filters.snapshot)
        } catch {
            loadError = error
            trend = []
        }
    }
}
