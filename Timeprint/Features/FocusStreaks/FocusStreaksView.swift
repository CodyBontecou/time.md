import Charts
import SwiftUI

struct FocusStreaksView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var focusDays: [FocusDay] = []
    @State private var loadError: Error?

    private var aggregatedFocusDays: [FocusDay] {
        let calendar = Calendar.current

        switch filters.granularity {
        case .day, .year:
            return focusDays
        case .week:
            var grouped: [Date: (blocks: Int, seconds: Double)] = [:]
            for day in focusDays {
                let weekStart = calendar.dateInterval(of: .weekOfYear, for: day.date)?.start ?? day.date
                grouped[weekStart, default: (0, 0)].blocks += day.focusBlocks
                grouped[weekStart, default: (0, 0)].seconds += day.totalSeconds
            }
            return grouped.map { FocusDay(date: $0.key, focusBlocks: $0.value.blocks, totalSeconds: $0.value.seconds) }
                .sorted { $0.date < $1.date }
        case .month:
            var grouped: [Date: (blocks: Int, seconds: Double)] = [:]
            for day in focusDays {
                let monthStart = calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
                grouped[monthStart, default: (0, 0)].blocks += day.focusBlocks
                grouped[monthStart, default: (0, 0)].seconds += day.totalSeconds
            }
            return grouped.map { FocusDay(date: $0.key, focusBlocks: $0.value.blocks, totalSeconds: $0.value.seconds) }
                .sorted { $0.date < $1.date }
        }
    }

    private var currentStreak: Int {
        aggregatedFocusDays.reversed().prefix { $0.focusBlocks > 0 }.count
    }

    private var longestStreak: Int {
        var maxRun = 0
        var currentRun = 0

        for day in aggregatedFocusDays {
            if day.focusBlocks > 0 {
                currentRun += 1
                maxRun = max(maxRun, currentRun)
            } else {
                currentRun = 0
            }
        }

        return maxRun
    }

    private var streakUnitLabel: String {
        switch filters.granularity {
        case .day, .year: return "days"
        case .week: return "weeks"
        case .month: return "months"
        }
    }

    private var chartTitle: String {
        switch filters.granularity {
        case .day, .year: return "Daily Focus Blocks"
        case .week: return "Weekly Focus Blocks"
        case .month: return "Monthly Focus Blocks"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Focus & Streaks")
                .font(.largeTitle.bold())

            if let loadError {
                DataLoadErrorView(error: loadError)
            }

            HStack(spacing: 12) {
                streakCard(title: "Current", value: "\(currentStreak) \(streakUnitLabel)")
                streakCard(title: "Longest", value: "\(longestStreak) \(streakUnitLabel)")
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(chartTitle)
                        .font(.headline)

                    Chart(aggregatedFocusDays) { day in
                        BarMark(
                            x: .value("Date", day.date),
                            y: .value("Focus Blocks", day.focusBlocks)
                        )
                        .foregroundStyle(.purple.gradient)
                    }
                    .frame(height: 280)
                }
            }

            Spacer()
        }
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    private func streakCard(title: String, value: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title2.bold())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func load() async {
        do {
            loadError = nil
            focusDays = try await appEnvironment.dataService.fetchFocusDays(filters: filters.snapshot)
        } catch {
            loadError = error
            focusDays = []
        }
    }
}
