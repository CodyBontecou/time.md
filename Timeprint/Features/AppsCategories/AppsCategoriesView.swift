import Charts
import SwiftUI

private enum BreakdownMode: String, CaseIterable, Identifiable {
    case apps
    case categories

    var id: String { rawValue }

    var title: String { rawValue.uppercased() }
}

struct AppsCategoriesView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode
    @State private var mode: BreakdownMode = .apps
    @State private var apps: [AppUsageSummary] = []
    @State private var categories: [CategoryUsageSummary] = []
    @State private var categoryMappingByApp: [String: String] = [:]
    @State private var categoryDraftByApp: [String: String] = [:]
    @State private var mappingSaveInFlight: Set<String> = []
    @State private var loadError: Error?
    @State private var mappingError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                // ─── Title ───
                Text("APPS & CATEGORIES.")
                    .font(BrutalTheme.displayFont)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .tracking(1)

                Rectangle()
                    .fill(BrutalTheme.borderStrong)
                    .frame(height: 2)

                // Mode toggle
                HStack(spacing: 0) {
                    ForEach(BreakdownMode.allCases) { m in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                mode = m
                            }
                        } label: {
                            Text(m.title)
                                .font(BrutalTheme.captionMono)
                                .tracking(1)
                                .foregroundColor(mode == m ? .white : BrutalTheme.textSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .background(mode == m ? BrutalTheme.accent : Color.clear)
                        }
                        .buttonStyle(.plain)

                        if m != BreakdownMode.allCases.last {
                            Rectangle()
                                .fill(BrutalTheme.border)
                                .frame(width: 1)
                        }
                    }
                }
                .frame(maxWidth: 300)
                .overlay(
                    Rectangle()
                        .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
                )

                if let loadError {
                    DataLoadErrorView(error: loadError)
                }

                // ─── Chart ───
                Group {
                    switch mode {
                    case .apps:
                        appChart
                    case .categories:
                        categoryChart
                    }
                }

                // ─── Cross-filter ───
                quickFilterPanel

                // ─── Mapping editor ───
                mappingEditor
            }
        }
        .task(id: reloadKey) {
            await load()
        }
    }

    // MARK: - Charts

    private var appChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(1, "APP BREAKDOWN"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Chart(apps) { app in
                    BarMark(
                        x: .value("Duration", app.totalSeconds),
                        y: .value("App", AppNameDisplay.displayName(for: app.appName, mode: appNameDisplayMode))
                    )
                    .foregroundStyle(appBarColor(for: app))
                    .cornerRadius(0)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(BrutalTheme.captionMono)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 320)

                Text("SELECT APPS BELOW TO CROSS-FILTER ALL VIEWS.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
            }
        }
    }

    private var categoryChart: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(1, "CATEGORY BREAKDOWN"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Chart(categories) { category in
                    BarMark(
                        x: .value("Duration", category.totalSeconds),
                        y: .value("Category", category.category)
                    )
                    .foregroundStyle(categoryBarColor(for: category))
                    .cornerRadius(0)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisValueLabel {
                            if let name = value.as(String.self) {
                                Text(name)
                                    .font(BrutalTheme.captionMono)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .frame(height: 320)

                Text("SELECT CATEGORIES BELOW TO CROSS-FILTER ALL VIEWS.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)
            }
        }
    }

    // MARK: - Cross-filter panel

    private var quickFilterPanel: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(2, "CROSS-FILTER"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                switch mode {
                case .apps:
                    if apps.isEmpty {
                        Text("NO APPS AVAILABLE.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    } else {
                        chipLayout(
                            rawValues: apps.map(\.appName),
                            selectedValues: filters.selectedApps,
                            onTap: toggleAppSelection
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            filters.selectedApps.removeAll()
                        } label: {
                            Text("CLEAR")
                                .font(BrutalTheme.captionMono)
                                .tracking(0.5)
                                .foregroundColor(filters.selectedApps.isEmpty ? BrutalTheme.textTertiary : BrutalTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(BrutalTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(filters.selectedApps.isEmpty)

                        Text(filters.selectedApps.isEmpty ? "ALL APPS" : "\(filters.selectedApps.count) SELECTED")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(0.5)
                    }

                case .categories:
                    if categories.isEmpty {
                        Text("NO CATEGORIES AVAILABLE.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    } else {
                        chipLayout(
                            values: categories.map(\.category),
                            selectedValues: filters.selectedCategories,
                            onTap: toggleCategorySelection
                        )
                    }

                    HStack(spacing: 12) {
                        Button {
                            filters.selectedCategories.removeAll()
                        } label: {
                            Text("CLEAR")
                                .font(BrutalTheme.captionMono)
                                .tracking(0.5)
                                .foregroundColor(filters.selectedCategories.isEmpty ? BrutalTheme.textTertiary : BrutalTheme.accent)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .overlay(
                                    Rectangle()
                                        .strokeBorder(BrutalTheme.border, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(filters.selectedCategories.isEmpty)

                        Text(filters.selectedCategories.isEmpty ? "ALL CATEGORIES" : "\(filters.selectedCategories.count) SELECTED")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(0.5)
                    }
                }
            }
        }
    }

    // MARK: - Mapping editor

    private var mappingEditor: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(BrutalTheme.sectionLabel(3, "CATEGORY MAPPING"))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                Text("MAP APPS TO CATEGORIES LOCALLY. LEAVE BLANK FOR UNCATEGORIZED.")
                    .font(BrutalTheme.captionMono)
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)

                if let mappingError {
                    Text(mappingError)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.danger)
                }

                if apps.isEmpty {
                    Text("NO APP USAGE IN THIS RANGE.")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                } else {
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(height: 0.5)

                    ForEach(apps.prefix(12)) { app in
                        mappingRow(for: app)
                    }
                }
            }
        }
    }

    // MARK: - Chip layout

    private func chipLayout(
        rawValues: [String],
        selectedValues: Set<String>,
        onTap: @escaping (String) -> Void
    ) -> some View {
        let stableValues = Array(rawValues)

        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 0)], spacing: 0) {
            ForEach(stableValues, id: \.self) { (value: String) in
                let selected = selectedValues.contains(value)

                Button {
                    onTap(value)
                } label: {
                    HStack(spacing: 6) {
                        Rectangle()
                            .fill(selected ? BrutalTheme.accent : BrutalTheme.border)
                            .frame(width: 8, height: 8)
                        AppNameText(value)
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(selected ? BrutalTheme.textPrimary : BrutalTheme.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(selected ? BrutalTheme.accentMuted : Color.clear)
                    .overlay(
                        Rectangle()
                            .strokeBorder(selected ? BrutalTheme.accent.opacity(0.4) : BrutalTheme.border.opacity(0.5), lineWidth: 0.5)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func chipLayout(
        values: [String],
        selectedValues: Set<String>,
        onTap: @escaping (String) -> Void
    ) -> some View {
        chipLayout(rawValues: values, selectedValues: selectedValues, onTap: onTap)
    }

    // MARK: - Bar colors

    private func appBarColor(for app: AppUsageSummary) -> AnyShapeStyle {
        if filters.selectedApps.isEmpty || filters.selectedApps.contains(app.appName) {
            return AnyShapeStyle(BrutalTheme.accent)
        }
        return AnyShapeStyle(BrutalTheme.border)
    }

    private func categoryBarColor(for category: CategoryUsageSummary) -> AnyShapeStyle {
        if filters.selectedCategories.isEmpty || filters.selectedCategories.contains(category.category) {
            return AnyShapeStyle(BrutalTheme.accent)
        }
        return AnyShapeStyle(BrutalTheme.border)
    }

    // MARK: - Mapping row

    @ViewBuilder
    private func mappingRow(for app: AppUsageSummary) -> some View {
        HStack(spacing: 10) {
            AppNameText(app.appName)
                .font(BrutalTheme.tableBody)
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("CATEGORY", text: draftBinding(for: app.appName))
                .font(BrutalTheme.tableBody)
                .textFieldStyle(.plain)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    Rectangle()
                        .strokeBorder(BrutalTheme.border, lineWidth: 1)
                )
                .frame(width: 200)
                .onSubmit {
                    Task {
                        await persistCategory(for: app.appName)
                    }
                }

            Button {
                Task {
                    await persistCategory(for: app.appName)
                }
            } label: {
                Text("SAVE")
                    .font(BrutalTheme.captionMono)
                    .tracking(0.5)
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BrutalTheme.accent)
            }
            .buttonStyle(.plain)
            .disabled(mappingSaveInFlight.contains(app.appName))

            Button {
                categoryDraftByApp[app.appName] = ""
                Task {
                    await persistCategory(for: app.appName)
                }
            } label: {
                Text("CLR")
                    .font(BrutalTheme.captionMono)
                    .tracking(0.5)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .overlay(
                        Rectangle()
                            .strokeBorder(BrutalTheme.border, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .disabled(mappingSaveInFlight.contains(app.appName) || categoryMappingByApp[app.appName] == nil)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private var reloadKey: String {
        let selectedApps = filters.selectedApps.sorted().joined(separator: "|")
        let selectedCategories = filters.selectedCategories.sorted().joined(separator: "|")
        let selectedCells = filters.selectedHeatmapCells
            .sorted {
                if $0.weekday == $1.weekday {
                    return $0.hour < $1.hour
                }
                return $0.weekday < $1.weekday
            }
            .map { "\($0.weekday)-\($0.hour)" }
            .joined(separator: "|")

        return [
            String(filters.startDate.timeIntervalSince1970),
            String(filters.endDate.timeIntervalSince1970),
            filters.granularity.rawValue,
            selectedApps,
            selectedCategories,
            selectedCells
        ].joined(separator: "::")
    }

    private func draftBinding(for appName: String) -> Binding<String> {
        Binding(
            get: { categoryDraftByApp[appName] ?? categoryMappingByApp[appName] ?? "" },
            set: { categoryDraftByApp[appName] = $0 }
        )
    }

    private func toggleAppSelection(_ appName: String) {
        if filters.selectedApps.contains(appName) {
            filters.selectedApps.remove(appName)
        } else {
            filters.selectedApps.insert(appName)
        }
    }

    private func toggleCategorySelection(_ category: String) {
        if filters.selectedCategories.contains(category) {
            filters.selectedCategories.remove(category)
        } else {
            filters.selectedCategories.insert(category)
        }
    }

    private func load() async {
        do {
            loadError = nil
            mappingError = nil
            let snapshot = filters.snapshot

            async let appFetch = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 16)
            async let categoryFetch = appEnvironment.dataService.fetchTopCategories(filters: snapshot, limit: 12)
            async let mappingFetch = appEnvironment.dataService.fetchCategoryMappings()

            let fetchedApps = try await appFetch
            let fetchedCategories = try await categoryFetch
            let fetchedMappings = try await mappingFetch

            apps = fetchedApps
            categories = fetchedCategories
            categoryMappingByApp = Dictionary(uniqueKeysWithValues: fetchedMappings.map { ($0.appName, $0.category) })

            syncDraftsToLoadedApps()
        } catch {
            loadError = error
            apps = []
            categories = []
            categoryMappingByApp = [:]
            categoryDraftByApp = [:]
        }
    }

    private func syncDraftsToLoadedApps() {
        var nextDrafts: [String: String] = [:]
        for app in apps {
            nextDrafts[app.appName] = categoryDraftByApp[app.appName] ?? categoryMappingByApp[app.appName] ?? ""
        }
        categoryDraftByApp = nextDrafts
    }

    private func persistCategory(for appName: String) async {
        let category = (categoryDraftByApp[appName] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        mappingSaveInFlight.insert(appName)
        defer { mappingSaveInFlight.remove(appName) }

        do {
            mappingError = nil
            if category.isEmpty {
                try await appEnvironment.dataService.deleteCategoryMapping(appName: appName)
                categoryMappingByApp.removeValue(forKey: appName)
            } else {
                try await appEnvironment.dataService.saveCategoryMapping(appName: appName, category: category)
                categoryMappingByApp[appName] = category
                categoryDraftByApp[appName] = category
            }

            categories = try await appEnvironment.dataService.fetchTopCategories(filters: filters.snapshot, limit: 12)
        } catch {
            mappingError = ScreenTimeDataError.message(for: error)
        }
    }
}
