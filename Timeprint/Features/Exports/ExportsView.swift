import SwiftUI

struct ExportsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var selectedFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var showSuccess = false
    @State private var lastExportURL: URL?
    @State private var showError = false
    @State private var errorMessage = ""
    
    // Filter presets
    @State private var filterPresetStore = ExportFilterPresetStore()
    @State private var selectedPresetId: UUID?
    @State private var editingPreset: ExportFilterPreset?
    @State private var availableApps: [String] = []
    
    // Custom date range for export
    @State private var showDatePicker = false
    @State private var customStartDate: Date?
    @State private var customEndDate: Date?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                headerSection
                
                // Filter Presets Section (NEW)
                filterPresetSection
                
                // Format Selection
                formatSelectionSection
                
                // Export Button
                exportButtonSection
                
                // Status
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
        .task {
            await loadAvailableApps()
        }
    }

    // MARK: - Header
    
    /// The effective start date for export (custom or from global filters)
    private var effectiveStartDate: Date {
        customStartDate ?? filters.startDate
    }
    
    /// The effective end date for export (custom or from global filters)
    private var effectiveEndDate: Date {
        customEndDate ?? filters.endDate
    }
    
    /// Whether a custom date range is active
    private var hasCustomDateRange: Bool {
        customStartDate != nil || customEndDate != nil
    }
    
    /// Formatted date range label for display
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

                // Tappable date range badge
                Button {
                    // Initialize custom dates from current effective dates if not already set
                    if customStartDate == nil {
                        customStartDate = filters.startDate
                    }
                    if customEndDate == nil {
                        customEndDate = filters.endDate
                    }
                    showDatePicker = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 11, weight: .semibold))
                        Text(dateRangeLabel)
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

            Text("Export your screen time data with granular filtering options.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    // MARK: - Filter Preset Section

    private var filterPresetSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("FILTER PRESET")
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
                            Text("New")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(BrutalTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                
                // Preset selector
                presetSelector
                
                // Show active filters summary
                if let preset = selectedPreset, preset.hasFilters {
                    activeFiltersDisplay(preset)
                }
            }
        }
    }
    
    private var presetSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Quick selection buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    // No filter option
                    presetChip(nil, name: "All Data", icon: "square.stack.3d.up")
                    
                    // Built-in presets
                    ForEach(ExportFilterPresetStore.builtInPresets) { preset in
                        presetChip(preset.id, name: preset.name, icon: presetIcon(for: preset))
                    }
                    
                    // User presets
                    ForEach(filterPresetStore.userPresets) { preset in
                        presetChip(preset.id, name: preset.name, icon: "person.crop.circle", isUserPreset: true)
                    }
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
                
                Text(name)
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
        VStack(alignment: .leading, spacing: 8) {
            Divider()
                .opacity(0.5)
            
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(BrutalTheme.accent)
                
                Text(preset.filterSummary)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(BrutalTheme.textSecondary)
                
                Spacer()
                
                if let desc = preset.description {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }
    
    private var selectedPreset: ExportFilterPreset? {
        guard let id = selectedPresetId else { return nil }
        return filterPresetStore.allPresets.first { $0.id == id }
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
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? BrutalTheme.accent : BrutalTheme.accent.opacity(0.1))
                        .frame(width: 48, height: 48)

                    Image(systemName: format.systemImage)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isSelected ? .white : BrutalTheme.accent)
                }

                VStack(spacing: 4) {
                    Text(format.displayName)
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Text(format.description)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
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

    // MARK: - Export Button

    private var exportButtonSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                // Info about what will be exported
                HStack(spacing: 12) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Text(exportDescription)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                
                Divider()
                    .opacity(0.3)
                
                // Export button
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
                            .fill(isExporting ? BrutalTheme.accent.opacity(0.6) : BrutalTheme.accent)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isExporting)
            }
        }
    }
    
    private var exportDescription: String {
        var parts: [String] = []
        
        parts.append("Exports session data for the selected date range")
        
        if let preset = selectedPreset, preset.hasFilters {
            parts.append("with \(preset.name.lowercased()) filter applied")
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

                            Text(url.lastPathComponent)
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

                            Text(errorMessage)
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

    // MARK: - Export Logic
    
    private func loadAvailableApps() async {
        do {
            // Fetch top apps from the data service to populate the app picker
            let snapshot = filters.snapshot
            let apps = try await appEnvironment.dataService.fetchTopApps(filters: snapshot, limit: 500)
            await MainActor.run {
                availableApps = apps.map(\.appName)
            }
        } catch {
            print("Failed to load available apps: \(error)")
        }
    }

    private func performExport() async {
        isExporting = true
        showSuccess = false
        showError = false

        do {
            var snapshot = filters.snapshot
            
            // Apply custom date range if set
            snapshot.startDate = effectiveStartDate
            snapshot.endDate = effectiveEndDate
            
            // Apply the selected preset's filters
            if let preset = selectedPreset {
                preset.apply(to: &snapshot)
            }
            
            let coordinator = appEnvironment.exportCoordinator
            
            let url = try await coordinator.export(
                format: selectedFormat,
                from: .rawSessions,
                filters: snapshot
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
            // Header
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
            
            // Start Date
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
            
            // End Date
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
            
            // Quick presets
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
            
            // Done button
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
    
    private func quickPresetButton(_ title: String, action: @escaping () -> Void) -> some View {
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
