import SwiftUI

// MARK: - Timing-style Details / Timeline View
// Vertical timeline showing individual app usage entries with durations and app icons.

struct TimingDetailsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var rawSessions: [RawSession] = []
    @State private var contextSwitches: [ContextSwitchPoint] = []
    @State private var transitions: [AppTransition] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var selectedApp: String?

    private var filteredSessions: [RawSession] {
        if let selectedApp {
            return rawSessions.filter { $0.appName == selectedApp }
        }
        return rawSessions
    }

    private var uniqueApps: [String] {
        Array(Set(rawSessions.map(\.appName))).sorted()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            headerSection
            filterBar

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 300)
            } else if let loadError {
                DataLoadErrorView(error: loadError)
            } else {
                HStack(alignment: .top, spacing: 20) {
                    // Main timeline
                    timelineSection
                        .frame(maxWidth: .infinity)

                    // Sidebar stats
                    ScrollView {
                        sidebarStats
                    }
                    .scrollIndicators(.never)
                    .frame(width: 260)
                }
            }
        }
        .task(id: "\(filters.rangeLabel)\(filters.granularity.rawValue)\(filters.refreshToken)") {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Details")
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)

            HStack(spacing: 8) {
                Text(filters.rangeLabel.uppercased())
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.8)

                Text("--")
                    .foregroundColor(BrutalTheme.textTertiary)

                Text("\(filteredSessions.count) sessions")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.accent)
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            // All apps button
            Button {
                selectedApp = nil
            } label: {
                Text("All Apps")
                    .font(.system(size: 11, weight: selectedApp == nil ? .bold : .medium))
                    .foregroundColor(selectedApp == nil ? .white : BrutalTheme.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selectedApp == nil ? BrutalTheme.accent : Color.clear)
                    )
            }
            .buttonStyle(.plain)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(uniqueApps.prefix(15), id: \.self) { appName in
                        Button {
                            selectedApp = selectedApp == appName ? nil : appName
                        } label: {
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(BrutalTheme.color(for: appName))
                                    .frame(width: 6, height: 6)
                                AppNameText(appName)
                                    .font(.system(size: 11, weight: selectedApp == appName ? .bold : .medium))
                                    .foregroundColor(selectedApp == appName ? .white : BrutalTheme.textSecondary)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(selectedApp == appName ? BrutalTheme.color(for: appName) : Color.clear)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Spacer()
        }
    }

    // MARK: - Timeline Section

    private var timelineSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("TIMELINE")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)
                    .padding(.bottom, 12)

                if filteredSessions.isEmpty {
                    Text("No sessions recorded for this period.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 40)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(filteredSessions.prefix(200).enumerated()), id: \.element.id) { index, session in
                                timelineEntry(session: session, isLast: index == min(filteredSessions.count, 200) - 1)
                            }

                            if filteredSessions.count > 200 {
                                Text("+ \(filteredSessions.count - 200) more sessions")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                                    .padding(.top, 12)
                                    .padding(.leading, 48)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func timelineEntry(session: RawSession, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Time column
            VStack(alignment: .trailing, spacing: 2) {
                Text(timeString(session.startTime))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                Text(timeString(session.endTime))
                    .font(.system(size: 9, weight: .regular, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .frame(width: 44, alignment: .trailing)

            // Timeline dot and line
            VStack(spacing: 0) {
                Circle()
                    .fill(BrutalTheme.color(for: session.appName))
                    .frame(width: 10, height: 10)
                    .padding(.top, 2)

                if !isLast {
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(width: 1)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(width: 10)

            // Session details
            HStack(spacing: 8) {
                #if os(macOS)
                AppIconView(bundleID: session.appName, size: 20)
                #endif

                VStack(alignment: .leading, spacing: 2) {
                    AppNameText(session.appName)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text(DurationFormatter.short(session.durationSeconds))
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                Spacer()

                // Duration bar
                let maxDuration = filteredSessions.map(\.durationSeconds).max() ?? 1
                let barWidth = max(session.durationSeconds / maxDuration * 80, 2)
                RoundedRectangle(cornerRadius: 2)
                    .fill(BrutalTheme.color(for: session.appName).opacity(0.4))
                    .frame(width: barWidth, height: 6)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(BrutalTheme.surface.opacity(0.3))
            )
        }
        .frame(minHeight: 44)
    }

    // MARK: - Sidebar Stats

    private var sidebarStats: some View {
        VStack(spacing: 16) {
            // Session count summary
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUMMARY")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    let totalDuration = filteredSessions.reduce(0) { $0 + $1.durationSeconds }
                    let avgDuration = filteredSessions.isEmpty ? 0 : totalDuration / Double(filteredSessions.count)

                    VStack(alignment: .leading, spacing: 6) {
                        statRow(label: "Total Sessions", value: "\(filteredSessions.count)")
                        statRow(label: "Total Time", value: DurationFormatter.short(totalDuration))
                        statRow(label: "Avg Session", value: DurationFormatter.short(avgDuration))
                        statRow(label: "Unique Apps", value: "\(Set(filteredSessions.map(\.appName)).count)")
                    }
                }
            }

            // Top transitions
            if !transitions.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("TOP TRANSITIONS")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        ForEach(Array(transitions.prefix(8).enumerated()), id: \.element.id) { _, transition in
                            HStack(spacing: 4) {
                                AppNameText(transition.fromApp)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80, alignment: .trailing)

                                Image(systemName: "arrow.right")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(BrutalTheme.textTertiary)

                                AppNameText(transition.toApp)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                    .lineLimit(1)
                                    .frame(maxWidth: 80, alignment: .leading)

                                Spacer()

                                Text("\(transition.count)x")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }

            // Context switching
            if !contextSwitches.isEmpty {
                GlassCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONTEXT SWITCHES")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        let totalSwitches = contextSwitches.reduce(0) { $0 + $1.switchCount }
                        let peakHour = contextSwitches.max(by: { $0.switchCount < $1.switchCount })

                        statRow(label: "Total Switches", value: "\(totalSwitches)")
                        if let peak = peakHour {
                            statRow(label: "Peak Hour", value: formatHour(peak.hour))
                            statRow(label: "Peak Switches", value: "\(peak.switchCount)")
                        }
                    }
                }
            }
        }
    }

    private func statRow(label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
            Spacer()
            Text(verbatim: value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedSessions = appEnvironment.dataService.fetchRawSessions(filters: snapshot)
            async let fetchedSwitches = appEnvironment.dataService.fetchContextSwitchRate(filters: snapshot)
            async let fetchedTransitions = appEnvironment.dataService.fetchAppTransitions(filters: snapshot, limit: 10)

            rawSessions = try await fetchedSessions
            contextSwitches = try await fetchedSwitches
            transitions = try await fetchedTransitions
        } catch {
            loadError = error
        }
    }

    // MARK: - Helpers

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }
}
