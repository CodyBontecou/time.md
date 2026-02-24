import SwiftUI

struct ExportsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var selectedDestination: NavigationDestination = .overview
    @State private var selectedFormat: ExportFormat = .csv
    @State private var isExporting = false
    @State private var showSuccess = false
    @State private var lastExportURL: URL?
    @State private var lastMessage = ""
    @State private var showError = false
    @State private var errorMessage = ""

    // Export settings
    @State private var exportSettings = ExportSettings.load()
    @State private var exportEstimate: ExportEstimate?
    @State private var isLoadingEstimate = false
    
    // Field selection
    @State private var showFieldSelection = false

    // Progress tracking
    @State private var exportProgress = ExportProgress()
    @State private var showProgressSheet = false
    @State private var exportTask: Task<Void, Never>?

    // Weekly summary card preview
    @State private var isGeneratingCard = false
    @State private var cardPreviewURL: URL?

    // Clipboard
    @State private var copiedToClipboard = false
    
    // Combined export
    @State private var showCombinedExport = false
    @State private var combinedExportSections = ExportSectionSelection.allExceptRaw
    @State private var combinedExportFormat: ExportFormat = .csv
    @State private var combinedExportEstimate: ExportEstimate?
    @State private var isLoadingCombinedEstimate = false
    
    // Presets
    @State private var presetStore = ExportPresetStore()
    @State private var showSavePresetSheet = false
    @State private var newPresetName = ""
    @State private var selectedPreset: ExportPreset?
    @State private var showPresetPicker = false
    
    // Schedules
    @State private var scheduleStore = ExportScheduleStore()
    @State private var showScheduleSheet = false
    @State private var editingSchedule: ExportSchedule?

    private var exportableDestinations: [NavigationDestination] {
        NavigationDestination.allCases.filter { $0.isExportable }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // ─── Header ───
                headerSection
                
                // ─── Saved Presets Row ───
                presetsSection

                // ─── Quick Actions Row ───
                quickActionsSection

                // ─── Data Export Section ───
                dataExportSection
                
                // ─── Combined Export Section ───
                combinedExportSection

                // ─── Scheduled Exports Section ───
                scheduledExportsSection

                // ─── Weekly Summary Card Section ───
                weeklySummarySection

                // ─── Status Section ───
                if showSuccess || showError {
                    statusSection
                }
            }
        }
        .scrollClipDisabled()
        .scrollIndicators(.never)
        .sheet(isPresented: $showProgressSheet) {
            ExportProgressSheet(progress: exportProgress, onCancel: cancelExport)
        }

    }

    // MARK: - Header Section

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text("Export & Share")
                    .font(.system(size: 26, weight: .bold, design: .default))
                    .foregroundColor(BrutalTheme.textPrimary)

                Spacer()

                // Granularity badge
                HStack(spacing: 6) {
                    Image(systemName: "clock")
                        .font(.system(size: 11, weight: .semibold))
                    Text(filters.granularity.title)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(BrutalTheme.accent)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(BrutalTheme.accent.opacity(0.1))
                )

                // Date range badge
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                    Text(filters.rangeLabel)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundColor(BrutalTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.ultraThinMaterial)
                )
            }

            Text("Export your screen time data in multiple formats or generate shareable summary cards.")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }

    // MARK: - Presets Section
    
    private var presetsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("SAVED PRESETS")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1)
                    
                    Spacer()
                    
                    // Save current as preset button
                    Button {
                        newPresetName = ""
                        showSavePresetSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Save Current")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(BrutalTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                
                // Preset pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(presetStore.allPresets) { preset in
                            presetPill(preset)
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showSavePresetSheet) {
            savePresetSheet
        }
    }
    
    private func presetPill(_ preset: ExportPreset) -> some View {
        Button {
            applyPreset(preset)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: preset.format.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 1) {
                    Text(preset.name)
                        .font(.system(size: 11, weight: .semibold))
                    
                    if let desc = preset.description {
                        Text(desc)
                            .font(.system(size: 9, weight: .medium))
                            .opacity(0.7)
                    }
                }
                
                if preset.isBuiltIn {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 8))
                        .opacity(0.5)
                }
            }
            .foregroundColor(selectedPreset?.id == preset.id ? .white : BrutalTheme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selectedPreset?.id == preset.id ? BrutalTheme.accent : BrutalTheme.accent.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            if !preset.isBuiltIn {
                Button {
                    // Edit preset - just select and allow modification
                    applyPreset(preset)
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    presetStore.deletePreset(id: preset.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            
            Button {
                _ = presetStore.duplicatePreset(preset)
            } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            
            Divider()
            
            Button {
                Task { await exportWithPreset(preset) }
            } label: {
                Label("Export Now", systemImage: "square.and.arrow.up")
            }
        }
    }
    
    private var savePresetSheet: some View {
        VStack(spacing: 20) {
            Text("Save Export Preset")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BrutalTheme.textPrimary)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Preset Name")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                TextField("My Export Preset", text: $newPresetName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Configuration")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Format: \(combinedExportFormat.displayName)")
                    Text("Sections: \(combinedExportSections.count) selected")
                }
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
            }
            
            HStack(spacing: 12) {
                Button {
                    showSavePresetSheet = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                
                Button {
                    saveCurrentAsPreset()
                } label: {
                    Text("Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrutalTheme.accent)
                .disabled(newPresetName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    private func applyPreset(_ preset: ExportPreset) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedPreset = preset
            combinedExportFormat = preset.format
            combinedExportSections = preset.sections
            exportSettings = preset.settings
            showCombinedExport = true
            
            // Apply date range
            let range = preset.resolvedDateRange()
            filters.startDate = range.start
            filters.endDate = range.end
        }
        
        Task { await updateCombinedEstimate() }
    }
    
    private func saveCurrentAsPreset() {
        let preset = ExportPreset(
            name: newPresetName.trimmingCharacters(in: .whitespaces),
            format: combinedExportFormat,
            sections: combinedExportSections,
            settings: exportSettings,
            dateRangeType: .relative,
            relativeDateRange: .last7Days,
            isBuiltIn: false
        )
        
        presetStore.addPreset(preset)
        showSavePresetSheet = false
    }
    
    private func exportWithPreset(_ preset: ExportPreset) async {
        applyPreset(preset)
        await exportCombined()
    }

    // MARK: - Quick Actions Section

    private var quickActionsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("QUICK ACTIONS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                HStack(spacing: 12) {
                    // Copy to Clipboard
                    quickActionButton(
                        icon: copiedToClipboard ? "checkmark.circle.fill" : "doc.on.clipboard",
                        title: copiedToClipboard ? "Copied!" : "Copy Stats",
                        subtitle: "Formatted text",
                        color: BrutalTheme.accent,
                        isLoading: false
                    ) {
                        Task { await copyToClipboard() }
                    }

                    // Quick CSV
                    quickActionButton(
                        icon: "tablecells",
                        title: "Quick CSV",
                        subtitle: "All data",
                        color: BrutalTheme.accent,
                        isLoading: isExporting && selectedDestination == .overview
                    ) {
                        Task { await quickExport(format: .csv) }
                    }

                    // Quick JSON
                    quickActionButton(
                        icon: "curlybraces",
                        title: "Quick JSON",
                        subtitle: "All data",
                        color: BrutalTheme.accent,
                        isLoading: isExporting
                    ) {
                        Task { await quickExport(format: .json) }
                    }
                }
            }
        }
    }

    private func quickActionButton(
        icon: String,
        title: String,
        subtitle: String,
        color: Color,
        isLoading: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(color.opacity(0.15))
                        .frame(width: 48, height: 48)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: icon)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundColor(color)
                    }
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(subtitle)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.glass)
        .disabled(isLoading || isExporting)
    }

    // MARK: - Data Export Section

    private var dataExportSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                Text("DATA EXPORT")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)

                // Scope picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Scope")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(exportableDestinations) { destination in
                                scopeButton(destination)
                            }
                        }
                    }
                }

                Divider()
                    .opacity(0.3)

                // Field selection section
                fieldSelectionSection

                Divider()
                    .opacity(0.3)

                // Timestamp format picker (for CSV/JSON)
                timestampFormatSection

                Divider()
                    .opacity(0.3)

                // CSV/JSON Format customization (collapsible)
                formatCustomizationSection

                Divider()
                    .opacity(0.3)

                // Format buttons
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose Format")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)

                    HStack(spacing: 12) {
                        ForEach(ExportFormat.allCases) { format in
                            exportFormatButton(format)
                        }
                    }
                }

                // Estimation section
                if let estimate = exportEstimate {
                    estimationSection(estimate)
                } else if isLoadingEstimate {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Estimating export size...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .padding(.top, 4)
                }

                // Info text
                Text("Exports include active date range, granularity, and current cross-filter selections.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.top, 4)
            }
        }
        .onChange(of: selectedDestination) { _, _ in
            Task { await updateEstimate() }
        }
        .onChange(of: selectedFormat) { _, _ in
            Task { await updateEstimate() }
        }
        .onChange(of: filters.granularity) { _, _ in
            Task { await updateEstimate() }
            Task { await updateCombinedEstimate() }
        }
        .onChange(of: filters.startDate) { _, _ in
            Task { await updateEstimate() }
            Task { await updateCombinedEstimate() }
        }
        .onChange(of: filters.endDate) { _, _ in
            Task { await updateEstimate() }
            Task { await updateCombinedEstimate() }
        }
        .task {
            await updateEstimate()
        }
    }
    
    // MARK: - Field Selection Section
    
    private var fieldSelectionSection: some View {
        let availableFields = exportSettings.availableFields(for: selectedDestination)
        let fieldSelection = exportSettings.fieldSelection(for: selectedDestination)
        
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Fields to Export")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                Spacer()
                
                // Select All / Deselect All buttons
                HStack(spacing: 8) {
                    Button {
                        var newSelection = fieldSelection
                        newSelection.selectedFields = Set(availableFields)
                        exportSettings.setFieldSelection(newSelection, for: selectedDestination)
                        exportSettings.save()
                    } label: {
                        Text("All")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(fieldSelection.allSelected(from: availableFields))
                    
                    Text("·")
                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                    
                    Button {
                        var newSelection = fieldSelection
                        newSelection.selectedFields = []
                        exportSettings.setFieldSelection(newSelection, for: selectedDestination)
                        exportSettings.save()
                    } label: {
                        Text("None")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .disabled(fieldSelection.isEmpty)
                }
            }
            
            // Field checkboxes in a flow layout
            FlowLayout(spacing: 8) {
                ForEach(availableFields) { field in
                    fieldToggleButton(field: field, selection: fieldSelection)
                }
            }
            
            // Selected count indicator
            let selectedCount = fieldSelection.filter(availableFields).count
            if selectedCount < availableFields.count && selectedCount > 0 {
                Text("\(selectedCount) of \(availableFields.count) fields selected")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
        }
    }
    
    private func fieldToggleButton(field: ExportField, selection: ExportFieldSelection) -> some View {
        let isSelected = selection.selectedFields.contains(field)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                var newSelection = selection
                if isSelected {
                    newSelection.selectedFields.remove(field)
                } else {
                    newSelection.selectedFields.insert(field)
                }
                exportSettings.setFieldSelection(newSelection, for: selectedDestination)
                exportSettings.save()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)
                
                Text(field.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? BrutalTheme.accent.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? BrutalTheme.accent.opacity(0.3) : BrutalTheme.textTertiary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Format Customization Section
    
    @State private var showFormatOptions = false
    
    private var formatCustomizationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showFormatOptions.toggle()
                }
            } label: {
                HStack {
                    Text("Format Options")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Image(systemName: showFormatOptions ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Spacer()
                }
            }
            .buttonStyle(.plain)
            
            if showFormatOptions {
                VStack(alignment: .leading, spacing: 16) {
                    // CSV Options
                    csvOptionsSection
                    
                    Divider()
                        .opacity(0.2)
                    
                    // JSON Options
                    jsonOptionsSection
                }
                .padding(.top, 4)
            }
        }
    }
    
    private var csvOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("CSV")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
            
            // Delimiter picker
            HStack {
                Text("Delimiter")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    ForEach(CSVExportOptions.CSVDelimiter.allCases) { delimiter in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                exportSettings.csvOptions.delimiter = delimiter
                                exportSettings.save()
                            }
                        } label: {
                            Text(delimiter.displayName)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(exportSettings.csvOptions.delimiter == delimiter ? .white : BrutalTheme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .tint(exportSettings.csvOptions.delimiter == delimiter ? BrutalTheme.accent : .clear)
                    }
                }
            }
            
            // Quote style picker
            HStack {
                Text("Quoting")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    ForEach(CSVExportOptions.CSVQuoteStyle.allCases) { style in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                exportSettings.csvOptions.quoteStyle = style
                                exportSettings.save()
                            }
                        } label: {
                            Text(style.displayName)
                                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                .foregroundColor(exportSettings.csvOptions.quoteStyle == style ? .white : BrutalTheme.textTertiary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                        .tint(exportSettings.csvOptions.quoteStyle == style ? BrutalTheme.accent : .clear)
                    }
                }
            }
            
            // Toggles
            HStack(spacing: 16) {
                Toggle(isOn: $exportSettings.csvOptions.includeHeader) {
                    Text("Include Header")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: exportSettings.csvOptions.includeHeader) { _, _ in
                    exportSettings.save()
                }
                
                Toggle(isOn: $exportSettings.csvOptions.includeMetadataComments) {
                    Text("Include Comments")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: exportSettings.csvOptions.includeMetadataComments) { _, _ in
                    exportSettings.save()
                }
            }
        }
    }
    
    private var jsonOptionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("JSON")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
            
            // Structure picker
            HStack {
                Text("Structure")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                Spacer()
                
                HStack(spacing: 6) {
                    ForEach(JSONExportOptions.JSONStructure.allCases) { structure in
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                exportSettings.jsonOptions.structure = structure
                                exportSettings.save()
                            }
                        } label: {
                            VStack(spacing: 2) {
                                Text(structure.displayName)
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                Text(structure.description)
                                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                                    .opacity(0.7)
                            }
                            .foregroundColor(exportSettings.jsonOptions.structure == structure ? .white : BrutalTheme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.glass)
                        .tint(exportSettings.jsonOptions.structure == structure ? BrutalTheme.accent : .clear)
                    }
                }
            }
            
            // Toggles
            HStack(spacing: 16) {
                Toggle(isOn: $exportSettings.jsonOptions.prettyPrint) {
                    Text("Pretty Print")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: exportSettings.jsonOptions.prettyPrint) { _, _ in
                    exportSettings.save()
                }
                
                Toggle(isOn: $exportSettings.jsonOptions.includeMetadata) {
                    Text("Include Metadata")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: exportSettings.jsonOptions.includeMetadata) { _, _ in
                    exportSettings.save()
                }
                .disabled(exportSettings.jsonOptions.structure == .flat)
                
                Toggle(isOn: $exportSettings.jsonOptions.sortKeys) {
                    Text("Sort Keys")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                }
                .toggleStyle(.checkbox)
                .onChange(of: exportSettings.jsonOptions.sortKeys) { _, _ in
                    exportSettings.save()
                }
            }
        }
    }

    // MARK: - Timestamp Format Section

    private var timestampFormatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Timestamp Format")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)

                Spacer()

                Text("Example: \(exportSettings.timestampFormat.example)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }

            HStack(spacing: 8) {
                ForEach(ExportTimestampFormat.allCases) { format in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            exportSettings.timestampFormat = format
                            exportSettings.save()
                        }
                    } label: {
                        Text(format.displayName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundColor(exportSettings.timestampFormat == format ? .white : BrutalTheme.textTertiary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glass)
                    .tint(exportSettings.timestampFormat == format ? BrutalTheme.accent : .clear)
                }
            }
        }
    }

    // MARK: - Estimation Section

    private func estimationSection(_ estimate: ExportEstimate) -> some View {
        HStack(spacing: 16) {
            // Row count
            VStack(alignment: .leading, spacing: 2) {
                Text("Rows")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                Text(estimate.formattedRowCount)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }

            // File size
            VStack(alignment: .leading, spacing: 2) {
                Text("Est. Size")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(BrutalTheme.textTertiary)
                Text(estimate.formattedSize)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)
            }

            Spacer()

            // Large export warning
            if estimate.isLarge {
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                    Text("Large export — may take a moment")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(BrutalTheme.textTertiary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.ultraThinMaterial)
        )
    }

    private func scopeButton(_ destination: NavigationDestination) -> some View {
        let isSelected = selectedDestination == destination

        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedDestination = destination
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: destination.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                Text(destination.title)
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
            }
            .foregroundColor(isSelected ? .white : BrutalTheme.textTertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
        }
        .buttonStyle(.glass)
        .tint(isSelected ? BrutalTheme.accent : .clear)
    }

    private func exportFormatButton(_ format: ExportFormat) -> some View {
        Button {
            Task { await export(format: format) }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: format.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(formatColor(format))

                Text(format.displayName)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundColor(BrutalTheme.textPrimary)

                Text(formatDescription(format))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.glass)
        .disabled(isExporting)
    }

    private func formatColor(_ format: ExportFormat) -> Color {
        switch format {
        case .csv: BrutalTheme.accent
        case .json: BrutalTheme.accent.opacity(0.8)
        case .pdf: BrutalTheme.textSecondary
        case .png: BrutalTheme.accent
        }
    }

    private func formatDescription(_ format: ExportFormat) -> String {
        switch format {
        case .csv: "Spreadsheets"
        case .json: "Developers"
        case .pdf: "Reports"
        case .png: "Images"
        }
    }

    // MARK: - Scheduled Exports Section
    
    private var scheduledExportsSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SCHEDULED EXPORTS")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)
                        
                        Text("Automate recurring exports")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    Button {
                        editingSchedule = nil
                        showScheduleSheet = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                            Text("Add Schedule")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundColor(BrutalTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                
                if scheduleStore.schedules.isEmpty {
                    HStack {
                        Image(systemName: "calendar.badge.clock")
                            .font(.system(size: 24))
                            .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("No scheduled exports")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BrutalTheme.textSecondary)
                            Text("Create a schedule to automatically export data on a recurring basis")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
                    }
                    .padding(.vertical, 8)
                } else {
                    VStack(spacing: 8) {
                        ForEach(scheduleStore.schedules) { schedule in
                            scheduleRow(schedule)
                        }
                    }
                }
                
                // Note about background execution
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                    Text("Scheduled exports run when the app is open. Background execution requires system permissions.")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(BrutalTheme.textTertiary.opacity(0.7))
                .padding(.top, 4)
            }
        }
        .sheet(isPresented: $showScheduleSheet) {
            scheduleEditorSheet
        }
    }
    
    private func scheduleRow(_ schedule: ExportSchedule) -> some View {
        let preset = presetStore.allPresets.first { $0.id == schedule.presetId }
        
        return HStack(spacing: 12) {
            // Enable/disable toggle
            Toggle("", isOn: Binding(
                get: { schedule.isEnabled },
                set: { _ in scheduleStore.toggleSchedule(id: schedule.id) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .scaleEffect(0.7)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(preset?.name ?? "Unknown Preset")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(schedule.isEnabled ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                
                Text(schedule.scheduleDescription)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            
            Spacer()
            
            // Last run status
            if let lastRun = schedule.lastRunAt {
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: schedule.lastRunSuccess == true ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundColor(schedule.lastRunSuccess == true ? .green : .red)
                        Text(lastRun, style: .relative)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                }
            }
            
            // Actions
            Menu {
                Button {
                    Task { await runScheduleNow(schedule) }
                } label: {
                    Label("Run Now", systemImage: "play.fill")
                }
                
                Button {
                    editingSchedule = schedule
                    showScheduleSheet = true
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    scheduleStore.deleteSchedule(id: schedule.id)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 14))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(schedule.isEnabled ? BrutalTheme.accent.opacity(0.05) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(BrutalTheme.textTertiary.opacity(0.1), lineWidth: 1)
                )
        )
    }
    
    @State private var schedulePresetId: UUID = ExportPreset.builtInPresets.first?.id ?? UUID()
    @State private var scheduleFrequency: ScheduleFrequency = .daily
    @State private var scheduleHour: Int = 8
    @State private var scheduleMinute: Int = 0
    @State private var scheduleDayOfWeek: Int = 1
    @State private var scheduleDayOfMonth: Int = 1
    
    private var scheduleEditorSheet: some View {
        VStack(spacing: 20) {
            Text(editingSchedule == nil ? "New Schedule" : "Edit Schedule")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BrutalTheme.textPrimary)
            
            VStack(alignment: .leading, spacing: 16) {
                // Preset picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Export Preset")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Picker("Preset", selection: $schedulePresetId) {
                        ForEach(presetStore.allPresets) { preset in
                            Text(preset.name).tag(preset.id)
                        }
                    }
                    .labelsHidden()
                }
                
                // Frequency picker
                VStack(alignment: .leading, spacing: 6) {
                    Text("Frequency")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    Picker("Frequency", selection: $scheduleFrequency) {
                        ForEach(ScheduleFrequency.allCases) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                
                // Day picker (for weekly/monthly)
                if scheduleFrequency == .weekly {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Day of Week")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                        
                        Picker("Day", selection: $scheduleDayOfWeek) {
                            Text("Sunday").tag(1)
                            Text("Monday").tag(2)
                            Text("Tuesday").tag(3)
                            Text("Wednesday").tag(4)
                            Text("Thursday").tag(5)
                            Text("Friday").tag(6)
                            Text("Saturday").tag(7)
                        }
                        .labelsHidden()
                    }
                } else if scheduleFrequency == .monthly {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Day of Month")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                        
                        Picker("Day", selection: $scheduleDayOfMonth) {
                            ForEach(1...28, id: \.self) { day in
                                Text("\(day)").tag(day)
                            }
                        }
                        .labelsHidden()
                    }
                }
                
                // Time picker
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Hour")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                        
                        Picker("Hour", selection: $scheduleHour) {
                            ForEach(0..<24, id: \.self) { hour in
                                Text(String(format: "%02d", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Minute")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                        
                        Picker("Minute", selection: $scheduleMinute) {
                            ForEach([0, 15, 30, 45], id: \.self) { minute in
                                Text(String(format: "%02d", minute)).tag(minute)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 80)
                    }
                }
            }
            
            HStack(spacing: 12) {
                Button {
                    showScheduleSheet = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(BrutalTheme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.bordered)
                
                Button {
                    saveSchedule()
                } label: {
                    Text(editingSchedule == nil ? "Create" : "Save")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(BrutalTheme.accent)
            }
        }
        .padding(24)
        .frame(width: 360)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
        .onAppear {
            if let schedule = editingSchedule {
                schedulePresetId = schedule.presetId
                scheduleFrequency = schedule.frequency
                scheduleHour = schedule.hour
                scheduleMinute = schedule.minute
                scheduleDayOfWeek = schedule.dayOfWeek ?? 1
                scheduleDayOfMonth = schedule.dayOfMonth ?? 1
            } else {
                schedulePresetId = presetStore.allPresets.first?.id ?? UUID()
                scheduleFrequency = .daily
                scheduleHour = 8
                scheduleMinute = 0
            }
        }
    }
    
    private func saveSchedule() {
        if var schedule = editingSchedule {
            schedule.presetId = schedulePresetId
            schedule.frequency = scheduleFrequency
            schedule.hour = scheduleHour
            schedule.minute = scheduleMinute
            schedule.dayOfWeek = scheduleFrequency == .weekly ? scheduleDayOfWeek : nil
            schedule.dayOfMonth = scheduleFrequency == .monthly ? scheduleDayOfMonth : nil
            scheduleStore.updateSchedule(schedule)
        } else {
            let schedule = ExportSchedule(
                presetId: schedulePresetId,
                frequency: scheduleFrequency,
                hour: scheduleHour,
                minute: scheduleMinute,
                dayOfWeek: scheduleFrequency == .weekly ? scheduleDayOfWeek : nil,
                dayOfMonth: scheduleFrequency == .monthly ? scheduleDayOfMonth : nil
            )
            scheduleStore.addSchedule(schedule)
        }
        showScheduleSheet = false
    }
    
    private func runScheduleNow(_ schedule: ExportSchedule) async {
        guard let preset = presetStore.allPresets.first(where: { $0.id == schedule.presetId }) else {
            scheduleStore.recordRun(id: schedule.id, success: false, error: "Preset not found")
            return
        }
        
        do {
            let config = CombinedExportConfig(
                sections: preset.sections,
                format: preset.format
            )
            
            let range = preset.resolvedDateRange()
            var filters = self.filters.snapshot
            filters.startDate = range.start
            filters.endDate = range.end
            
            _ = try await appEnvironment.exportCoordinator.exportCombined(
                config: config,
                filters: filters,
                settings: preset.settings,
                progress: nil
            )
            
            scheduleStore.recordRun(id: schedule.id, success: true)
        } catch {
            scheduleStore.recordRun(id: schedule.id, success: false, error: error.localizedDescription)
        }
    }
    
    // MARK: - Combined Export Section
    
    private var combinedExportSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("COMBINED EXPORT")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)
                        
                        Text("Export multiple data types in a single file")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    
                    Spacer()
                    
                    // Toggle to expand/collapse
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showCombinedExport.toggle()
                        }
                    } label: {
                        Image(systemName: showCombinedExport ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                
                if showCombinedExport {
                    Divider().opacity(0.3)
                    
                    // Section selection
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Sections to Include")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(BrutalTheme.textTertiary)
                            
                            Spacer()
                            
                            // Quick presets
                            HStack(spacing: 6) {
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        combinedExportSections = .quickSummary
                                    }
                                } label: {
                                    Text("Quick")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                
                                Text("·")
                                    .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        combinedExportSections = .allExceptRaw
                                    }
                                } label: {
                                    Text("Basic")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                
                                Text("·")
                                    .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        combinedExportSections = .withAnalytics
                                    }
                                } label: {
                                    Text("+ Analytics")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                                
                                Text("·")
                                    .foregroundColor(BrutalTheme.textTertiary.opacity(0.5))
                                
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        combinedExportSections = .full
                                    }
                                } label: {
                                    Text("Full")
                                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        
                        // Basic data sections
                        Text("Data")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .padding(.top, 4)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(ExportSection.basicSections) { section in
                                combinedSectionToggle(section)
                            }
                        }
                        
                        // Analytics sections
                        HStack {
                            Text("Analytics")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(BrutalTheme.textTertiary)
                            
                            Text("(computed)")
                                .font(.system(size: 9, weight: .medium))
                                .foregroundColor(BrutalTheme.textTertiary.opacity(0.6))
                        }
                        .padding(.top, 8)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(ExportSection.analyticsSections) { section in
                                combinedSectionToggle(section)
                            }
                        }
                        
                        // Selected count
                        if !combinedExportSections.isEmpty {
                            let basicCount = combinedExportSections.sections.filter { !$0.isAnalytics }.count
                            let analyticsCount = combinedExportSections.sections.filter { $0.isAnalytics }.count
                            
                            HStack(spacing: 8) {
                                Text("\(combinedExportSections.count) section\(combinedExportSections.count == 1 ? "" : "s") selected")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(BrutalTheme.textTertiary)
                                
                                if analyticsCount > 0 {
                                    Text("(\(basicCount) data, \(analyticsCount) analytics)")
                                        .font(.system(size: 9, weight: .medium))
                                        .foregroundColor(BrutalTheme.textTertiary.opacity(0.6))
                                }
                            }
                        }
                    }
                    
                    Divider().opacity(0.3)
                    
                    // Format selection and export button
                    HStack(spacing: 12) {
                        // Format picker
                        HStack(spacing: 6) {
                            ForEach(ExportFormat.allCases) { format in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        combinedExportFormat = format
                                    }
                                    Task { await updateCombinedEstimate() }
                                } label: {
                                    Text(format.displayName)
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(combinedExportFormat == format ? .white : BrutalTheme.textTertiary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.glass)
                                .tint(combinedExportFormat == format ? BrutalTheme.accent : .clear)
                            }
                        }
                        
                        Spacer()
                        
                        // Estimate
                        if let estimate = combinedExportEstimate {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text("\(estimate.formattedRowCount) rows")
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                Text("~\(estimate.formattedSize)")
                                    .font(.system(size: 9, weight: .medium))
                            }
                            .foregroundColor(BrutalTheme.textTertiary)
                        } else if isLoadingCombinedEstimate {
                            ProgressView()
                                .scaleEffect(0.6)
                        }
                        
                        // Export button
                        Button {
                            Task { await exportCombined() }
                        } label: {
                            HStack(spacing: 4) {
                                if isExporting {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                Text("Export")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(BrutalTheme.accent)
                        .disabled(isExporting || combinedExportSections.isEmpty)
                    }
                }
            }
        }
        .onChange(of: combinedExportSections.sections) { _, _ in
            Task { await updateCombinedEstimate() }
        }
        .task {
            if showCombinedExport {
                await updateCombinedEstimate()
            }
        }
    }
    
    private func combinedSectionToggle(_ section: ExportSection) -> some View {
        let isSelected = combinedExportSections.contains(section)
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                combinedExportSections.toggle(section)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)
                
                Image(systemName: section.systemImage)
                    .font(.system(size: 10))
                    .foregroundColor(isSelected ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
                
                Text(section.displayName)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(isSelected ? BrutalTheme.textPrimary : BrutalTheme.textTertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? BrutalTheme.accent.opacity(0.15) : Color.clear)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isSelected ? BrutalTheme.accent.opacity(0.3) : BrutalTheme.textTertiary.opacity(0.2), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
    
    private func exportCombined() async {
        isExporting = true
        showSuccess = false
        showError = false
        
        let isLarge = combinedExportEstimate?.isLarge ?? false
        
        if isLarge {
            exportProgress.reset()
            showProgressSheet = true
        }
        
        exportTask = Task {
            defer {
                Task { @MainActor in
                    isExporting = false
                    showProgressSheet = false
                }
            }
            
            do {
                let config = CombinedExportConfig(
                    sections: combinedExportSections,
                    format: combinedExportFormat
                )
                
                let url = try await appEnvironment.exportCoordinator.exportCombined(
                    config: config,
                    filters: filters.snapshot,
                    settings: exportSettings,
                    progress: isLarge ? exportProgress : nil
                )
                
                await MainActor.run {
                    lastExportURL = url
                    withAnimation {
                        showSuccess = true
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    lastMessage = "Export cancelled"
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    withAnimation {
                        showError = true
                    }
                }
            }
        }
    }
    
    private func updateCombinedEstimate() async {
        guard !combinedExportSections.isEmpty else {
            combinedExportEstimate = nil
            return
        }
        
        isLoadingCombinedEstimate = true
        
        do {
            let estimate = try await appEnvironment.exportCoordinator.estimateCombinedExport(
                sections: combinedExportSections,
                filters: filters.snapshot,
                format: combinedExportFormat
            )
            await MainActor.run {
                combinedExportEstimate = estimate
                isLoadingCombinedEstimate = false
            }
        } catch {
            await MainActor.run {
                isLoadingCombinedEstimate = false
            }
        }
    }

    // MARK: - Weekly Summary Section

    private var weeklySummarySection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SHAREABLE SUMMARY CARD")
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1)

                        Text("Generate a beautiful image to share your screen time stats")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }

                    Spacer()

                    Button {
                        Task { await generateSummaryCard() }
                    } label: {
                        HStack(spacing: 6) {
                            if isGeneratingCard {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            Text("Generate")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(BrutalTheme.accent)
                    .disabled(isGeneratingCard)
                }

                // Preview area
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.black.opacity(0.3))
                        .frame(height: 200)

                    if let cardURL = cardPreviewURL {
                        AsyncImage(url: cardURL) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 200)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.on.rectangle")
                                .font(.system(size: 32, weight: .light))
                                .foregroundColor(BrutalTheme.textTertiary)
                            Text("Preview will appear here")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BrutalTheme.textTertiary)
                        }
                    }
                }

                if cardPreviewURL != nil {
                    HStack(spacing: 12) {
                        Button {
                            if let url = cardPreviewURL {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "folder")
                                Text("Show in Finder")
                            }
                            .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.glass)

                        Button {
                            if let url = cardPreviewURL,
                               let image = NSImage(contentsOf: url) {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.writeObjects([image])
                                withAnimation {
                                    copiedToClipboard = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    withAnimation { copiedToClipboard = false }
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.clipboard")
                                Text("Copy Image")
                            }
                            .font(.system(size: 11, weight: .semibold))
                        }
                        .buttonStyle(.glass)

                        Spacer()
                    }
                }
            }
        }
    }

    // MARK: - Status Section

    private var statusSection: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: showError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(showError ? BrutalTheme.danger : BrutalTheme.accent)

                    Text(showError ? "Export Failed" : "Export Complete")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)

                    Spacer()

                    Button {
                        withAnimation {
                            showSuccess = false
                            showError = false
                        }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                if showError {
                    Text(errorMessage)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(BrutalTheme.textSecondary)
                } else if let url = lastExportURL {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(url.lastPathComponent)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        HStack(spacing: 8) {
                            Button {
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "folder")
                                    Text("Show in Finder")
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.glass)

                            Button {
                                NSWorkspace.shared.open(url)
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.up.forward.square")
                                    Text("Open")
                                }
                                .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.glass)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private func export(format: ExportFormat) async {
        selectedFormat = format
        isExporting = true
        showSuccess = false
        showError = false

        // Show progress for large exports
        let isLargeExport = (exportEstimate?.isLarge ?? false) && (format == .csv || format == .json)

        if isLargeExport {
            exportProgress.reset()
            showProgressSheet = true
        }

        exportTask = Task {
            defer {
                Task { @MainActor in
                    isExporting = false
                    showProgressSheet = false
                }
            }

            do {
                let url = try await appEnvironment.exportCoordinator.export(
                    format: format,
                    from: selectedDestination,
                    filters: filters.snapshot,
                    settings: exportSettings,
                    progress: isLargeExport ? exportProgress : nil
                )

                await MainActor.run {
                    lastExportURL = url
                    withAnimation {
                        showSuccess = true
                    }
                }
            } catch is CancellationError {
                await MainActor.run {
                    lastMessage = "Export cancelled"
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    withAnimation {
                        showError = true
                    }
                }
            }
        }
    }

    private func cancelExport() {
        exportProgress.cancel()
        exportTask?.cancel()
        showProgressSheet = false
        isExporting = false
    }

    private func quickExport(format: ExportFormat) async {
        // Quick export defaults to overview
        let tempDest = selectedDestination
        selectedDestination = .overview
        await export(format: format)
        selectedDestination = tempDest
    }

    private func copyToClipboard() async {
        do {
            _ = try await appEnvironment.exportCoordinator.copyStatsToClipboard(filters: filters.snapshot)
            withAnimation {
                copiedToClipboard = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                withAnimation { copiedToClipboard = false }
            }
        } catch {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }
    }

    private func generateSummaryCard() async {
        isGeneratingCard = true
        showSuccess = false
        showError = false

        defer { isGeneratingCard = false }

        do {
            let url = try await appEnvironment.exportCoordinator.generateWeeklySummaryCard(filters: filters.snapshot)
            cardPreviewURL = url
            lastExportURL = url
            withAnimation {
                showSuccess = true
            }
        } catch {
            errorMessage = error.localizedDescription
            withAnimation {
                showError = true
            }
        }
    }

    private func updateEstimate() async {
        isLoadingEstimate = true
        exportEstimate = nil

        do {
            let estimate = try await appEnvironment.exportCoordinator.estimateExport(
                from: selectedDestination,
                filters: filters.snapshot,
                format: selectedFormat
            )
            await MainActor.run {
                exportEstimate = estimate
                isLoadingEstimate = false
            }
        } catch {
            await MainActor.run {
                isLoadingEstimate = false
            }
        }
    }
}

// MARK: - Export Progress Sheet

private struct ExportProgressSheet: View {
    @Bindable var progress: ExportProgress
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Text("Exporting...")
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(BrutalTheme.textPrimary)

            VStack(spacing: 8) {
                ProgressView(value: progress.fractionComplete)
                    .progressViewStyle(.linear)
                    .tint(BrutalTheme.accent)

                Text(progress.statusText)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundColor(BrutalTheme.textSecondary)
            }

            Button {
                onCancel()
            } label: {
                Text("Cancel")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red.opacity(0.8))
        }
        .padding(32)
        .frame(width: 320)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
}
