import SwiftUI

// MARK: - Preset Editor Wrapper

/// Wrapper view that bridges .sheet(item:) with the binding-based ExportFilterPresetEditor
struct PresetEditorWrapper: View {
    let initialPreset: ExportFilterPreset
    let availableApps: [String]
    let onSave: (ExportFilterPreset) -> Void
    let onCancel: () -> Void
    
    @State private var preset: ExportFilterPreset
    
    init(initialPreset: ExportFilterPreset, availableApps: [String], onSave: @escaping (ExportFilterPreset) -> Void, onCancel: @escaping () -> Void) {
        self.initialPreset = initialPreset
        self.availableApps = availableApps
        self.onSave = onSave
        self.onCancel = onCancel
        self._preset = State(initialValue: initialPreset)
    }
    
    var body: some View {
        ExportFilterPresetEditor(
            preset: $preset,
            availableApps: availableApps,
            onSave: { onSave(preset) },
            onCancel: onCancel
        )
    }
}

/// Editor view for creating or modifying an export filter preset
struct ExportFilterPresetEditor: View {
    @Binding var preset: ExportFilterPreset
    let availableApps: [String]
    let onSave: () -> Void
    let onCancel: () -> Void
    
    @State private var showingAppPicker = false
    @State private var showingTimeRangeEditor = false
    @State private var editingTimeRange: TimeRangeConfig?
    @State private var appSearchText = ""
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    nameSection
                    appFilterSection
                    timeRangeSection
                    weekdaySection
                    durationSection
                }
                .padding(20)
            }
            
            Divider()
            
            // Footer
            footer
        }
        .frame(width: 500, height: 600)
        .background(Color(NSColor.windowBackgroundColor))
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet(
                selectedApps: $preset.selectedApps,
                availableApps: availableApps
            )
        }
        .sheet(item: $editingTimeRange) { range in
            TimeRangeEditorSheet(
                range: range,
                onSave: { updated in
                    if let index = preset.timeRanges.firstIndex(where: { $0.id == updated.id }) {
                        preset.timeRanges[index] = updated
                    } else {
                        preset.timeRanges.append(updated)
                    }
                    editingTimeRange = nil
                },
                onCancel: {
                    editingTimeRange = nil
                }
            )
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        HStack {
            Text(preset.name.isEmpty ? "New Filter Preset" : "Edit Filter Preset")
                .font(.system(size: 16, weight: .semibold))
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
    
    // MARK: - Name Section
    
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NAME")
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1)
            
            TextField("Enter preset name", text: $preset.name)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 14))
            
            TextField("Description (optional)", text: Binding(
                get: { preset.description ?? "" },
                set: { preset.description = $0.isEmpty ? nil : $0 }
            ))
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12))
            .foregroundColor(BrutalTheme.textSecondary)
        }
    }
    
    // MARK: - App Filter Section
    
    private var appFilterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("APPS")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)
                
                Spacer()
                
                if !preset.selectedApps.isEmpty {
                    Button {
                        preset.selectedApps.removeAll()
                    } label: {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            // Mode picker
            Picker("Filter Mode", selection: $preset.appFilterMode) {
                ForEach(AppFilterMode.allCases) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            
            // Selected apps display
            if preset.selectedApps.isEmpty {
                Button {
                    showingAppPicker = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 14))
                        Text("Select apps to filter")
                            .font(.system(size: 13))
                    }
                    .foregroundColor(BrutalTheme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(BrutalTheme.accent.opacity(0.3), style: StrokeStyle(lineWidth: 1, dash: [5]))
                    )
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    // Show selected apps as chips
                    FlowLayout(spacing: 6) {
                        ForEach(Array(preset.selectedApps).sorted(), id: \.self) { app in
                            appChip(app)
                        }
                    }
                    
                    Button {
                        showingAppPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
                            Text("Edit Selection")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(BrutalTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(BrutalTheme.accent.opacity(0.05))
                )
            }
            
            Text(preset.appFilterMode.description)
                .font(.system(size: 11))
                .foregroundColor(BrutalTheme.textTertiary)
        }
    }
    
    private func appChip(_ app: String) -> some View {
        HStack(spacing: 4) {
            Text(verbatim: app)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
            
            Button {
                preset.selectedApps.remove(app)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    // MARK: - Time Range Section
    
    private var timeRangeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("TIME OF DAY")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)
                
                Spacer()
                
                Menu {
                    Button("Work Hours (9 AM – 5 PM)") {
                        addTimeRange(.workHours)
                    }
                    Button("Early Morning (5 AM – 9 AM)") {
                        addTimeRange(.earlyMorning)
                    }
                    Button("Evening (5 PM – 10 PM)") {
                        addTimeRange(.evening)
                    }
                    Button("Late Night (10 PM – 5 AM)") {
                        addTimeRange(.lateNight)
                    }
                    Divider()
                    Button("Custom Range...") {
                        editingTimeRange = TimeRangeConfig()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Add")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(BrutalTheme.accent)
                }
            }
            
            if preset.timeRanges.isEmpty {
                Text("No time filters – all hours included")
                    .font(.system(size: 12))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 6) {
                    ForEach(preset.timeRanges) { range in
                        timeRangeRow(range)
                    }
                }
            }
        }
    }
    
    private func timeRangeRow(_ range: TimeRangeConfig) -> some View {
        HStack {
            Image(systemName: "clock")
                .font(.system(size: 12))
                .foregroundColor(BrutalTheme.accent)
            
            Text(verbatim: range.displayName)
                .font(.system(size: 13, weight: .medium))

            Spacer()

            Button {
                editingTimeRange = range
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 11))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .buttonStyle(.plain)
            
            Button {
                preset.timeRanges.removeAll { $0.id == range.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
    
    private func addTimeRange(_ range: TimeRangeConfig) {
        // Avoid duplicates
        if !preset.timeRanges.contains(where: { $0.startHour == range.startHour && $0.endHour == range.endHour }) {
            preset.timeRanges.append(range)
        }
    }
    
    // MARK: - Weekday Section
    
    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("DAYS OF WEEK")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1)
                
                Spacer()
                
                Menu {
                    Button("All Days") {
                        preset.selectedWeekdays = WeekdaySelection.all
                    }
                    Button("Weekdays Only") {
                        preset.selectedWeekdays = WeekdaySelection.weekdays
                    }
                    Button("Weekends Only") {
                        preset.selectedWeekdays = WeekdaySelection.weekends
                    }
                } label: {
                    Text("Quick Select")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.accent)
                }
            }
            
            HStack(spacing: 6) {
                ForEach([0, 1, 2, 3, 4, 5, 6], id: \.self) { day in
                    weekdayButton(day)
                }
            }
        }
    }
    
    private func weekdayButton(_ day: Int) -> some View {
        let isSelected = preset.selectedWeekdays.contains(day)
        
        return Button {
            if isSelected {
                preset.selectedWeekdays.remove(day)
            } else {
                preset.selectedWeekdays.insert(day)
            }
        } label: {
            Text(WeekdaySelection.singleLetter(for: day))
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 36, height: 36)
                .foregroundColor(isSelected ? .white : BrutalTheme.textSecondary)
                .background(
                    Circle()
                        .fill(isSelected ? BrutalTheme.accent : Color(NSColor.controlBackgroundColor))
                )
        }
        .buttonStyle(.plain)
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SESSION DURATION")
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1)
            
            HStack(spacing: 16) {
                // Min duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Minimum")
                        .font(.system(size: 11))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    DurationPicker(
                        seconds: Binding(
                            get: { preset.minDurationSeconds ?? 0 },
                            set: { preset.minDurationSeconds = $0 > 0 ? $0 : nil }
                        ),
                        placeholder: "No min"
                    )
                }
                
                // Max duration
                VStack(alignment: .leading, spacing: 4) {
                    Text("Maximum")
                        .font(.system(size: 11))
                        .foregroundColor(BrutalTheme.textTertiary)
                    
                    DurationPicker(
                        seconds: Binding(
                            get: { preset.maxDurationSeconds ?? 0 },
                            set: { preset.maxDurationSeconds = $0 > 0 ? $0 : nil }
                        ),
                        placeholder: "No max"
                    )
                }
                
                Spacer()
            }
            
            // Quick presets
            HStack(spacing: 8) {
                Button("30+ min") {
                    preset.minDurationSeconds = 30 * 60
                    preset.maxDurationSeconds = nil
                }
                .buttonStyle(QuickDurationButtonStyle())
                
                Button("< 5 min") {
                    preset.minDurationSeconds = nil
                    preset.maxDurationSeconds = 5 * 60
                }
                .buttonStyle(QuickDurationButtonStyle())
                
                Button("5-30 min") {
                    preset.minDurationSeconds = 5 * 60
                    preset.maxDurationSeconds = 30 * 60
                }
                .buttonStyle(QuickDurationButtonStyle())
                
                if preset.minDurationSeconds != nil || preset.maxDurationSeconds != nil {
                    Button("Clear") {
                        preset.minDurationSeconds = nil
                        preset.maxDurationSeconds = nil
                    }
                    .buttonStyle(QuickDurationButtonStyle())
                }
            }
        }
    }
    
    // MARK: - Footer
    
    private var footer: some View {
        HStack {
            // Preview of filters
            if preset.hasFilters {
                Text(verbatim: preset.filterSummary)
                    .font(.system(size: 11))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            Button("Cancel") {
                onCancel()
            }
            .keyboardShortcut(.escape)
            
            Button("Save") {
                onSave()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(preset.name.isEmpty)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

// MARK: - Duration Picker

struct DurationPicker: View {
    @Binding var seconds: Double
    let placeholder: String
    
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    
    var body: some View {
        HStack(spacing: 4) {
            Picker("Hours", selection: $hours) {
                Text(LocalizedStringKey(placeholder)).tag(0)
                ForEach(1..<24, id: \.self) { h in
                    Text("\(h)h").tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 70)
            .onChange(of: hours) { _, _ in updateSeconds() }
            
            Picker("Minutes", selection: $minutes) {
                Text("0m").tag(0)
                ForEach([5, 10, 15, 30, 45], id: \.self) { m in
                    Text("\(m)m").tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)
            .onChange(of: minutes) { _, _ in updateSeconds() }
        }
        .onAppear {
            hours = Int(seconds / 3600)
            minutes = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        }
    }
    
    private func updateSeconds() {
        seconds = Double(hours * 3600 + minutes * 60)
    }
}

// MARK: - Quick Duration Button Style

struct QuickDurationButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(BrutalTheme.textSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(NSColor.controlBackgroundColor))
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

// MARK: - App Picker Sheet

struct AppPickerSheet: View {
    @Binding var selectedApps: Set<String>
    let availableApps: [String]
    @State private var searchText = ""
    @Environment(\.dismiss) private var dismiss
    
    var filteredApps: [String] {
        if searchText.isEmpty {
            return availableApps.sorted()
        }
        return availableApps.filter { $0.localizedCaseInsensitiveContains(searchText) }.sorted()
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Select Apps")
                    .font(.system(size: 16, weight: .semibold))
                
                Spacer()
                
                Text("\(selectedApps.count) selected")
                    .font(.system(size: 12))
                    .foregroundColor(BrutalTheme.textSecondary)
            }
            .padding()
            
            // Search
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(BrutalTheme.textTertiary)
                TextField("Search apps...", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(10)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
            
            Divider()
                .padding(.top, 12)
            
            // App list
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredApps, id: \.self) { app in
                        appRow(app)
                    }
                }
            }
            
            Divider()
            
            // Footer
            HStack {
                Button("Select All") {
                    selectedApps = Set(filteredApps)
                }
                
                Button("Clear All") {
                    selectedApps.removeAll()
                }
                
                Spacer()
                
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 400, height: 500)
    }
    
    private func appRow(_ app: String) -> some View {
        let isSelected = selectedApps.contains(app)
        
        return Button {
            if isSelected {
                selectedApps.remove(app)
            } else {
                selectedApps.insert(app)
            }
        } label: {
            HStack {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16))
                    .foregroundColor(isSelected ? BrutalTheme.accent : BrutalTheme.textTertiary)
                
                Text(verbatim: app)
                    .font(.system(size: 13))
                    .foregroundColor(BrutalTheme.textPrimary)
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(isSelected ? BrutalTheme.accent.opacity(0.1) : Color.clear)
    }
}

// MARK: - Time Range Editor Sheet

struct TimeRangeEditorSheet: View {
    @State var range: TimeRangeConfig
    let onSave: (TimeRangeConfig) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Custom Time Range")
                .font(.system(size: 16, weight: .semibold))
            
            TextField("Name (optional)", text: $range.name)
                .textFieldStyle(.roundedBorder)
            
            HStack(spacing: 20) {
                VStack(alignment: .leading) {
                    Text("Start")
                        .font(.system(size: 12))
                        .foregroundColor(BrutalTheme.textSecondary)
                    
                    Picker("Start Hour", selection: $range.startHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(verbatim: formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
                
                VStack(alignment: .leading) {
                    Text("End")
                        .font(.system(size: 12))
                        .foregroundColor(BrutalTheme.textSecondary)
                    
                    Picker("End Hour", selection: $range.endHour) {
                        ForEach(0..<24, id: \.self) { hour in
                            Text(verbatim: formatHour(hour)).tag(hour)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 100)
                }
            }
            
            // Visual preview
            HStack(spacing: 2) {
                ForEach(0..<24, id: \.self) { hour in
                    Rectangle()
                        .fill(range.contains(hour: hour) ? BrutalTheme.accent : Color(NSColor.controlBackgroundColor))
                        .frame(height: 20)
                }
            }
            .cornerRadius(4)
            
            Text(verbatim: range.displayName)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(BrutalTheme.textSecondary)
            
            Spacer()
            
            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") { onSave(range) }
                    .keyboardShortcut(.return)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 350, height: 300)
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }
}
