import Charts
import SwiftUI

// MARK: - Timing-style Projects View
// Hierarchical project/category list showing time per project with nested categories.

struct TimingProjectsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var topApps: [AppUsageSummary] = []
    @State private var topCategories: [CategoryUsageSummary] = []
    @State private var categoryMappings: [AppCategoryMapping] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var expandedCategories: Set<String> = []
    @State private var editingApp: String?
    @State private var editCategory: String = ""
    @State private var showAddMapping = false
    @State private var searchText = ""

    private var totalSeconds: Double {
        topApps.reduce(0) { $0 + $1.totalSeconds }
    }

    /// Apps grouped by category
    private var appsByCategory: [(category: String, apps: [AppUsageSummary], totalSeconds: Double)] {
        let mappingDict = Dictionary(uniqueKeysWithValues: categoryMappings.map { ($0.appName, $0.category) })

        var grouped: [String: [AppUsageSummary]] = [:]
        for app in topApps {
            let category = mappingDict[app.appName] ?? "Uncategorized"
            grouped[category, default: []].append(app)
        }

        return grouped.map { (category: $0.key, apps: $0.value.sorted { $0.totalSeconds > $1.totalSeconds }, totalSeconds: $0.value.reduce(0) { $0 + $1.totalSeconds }) }
            .sorted { $0.totalSeconds > $1.totalSeconds }
    }

    private var filteredCategories: [(category: String, apps: [AppUsageSummary], totalSeconds: Double)] {
        if searchText.isEmpty { return appsByCategory }
        return appsByCategory.filter { group in
            group.category.localizedCaseInsensitiveContains(searchText) ||
            group.apps.contains { $0.appName.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                searchAndActions

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        projectList
                            .frame(maxWidth: .infinity)

                        categorySummary
                            .frame(width: 280)
                    }
                }
            }
        }
        .scrollIndicators(.never)
        .scrollClipDisabled()
        .task(id: "\(filters.rangeLabel)\(filters.granularity.rawValue)\(filters.refreshToken)") {
            await loadData()
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Projects")
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)

            Text(filters.rangeLabel.uppercased())
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(0.8)
        }
    }

    // MARK: - Search & Actions

    private var searchAndActions: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(BrutalTheme.textTertiary)
                TextField("Search apps or categories...", text: $searchText)
                    .font(.system(size: 12))
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(BrutalTheme.surface.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(BrutalTheme.border, lineWidth: 1)
                    )
            )
            .frame(maxWidth: 300)

            Spacer()

            // Expand/Collapse all
            Button {
                if expandedCategories.count == appsByCategory.count {
                    expandedCategories.removeAll()
                } else {
                    expandedCategories = Set(appsByCategory.map(\.category))
                }
            } label: {
                Text(expandedCategories.count == appsByCategory.count ? "Collapse All" : "Expand All")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Project List

    private var projectList: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                Text("PROJECTS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)
                    .padding(.bottom, 12)

                ForEach(filteredCategories, id: \.category) { group in
                    projectGroup(group)
                }
            }
        }
    }

    private func projectGroup(_ group: (category: String, apps: [AppUsageSummary], totalSeconds: Double)) -> some View {
        let isExpanded = expandedCategories.contains(group.category)
        let pct = totalSeconds > 0 ? group.totalSeconds / totalSeconds : 0

        return VStack(alignment: .leading, spacing: 0) {
            // Category header
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    if isExpanded {
                        expandedCategories.remove(group.category)
                    } else {
                        expandedCategories.insert(group.category)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: 14)

                    Circle()
                        .fill(BrutalTheme.color(for: group.category))
                        .frame(width: 10, height: 10)

                    Image(systemName: "folder.fill")
                        .font(.system(size: 13))
                        .foregroundColor(BrutalTheme.color(for: group.category))

                    Text(group.category)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text("(\(group.apps.count))")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)

                    Spacer()

                    // Progress bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(BrutalTheme.surface.opacity(0.5))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(BrutalTheme.color(for: group.category).opacity(0.6))
                                .frame(width: geo.size.width * pct)
                        }
                    }
                    .frame(width: 100, height: 6)

                    Text(DurationFormatter.short(group.totalSeconds))
                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                        .frame(width: 70, alignment: .trailing)

                    Text(String(format: "%.0f%%", pct * 100))
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(width: 40, alignment: .trailing)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // Expanded app list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.apps) { app in
                        projectAppRow(app: app, categoryTotal: group.totalSeconds)
                    }
                }
                .padding(.leading, 32)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(BrutalTheme.border)
                .frame(height: 0.5)
        }
    }

    private func projectAppRow(app: AppUsageSummary, categoryTotal: Double) -> some View {
        let pct = categoryTotal > 0 ? app.totalSeconds / categoryTotal : 0

        return HStack(spacing: 8) {
            #if os(macOS)
            AppIconView(bundleID: app.appName, size: 16)
            #endif

            AppNameText(app.appName)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)

            Spacer()

            Text(DurationFormatter.short(app.totalSeconds))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .frame(width: 60, alignment: .trailing)

            Text(String(format: "%.0f%%", pct * 100))
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(width: 40, alignment: .trailing)

            // Edit category button
            Button {
                editingApp = app.appName
                editCategory = categoryMappings.first(where: { $0.appName == app.appName })?.category ?? ""
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 10))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .buttonStyle(.plain)
            .popover(isPresented: Binding(
                get: { editingApp == app.appName },
                set: { if !$0 { editingApp = nil } }
            )) {
                categoryEditor(for: app.appName)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
    }

    // MARK: - Category Editor Popover

    private func categoryEditor(for appName: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Assign Category")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.textPrimary)

            AppNameText(appName)
                .font(BrutalTheme.bodyMono)
                .foregroundColor(BrutalTheme.textSecondary)

            TextField("Category name", text: $editCategory)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))

            // Quick category suggestions
            let existingCategories = Array(Set(categoryMappings.map(\.category))).sorted()
            if !existingCategories.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(existingCategories, id: \.self) { cat in
                            Button(cat) {
                                editCategory = cat
                            }
                            .font(.system(size: 10, weight: .medium))
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            HStack {
                Button("Remove") {
                    Task {
                        try? await appEnvironment.dataService.deleteCategoryMapping(appName: appName)
                        editingApp = nil
                        await loadData()
                    }
                }
                .foregroundColor(.red)
                .buttonStyle(.plain)

                Spacer()

                Button("Save") {
                    guard !editCategory.isEmpty else { return }
                    Task {
                        try? await appEnvironment.dataService.saveCategoryMapping(appName: appName, category: editCategory)
                        editingApp = nil
                        await loadData()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 260)
    }

    // MARK: - Category Summary Sidebar

    private var categorySummary: some View {
        VStack(spacing: 16) {
            // Pie chart
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("DISTRIBUTION")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    if appsByCategory.isEmpty {
                        Text("No data")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    } else {
                        Chart {
                            ForEach(appsByCategory.prefix(8), id: \.category) { group in
                                SectorMark(
                                    angle: .value("Time", group.totalSeconds),
                                    innerRadius: .ratio(0.5),
                                    angularInset: 1
                                )
                                .foregroundStyle(BrutalTheme.color(for: group.category))
                            }
                        }
                        .frame(height: 160)

                        // Legend
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(appsByCategory.prefix(8), id: \.category) { group in
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(BrutalTheme.color(for: group.category))
                                        .frame(width: 8, height: 8)
                                    Text(group.category)
                                        .font(.system(size: 10, weight: .medium))
                                        .foregroundColor(BrutalTheme.textPrimary)
                                        .lineLimit(1)
                                    Spacer()
                                    Text(DurationFormatter.short(group.totalSeconds))
                                        .font(BrutalTheme.captionMono)
                                        .foregroundColor(BrutalTheme.textSecondary)
                                }
                            }
                        }
                    }
                }
            }

            // Quick stats
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("STATS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    statRow(label: "Categories", value: "\(appsByCategory.count)")
                    statRow(label: "Total Apps", value: "\(topApps.count)")
                    statRow(label: "Total Time", value: DurationFormatter.short(totalSeconds))

                    if let top = appsByCategory.first {
                        statRow(label: "Top Project", value: top.category)
                    }
                }
            }
        }
    }

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
                .lineLimit(1)
        }
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 100)
            async let fetchedCategories = appEnvironment.dataService.fetchTopCategories(filters: snapshot, limit: 30)
            async let fetchedMappings = appEnvironment.dataService.fetchCategoryMappings()

            topApps = try await fetchedApps
            topCategories = try await fetchedCategories
            categoryMappings = try await fetchedMappings
        } catch {
            loadError = error
        }
    }
}
