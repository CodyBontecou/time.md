import SwiftUI

// MARK: - Timing-style Rules View
// Interface for creating/editing automatic categorization rules.

struct TimingRulesView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @Environment(\.appNameDisplayMode) private var appNameDisplayMode

    @State private var categoryMappings: [AppCategoryMapping] = []
    @State private var topApps: [AppUsageSummary] = []
    @State private var isLoading = true
    @State private var loadError: Error?
    @State private var searchText = ""
    @State private var showUnmappedOnly = false
    @State private var editingRule: String?
    @State private var editCategory = ""
    @State private var bulkCategory = ""
    @State private var selectedApps: Set<String> = []

    private var mappingDict: [String: String] {
        Dictionary(uniqueKeysWithValues: categoryMappings.map { ($0.appName, $0.category) })
    }

    private var existingCategories: [String] {
        Array(Set(categoryMappings.map(\.category))).sorted()
    }

    private var filteredApps: [AppUsageSummary] {
        var apps = topApps
        if showUnmappedOnly {
            apps = apps.filter { mappingDict[$0.appName] == nil }
        }
        if !searchText.isEmpty {
            apps = apps.filter {
                $0.appName.localizedCaseInsensitiveContains(searchText) ||
                (mappingDict[$0.appName] ?? "").localizedCaseInsensitiveContains(searchText)
            }
        }
        return apps
    }

    private var unmappedCount: Int {
        topApps.filter { mappingDict[$0.appName] == nil }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                controlBar

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 200)
                } else if let loadError {
                    DataLoadErrorView(error: loadError)
                } else {
                    HStack(alignment: .top, spacing: 20) {
                        rulesTable
                            .frame(maxWidth: .infinity)

                        rulesSidebar
                            .frame(width: 260)
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
            Text("Rules")
                .font(.system(size: 26, weight: .bold, design: .default))
                .foregroundColor(BrutalTheme.textPrimary)

            Text("Assign apps to categories for organized time tracking")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    // MARK: - Control Bar

    private var controlBar: some View {
        HStack(spacing: 12) {
            // Search
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12))
                    .foregroundColor(BrutalTheme.textTertiary)
                TextField("Search apps...", text: $searchText)
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

            // Unmapped filter
            Toggle(isOn: $showUnmappedOnly) {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 11))
                    Text("Unmapped only (\(unmappedCount))")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(showUnmappedOnly ? .orange : BrutalTheme.textSecondary)
            }
            .toggleStyle(.switch)
            .tint(.orange)

            Spacer()

            // Bulk assign (when apps are selected)
            if !selectedApps.isEmpty {
                HStack(spacing: 6) {
                    Text("\(selectedApps.count) selected")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textSecondary)

                    TextField("Category", text: $bulkCategory)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .frame(width: 120)

                    Button("Assign") {
                        Task { await bulkAssign() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(bulkCategory.isEmpty)

                    Button("Clear") {
                        selectedApps.removeAll()
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(BrutalTheme.textTertiary)
                }
            }
        }
    }

    // MARK: - Rules Table

    private var rulesTable: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 0) {
                // Table header
                HStack {
                    // Checkbox column
                    Button {
                        if selectedApps.count == filteredApps.count {
                            selectedApps.removeAll()
                        } else {
                            selectedApps = Set(filteredApps.map(\.appName))
                        }
                    } label: {
                        Image(systemName: selectedApps.count == filteredApps.count && !filteredApps.isEmpty ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 24)

                    Text("APP")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("CATEGORY")
                        .frame(width: 150, alignment: .leading)
                    Text("TIME")
                        .frame(width: 80, alignment: .trailing)
                    Text("")
                        .frame(width: 60)
                }
                .font(BrutalTheme.tableHeader)
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(0.5)
                .padding(.horizontal, 4)
                .padding(.bottom, 8)

                Rectangle()
                    .fill(BrutalTheme.borderStrong)
                    .frame(height: 1)

                // Rows
                ForEach(filteredApps) { app in
                    ruleRow(app: app)
                }

                if filteredApps.isEmpty {
                    Text("No apps match your filters.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 20)
                }
            }
        }
    }

    private func ruleRow(app: AppUsageSummary) -> some View {
        let currentCategory = mappingDict[app.appName]
        let isSelected = selectedApps.contains(app.appName)

        return VStack(spacing: 0) {
            HStack(spacing: 0) {
                // Checkbox
                Button {
                    if isSelected {
                        selectedApps.remove(app.appName)
                    } else {
                        selectedApps.insert(app.appName)
                    }
                } label: {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .font(.system(size: 12))
                        .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)
                }
                .buttonStyle(.plain)
                .frame(width: 24)

                // App icon + name
                HStack(spacing: 6) {
                    #if os(macOS)
                    AppIconView(bundleID: app.appName, size: 16)
                    #endif

                    AppNameText(app.appName)
                        .font(BrutalTheme.tableBody)
                        .foregroundColor(BrutalTheme.textPrimary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Category
                if editingRule == app.appName {
                    HStack(spacing: 4) {
                        TextField("Category", text: $editCategory)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11))
                            .frame(width: 100)
                            .onSubmit {
                                Task { await saveRule(appName: app.appName) }
                            }

                        Button {
                            Task { await saveRule(appName: app.appName) }
                        } label: {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.green)
                        }
                        .buttonStyle(.plain)

                        Button {
                            editingRule = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .frame(width: 150, alignment: .leading)
                } else {
                    HStack(spacing: 4) {
                        if let cat = currentCategory {
                            Circle()
                                .fill(BrutalTheme.color(for: cat))
                                .frame(width: 6, height: 6)
                            Text(verbatim: cat)
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textPrimary)
                        } else {
                            Text("--")
                                .font(BrutalTheme.tableBody)
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
                    }
                    .frame(width: 150, alignment: .leading)
                }

                // Time
                Text(DurationFormatter.short(app.totalSeconds))
                    .font(BrutalTheme.tableBody)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .frame(width: 80, alignment: .trailing)

                // Edit button
                HStack(spacing: 4) {
                    Button {
                        editingRule = app.appName
                        editCategory = currentCategory ?? ""
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 10))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)

                    if currentCategory != nil {
                        Button {
                            Task {
                                try? await appEnvironment.dataService.deleteCategoryMapping(appName: app.appName)
                                await loadData()
                            }
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 10))
                                .foregroundColor(.red.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(width: 60, alignment: .center)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 6)
            .background(isSelected ? BrutalTheme.accentMuted : Color.clear)

            Rectangle()
                .fill(BrutalTheme.border)
                .frame(height: 0.5)
        }
    }

    // MARK: - Rules Sidebar

    private var rulesSidebar: some View {
        VStack(spacing: 16) {
            // Category summary
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("CATEGORIES")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    if existingCategories.isEmpty {
                        Text("No categories defined yet.\nAssign apps to categories using the edit button.")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    } else {
                        ForEach(existingCategories, id: \.self) { category in
                            let count = categoryMappings.filter { $0.category == category }.count

                            HStack(spacing: 6) {
                                Circle()
                                    .fill(BrutalTheme.color(for: category))
                                    .frame(width: 8, height: 8)
                                Text(verbatim: category)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(BrutalTheme.textPrimary)
                                    .lineLimit(1)
                                Spacer()
                                Text("\(count) apps")
                                    .font(BrutalTheme.captionMono)
                                    .foregroundColor(BrutalTheme.textTertiary)
                            }
                        }
                    }
                }
            }

            // Stats
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("COVERAGE")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    let mapped = topApps.filter { mappingDict[$0.appName] != nil }.count
                    let total = topApps.count
                    let coverage = total > 0 ? Double(mapped) / Double(total) * 100 : 0

                    HStack {
                        Text("Mapped")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                        Spacer()
                        Text("\(mapped) / \(total)")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textPrimary)
                    }

                    // Coverage bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(BrutalTheme.surface.opacity(0.5))
                            RoundedRectangle(cornerRadius: 4)
                                .fill(coverage > 80 ? Color.green : (coverage > 50 ? Color.orange : Color.red))
                                .frame(width: geo.size.width * coverage / 100)
                        }
                    }
                    .frame(height: 8)

                    Text(String(format: "%.0f%% coverage", coverage))
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(coverage > 80 ? .green : (coverage > 50 ? .orange : .red))
                }
            }

            // Quick assign suggestions
            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("SUGGESTIONS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    Text("Common categories:")
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)

                    FlowLayout(spacing: 4) {
                        ForEach(["Development", "Communication", "Design", "Browsing", "Entertainment", "Productivity", "Social Media", "Writing"], id: \.self) { suggestion in
                            Button {
                                bulkCategory = suggestion
                            } label: {
                                Text(LocalizedStringKey(suggestion))
                                    .font(.system(size: 10, weight: .medium))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        RoundedRectangle(cornerRadius: 4)
                                            .fill(BrutalTheme.surface.opacity(0.5))
                                    )
                                    .foregroundColor(BrutalTheme.textSecondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func saveRule(appName: String) async {
        guard !editCategory.isEmpty else { return }
        try? await appEnvironment.dataService.saveCategoryMapping(appName: appName, category: editCategory)
        editingRule = nil
        await loadData()
    }

    private func bulkAssign() async {
        guard !bulkCategory.isEmpty else { return }
        for appName in selectedApps {
            try? await appEnvironment.dataService.saveCategoryMapping(appName: appName, category: bulkCategory)
        }
        selectedApps.removeAll()
        bulkCategory = ""
        await loadData()
    }

    // MARK: - Data Loading

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }

        do {
            loadError = nil
            let snapshot = filters.snapshot

            async let fetchedApps = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 100)
            async let fetchedMappings = appEnvironment.dataService.fetchCategoryMappings()

            topApps = try await fetchedApps
            categoryMappings = try await fetchedMappings
        } catch {
            loadError = error
        }
    }
}
