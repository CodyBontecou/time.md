import SwiftUI
import UniformTypeIdentifiers

struct ExportsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var selectedFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var showSuccess = false
    @State private var lastExportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""

    // Export mode
    @State private var exportMode: ExportMode = .general

    // Section selection (for general mode, a curated subset; for extensive, everything)
    @State private var sectionSelection = ExportSectionSelection.allExceptRaw

    // Filter presets
    @State private var filterPresetStore = ExportFilterPresetStore()
    @State private var selectedPresetId: UUID?
    @State private var editingPreset: ExportFilterPreset?
    @State private var availableApps: [String] = []
    @State private var availableCategories: [String] = []

    // Custom date range for export
    @State private var showDatePicker = false
    @State private var customStartDate: Date?
    @State private var customEndDate: Date?

    // Direct app/category filtering
    @State private var selectedApps: Set<String> = []
    @State private var selectedCategories: Set<String> = []
    @State private var showAppPicker = false
    @State private var showCategoryPicker = false

    // Export destination
    @State private var exportDirectory: URL? = ExportSettings.load().resolveDefaultExportDirectory()
    @State private var showDirectoryPicker = false

    // Progress
    @State private var exportProgress = ExportProgress()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                headerSection
                exportModeSection
                sectionSelectionSection
                filterSection
                formatSelectionSection
                destinationSection
                exportButtonSection

                if showSuccess || showError {
                    statusSection
                }
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .sheet(item: $editingPreset) { initialPreset in
            PresetEditorWrapper(
                initialPreset: initialPreset,
                availableApps: availableApps,
                onSave: { preset in
                    if filterPresetStore.presets.contains(where: { $0.id == preset.id }) {
                        filterPresetStore.updatePreset(preset)
                    } else {
                        filterPresetStore.addPreset(preset)
                    }
                    selectedPresetId = preset.id
                    editingPreset = nil
                },
                onCancel: {
                    editingPreset = nil
                }
            )
        }
        .sheet(isPresented: $showAppPicker) {
            appPickerSheet
        }
        .sheet(isPresented: $showCategoryPicker) {
            categoryPickerSheet
        }
        .task {
            await loadAvailableData()
        }
    }

    // MARK: - Export Mode

    enum ExportMode: String, CaseIterable, Identifiable {
        case general
        case extensive

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return String(localized: "General")
            case .extensive: return String(localized: "Extensive")
            }
        }

        var description: String {
            switch self {
            case .general: return String(localized: "Summary, top apps, categories, and trends")
            case .extensive: return String(localized: "Everything including raw sessions, heatmaps, web history, and analytics")
            }
        }

        var systemImage: String {
            switch self {
            case .general: return "doc.plaintext"
            case .extensive: return "doc.on.doc"
            }
        }
    }

    // MARK: - Header

    private var effectiveStartDate: Date {
        customStartDate ?? filters.startDate
    }

    private var effectiveEndDate: Date {
        customEndDate ?? filters.endDate
    }

    private var hasCustomDateRange: Bool {
        customStartDate != nil || customEndDate != nil
    }

    private var dateRangeLabel: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "\(formatter.string(from: effectiveStartDate)) – \(formatter.string(from: effectiveEndDate))"
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Export Data")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                Spacer()

                Button {
                    if customStartDate == nil { customStartDate = filters.startDate }
                    if customEndDate == nil { customEndDate = filters.endDate }
                    showDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(LocalizedStringKey(dateRangeLabel))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))

                        if hasCustomDateRange {
                            Image(systemName: "pencil.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(BrutalTheme.accent)
                        }
                    }
                    .foregroundColor(hasCustomDateRange ? BrutalTheme.accent : BrutalTheme.textSecondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(hasCustomDateRange ? BrutalTheme.accent.opacity(0.1) : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(.ultraThinMaterial)
                            )
                    )
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showDatePicker, arrowEdge: .bottom) {
                    ExportDateRangePicker(
                        startDate: Binding(
                            get: { customStartDate ?? filters.startDate },
                            set: { customStartDate = $0 }
                        ),
                        endDate: Binding(
                            get: { customEndDate ?? filters.endDate },
                            set: { customEndDate = $0 }
                        ),
                        onReset: {
                            customStartDate = nil
                            customEndDate = nil
                        },
                        onDone: {
                            showDatePicker = false
                        }
                    )
                }
            }

            Text("Configure what data to include and choose your preferred format.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    // MARK: - Export Mode Section

    private var exportModeSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("EXPORT MODE")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                HStack(spacing: 12) {
                    ForEach(ExportMode.allCases) { mode in
                        let isSelected = exportMode == mode
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                exportMode = mode
                                applySectionDefaults(for: mode)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(isSelected ? BrutalTheme.accent : BrutalTheme.accent.opacity(0.1))
                                        .frame(width: 40, height: 40)

                                    Image(systemName: mode.systemImage)
                                        .font(.system(size: 16, weight: .semibold))
                                        .foregroundColor(isSelected ? .white : BrutalTheme.accent)
                                }

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(mode.title)
                                        .font(.system(size: 14, weight: .bold))
                                        .foregroundColor(BrutalTheme.textPrimary)

                                    Text(mode.description)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? BrutalTheme.accent.opacity(0.1) : Color.clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                                    )
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func applySectionDefaults(for mode: ExportMode) {
        switch mode {
        case .general:
            sectionSelection = ExportSectionSelection(sections: [.summary, .apps, .categories, .trends])
        case .extensive:
            sectionSelection = .full
        }
    }

    // MARK: - Section Selection

    private var sectionSelectionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("DATA SECTIONS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    Spacer()

                    Text("\(sectionSelection.count) selected")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                // Basic sections
                sectionGroup("Screen Time", sections: ExportSection.basicSections)

                // Web sections
                sectionGroup("Web Browsing", sections: ExportSection.webBrowsingSections)

                // Analytics sections
                sectionGroup("Analytics", sections: ExportSection.analyticsSections)
            }
        }
    }

    private func sectionGroup(_ title: String, sections: [ExportSection]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(0.5)

            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ], spacing: 8) {
                ForEach(sections) { section in
                    sectionToggle(section)
                }
            }
        }
    }

    private func sectionToggle(_ section: ExportSection) -> some View {
        let isSelected = sectionSelection.contains(section)

        return Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                sectionSelection.toggle(section)
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(section.displayName)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isSelected ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                        .lineLimit(1)

                    Text(section.description)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary.opacity(0.4))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? BrutalTheme.accent.opacity(0.06) : Color(NSColor.controlBackgroundColor).opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? BrutalTheme.accent.opacity(0.3) : Color.clear, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Filter Section

    private var filterSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("FILTERS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)

                    Spacer()

                    Button {
                        editingPreset = ExportFilterPreset(name: "")
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .semibold))
                            Text("New Preset")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(BrutalTheme.accent)
                    }
                    .buttonStyle(.plain)
                }

                // Filter presets
                presetSelector

                // Show active preset filters summary
                if let preset = selectedPreset, preset.hasFilters {
                    activeFiltersDisplay(preset)
                }

                Divider().opacity(0.3)

                // Direct app filtering
                appFilterRow

                // Direct category filtering
                categoryFilterRow

                // Active filter summary
                if !selectedApps.isEmpty || !selectedCategories.isEmpty {
                    directFilterSummary
                }
            }
        }
    }

    private var presetSelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                presetChip(nil, name: "All Data", icon: "square.stack.3d.up")

                ForEach(ExportFilterPresetStore.builtInPresets) { preset in
                    presetChip(preset.id, name: preset.name, icon: presetIcon(for: preset))
                }

                ForEach(filterPresetStore.userPresets) { preset in
                    presetChip(preset.id, name: preset.name, icon: "person.crop.circle", isUserPreset: true)
                }
            }
        }
    }

    private func presetChip(_ id: UUID?, name: String, icon: String, isUserPreset: Bool = false) -> some View {
        let isSelected = selectedPresetId == id

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedPresetId = id
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))

                Text(verbatim: name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)

                if isUserPreset && isSelected {
                    Menu {
                        Button {
                            if let preset = filterPresetStore.userPresets.first(where: { $0.id == id }) {
                                editingPreset = preset
                            }
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

                        Button {
                            if let preset = filterPresetStore.userPresets.first(where: { $0.id == id }) {
                                _ = filterPresetStore.duplicatePreset(preset)
                            }
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }

                        Divider()

                        Button(role: .destructive) {
                            if let id = id {
                                filterPresetStore.deletePreset(id: id)
                                selectedPresetId = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .menuStyle(.borderlessButton)
                    .frame(width: 16)
                }
            }
            .foregroundColor(isSelected ? .white : BrutalTheme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? BrutalTheme.accent : Color(NSColor.controlBackgroundColor))
            )
        }
        .buttonStyle(.plain)
    }

    private func presetIcon(for preset: ExportFilterPreset) -> String {
        if !preset.timeRanges.isEmpty && preset.selectedWeekdays == WeekdaySelection.weekdays {
            return "briefcase"
        } else if preset.selectedWeekdays == WeekdaySelection.weekends {
            return "sun.max"
        } else if !preset.timeRanges.isEmpty {
            return "clock"
        } else if preset.minDurationSeconds != nil || preset.maxDurationSeconds != nil {
            return "timer"
        }
        return "line.3.horizontal.decrease.circle"
    }

    private func activeFiltersDisplay(_ preset: ExportFilterPreset) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(BrutalTheme.accent)

            Text(LocalizedStringKey(preset.filterSummary))
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textSecondary)

            Spacer()

            if let desc = preset.description {
                Text(verbatim: desc)
                    .font(.system(size: 10))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(1)
            }
        }
    }

    private var selectedPreset: ExportFilterPreset? {
        guard let id = selectedPresetId else { return nil }
        return filterPresetStore.allPresets.first { $0.id == id }
    }

    // MARK: - App / Category Filtering

    private var appFilterRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "app.badge")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Apps")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(selectedApps.isEmpty ? "All apps included" : "\(selectedApps.count) app\(selectedApps.count == 1 ? "" : "s") selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(selectedApps.isEmpty ? BrutalTheme.textTertiary : BrutalTheme.accent)
            }

            Spacer()

            Button {
                showAppPicker = true
            } label: {
                Text(selectedApps.isEmpty ? "Filter" : "Edit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BrutalTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BrutalTheme.accent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            if !selectedApps.isEmpty {
                Button {
                    withAnimation { selectedApps.removeAll() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var categoryFilterRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text("Categories")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(selectedCategories.isEmpty ? "All categories included" : "\(selectedCategories.count) categor\(selectedCategories.count == 1 ? "y" : "ies") selected")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(selectedCategories.isEmpty ? BrutalTheme.textTertiary : BrutalTheme.accent)
            }

            Spacer()

            Button {
                showCategoryPicker = true
            } label: {
                Text(selectedCategories.isEmpty ? "Filter" : "Edit")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(BrutalTheme.accent)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(BrutalTheme.accent.opacity(0.1))
                    )
            }
            .buttonStyle(.plain)

            if !selectedCategories.isEmpty {
                Button {
                    withAnimation { selectedCategories.removeAll() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var directFilterSummary: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(BrutalTheme.accent)

            if !selectedApps.isEmpty {
                Text(selectedApps.prefix(3).joined(separator: ", ") + (selectedApps.count > 3 ? " +\(selectedApps.count - 3) more" : ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineLimit(1)
            }

            if !selectedApps.isEmpty && !selectedCategories.isEmpty {
                Text("·")
                    .foregroundColor(BrutalTheme.textTertiary)
            }

            if !selectedCategories.isEmpty {
                Text(selectedCategories.prefix(3).joined(separator: ", ") + (selectedCategories.count > 3 ? " +\(selectedCategories.count - 3) more" : ""))
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(BrutalTheme.accent.opacity(0.05))
        )
    }

    // MARK: - Format Selection

    private var formatSelectionSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("FORMAT")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(ExportFormat.allCases) { format in
                        formatCard(format)
                    }
                }
            }
        }
    }

    private func formatCard(_ format: ExportFormat) -> some View {
        let isSelected = selectedFormat == format

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedFormat = format
            }
        } label: {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? BrutalTheme.accent : BrutalTheme.accent.opacity(0.1))
                        .frame(width: 40, height: 40)

                    Image(systemName: format.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isSelected ? .white : BrutalTheme.accent)
                }

                VStack(spacing: 3) {
                    Text(format.displayName)
                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text(format.description)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? BrutalTheme.accent.opacity(0.1) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Destination

    private var destinationSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("DESTINATION")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                HStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BrutalTheme.accent)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: exportDirectory?.lastPathComponent ?? "time.md Exports")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineLimit(1)

                        Text(verbatim: exportDirectoryDisplayPath)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    Spacer()

                    if exportDirectory != nil {
                        Button {
                            var settings = ExportSettings.load()
                            settings.setDefaultExportDirectory(nil)
                            exportDirectory = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Reset to default (~/Downloads/time.md Exports)")
                    }

                    Button {
                        showDirectoryPicker = true
                    } label: {
                        Text("Choose…")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BrutalTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result, let url = urls.first {
                var settings = ExportSettings.load()
                settings.setDefaultExportDirectory(url)
                exportDirectory = url
            }
        }
    }

    private var exportDirectoryDisplayPath: String {
        if let dir = exportDirectory {
            return dir.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
        }
        return "~/Downloads/time.md Exports"
    }

    // MARK: - Export Button

    private var exportButtonSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)

                    Text(LocalizedStringKey(exportDescription))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }

                if isExporting {
                    VStack(spacing: 8) {
                        ProgressView(value: exportProgress.fractionComplete)
                            .tint(BrutalTheme.accent)

                        Text(LocalizedStringKey(exportProgress.statusText))
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }

                Divider().opacity(0.3)

                Button {
                    Task { await performExport() }
                } label: {
                    HStack(spacing: 10) {
                        if isExporting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .tint(.white)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                        }

                        Text(isExporting ? "Exporting..." : "Export \(selectedFormat.displayName)")
                            .font(.system(size: 14, weight: .bold))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(isExporting || sectionSelection.isEmpty ? BrutalTheme.accent.opacity(0.4) : BrutalTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExporting || sectionSelection.isEmpty)
            }
        }
    }

    private var exportDescription: String {
        var parts: [String] = []

        let sectionCount = sectionSelection.count
        parts.append("Exports \(sectionCount) data section\(sectionCount == 1 ? "" : "s") for the selected date range")

        if let preset = selectedPreset, preset.hasFilters {
            parts.append("with \(preset.name.lowercased()) filter")
        }

        if !selectedApps.isEmpty {
            parts.append("filtered to \(selectedApps.count) app\(selectedApps.count == 1 ? "" : "s")")
        }

        if !selectedCategories.isEmpty {
            parts.append("and \(selectedCategories.count) categor\(selectedCategories.count == 1 ? "y" : "ies")")
        }

        return parts.joined(separator: " ")
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                if showSuccess, let url = lastExportURL {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.green)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Export Complete")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(BrutalTheme.textPrimary)

                            Text(verbatim: url.lastPathComponent)
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }

                        Spacer()

                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                    .font(.system(size: 11, weight: .semibold))
                                Text("Show")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .foregroundColor(BrutalTheme.accent)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.bordered)
                    }
                }

                if showError {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(.red)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Export Failed")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundColor(BrutalTheme.textPrimary)

                            Text(LocalizedStringKey(errorMessage))
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }

                        Spacer()

                        Button {
                            withAnimation { showError = false }
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - App Picker Sheet

    private var appPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Apps")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button("Done") { showAppPicker = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            HStack(spacing: 12) {
                Button("Select All") {
                    selectedApps = Set(availableApps)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.accent)

                Button("Clear All") {
                    selectedApps.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)

                Spacer()

                Text("\(selectedApps.count) of \(availableApps.count) selected")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(availableApps, id: \.self) { app in
                    let isSelected = selectedApps.contains(app)
                    Button {
                        if isSelected {
                            selectedApps.remove(app)
                        } else {
                            selectedApps.insert(app)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)

                            Text(verbatim: app)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(BrutalTheme.textPrimary)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 500)
    }

    // MARK: - Category Picker Sheet

    private var categoryPickerSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Select Categories")
                    .font(.system(size: 16, weight: .bold))

                Spacer()

                Button("Done") { showCategoryPicker = false }
                    .buttonStyle(.borderedProminent)
            }
            .padding()

            Divider()

            HStack(spacing: 12) {
                Button("Select All") {
                    selectedCategories = Set(availableCategories)
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.accent)

                Button("Clear All") {
                    selectedCategories.removeAll()
                }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)

                Spacer()

                Text("\(selectedCategories.count) of \(availableCategories.count) selected")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            List {
                ForEach(availableCategories, id: \.self) { category in
                    let isSelected = selectedCategories.contains(category)
                    Button {
                        if isSelected {
                            selectedCategories.remove(category)
                        } else {
                            selectedCategories.insert(category)
                        }
                    } label: {
                        HStack {
                            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)

                            Text(verbatim: category)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(BrutalTheme.textPrimary)

                            Spacer()
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(width: 400, height: 400)
    }

    // MARK: - Data Loading

    private func loadAvailableData() async {
        do {
            let snapshot = filters.snapshot
            async let appsResult = appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 500)
            async let categoriesResult = appEnvironment.dataService.fetchTopCategories(filters: snapshot, limit: 100)

            let (apps, categories) = try await (appsResult, categoriesResult)
            await MainActor.run {
                availableApps = apps.map(\.appName)
                availableCategories = categories.map(\.category)
            }
        } catch {
            print("Failed to load available data: \(error)")
        }
    }

    // MARK: - Export Logic

    private func performExport() async {
        isExporting = true
        showSuccess = false
        showError = false
        exportProgress.reset()

        do {
            var snapshot = filters.snapshot

            // Apply custom date range
            snapshot.startDate = effectiveStartDate
            snapshot.endDate = effectiveEndDate

            // Apply preset filters
            if let preset = selectedPreset {
                preset.apply(to: &snapshot)
            }

            // Apply direct app/category filters
            if !selectedApps.isEmpty {
                snapshot.selectedApps = selectedApps
            }
            if !selectedCategories.isEmpty {
                snapshot.selectedCategories = selectedCategories
            }

            let coordinator = appEnvironment.exportCoordinator
            let settings = ExportSettings.load()

            let config = CombinedExportConfig(
                sections: sectionSelection,
                format: selectedFormat
            )

            let url = try await coordinator.exportCombined(
                config: config,
                filters: snapshot,
                settings: settings,
                progress: exportProgress
            )

            await MainActor.run {
                lastExportURL = url
                withAnimation { showSuccess = true }
            }
        } catch {
            await MainActor.run {
                errorMessage = error.localizedDescription
                withAnimation { showError = true }
            }
        }

        isExporting = false
    }
}

// MARK: - Export Date Range Picker

struct ExportDateRangePicker: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onReset: () -> Void
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Export Date Range")
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button {
                    onReset()
                } label: {
                    Text("Reset")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("START DATE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)

                DatePicker(
                    "",
                    selection: $startDate,
                    in: ...endDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.field)
                .labelsHidden()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("END DATE")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)

                DatePicker(
                    "",
                    selection: $endDate,
                    in: startDate...,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.field)
                .labelsHidden()
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("QUICK SELECT")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .tracking(0.5)

                HStack(spacing: 8) {
                    quickPresetButton("Today") {
                        let today = Calendar.current.startOfDay(for: .now)
                        startDate = today
                        endDate = .now
                    }

                    quickPresetButton("This Week") {
                        let calendar = Calendar.current
                        if let weekStart = calendar.dateInterval(of: .weekOfYear, for: .now)?.start {
                            startDate = weekStart
                        }
                        endDate = .now
                    }

                    quickPresetButton("This Month") {
                        let calendar = Calendar.current
                        if let monthStart = calendar.dateInterval(of: .month, for: .now)?.start {
                            startDate = monthStart
                        }
                        endDate = .now
                    }
                }

                HStack(spacing: 8) {
                    quickPresetButton("Last 7 Days") {
                        let calendar = Calendar.current
                        startDate = calendar.date(byAdding: .day, value: -6, to: calendar.startOfDay(for: .now)) ?? .now
                        endDate = .now
                    }

                    quickPresetButton("Last 30 Days") {
                        let calendar = Calendar.current
                        startDate = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: .now)) ?? .now
                        endDate = .now
                    }

                    quickPresetButton("This Year") {
                        let calendar = Calendar.current
                        if let yearStart = calendar.dateInterval(of: .year, for: .now)?.start {
                            startDate = yearStart
                        }
                        endDate = .now
                    }
                }
            }

            Divider()

            HStack {
                Spacer()

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(BrutalTheme.accent)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: 280)
    }

    private func quickPresetButton(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(BrutalTheme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }
}
