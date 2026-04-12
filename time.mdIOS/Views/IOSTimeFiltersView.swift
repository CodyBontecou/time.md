import SwiftUI

/// iOS-optimized time and data filter view
struct IOSTimeFiltersView: View {
    @ObservedObject var filterStore: IOSFilterStore
    @Environment(\.dismiss) private var dismiss
    
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    var body: some View {
        NavigationStack {
            List {
                // Date Range Section
                dateRangeSection
                
                // Time Slot Presets
                timeSlotPresetsSection
                
                // Custom Time Ranges
                customTimeRangesSection
                
                // Weekday Filter
                weekdaySection
                
                // Duration Filter
                durationSection
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if filterStore.hasActiveFilters {
                        Button("Clear") {
                            withAnimation {
                                filterStore.clearAllFilters()
                            }
                        }
                        .foregroundStyle(.red)
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
    
    // MARK: - Date Range Section
    
    private var dateRangeSection: some View {
        Section {
            // Granularity picker
            VStack(alignment: .leading, spacing: 12) {
                Text("Time Period")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                
                Picker("Period", selection: $filterStore.granularity) {
                    ForEach(TimeGranularity.allCases) { granularity in
                        Text(granularity.title).tag(granularity)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)
            
            // Date navigation
            HStack {
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        filterStore.goToPreviousPeriod()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                
                Spacer()
                
                VStack(spacing: 2) {
                    Text(LocalizedStringKey(filterStore.dateRangeLabel))
                        .font(.headline)

                    if !filterStore.isCurrentPeriod {
                        Button("Jump to Now") {
                            withAnimation(.spring(response: 0.3)) {
                                filterStore.goToCurrentPeriod()
                            }
                        }
                        .font(.caption)
                    }
                }
                
                Spacer()
                
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        filterStore.goToNextPeriod()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundStyle(filterStore.isCurrentPeriod ? Color(.tertiaryLabel) : Color.accentColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(filterStore.isCurrentPeriod)
            }
            .padding(.vertical, 8)
        } header: {
            Text("Date Range")
        }
    }
    
    // MARK: - Time Slot Presets
    
    private var timeSlotPresetsSection: some View {
        Section {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(TimeSlotPreset.allCases) { preset in
                    TimeSlotButton(
                        preset: preset,
                        isSelected: filterStore.selectedTimeSlot == preset,
                        action: {
                            withAnimation(.spring(response: 0.25)) {
                                if filterStore.selectedTimeSlot == preset {
                                    filterStore.selectedTimeSlot = nil
                                    filterStore.timeOfDayRanges.removeAll()
                                } else {
                                    filterStore.selectedTimeSlot = preset
                                }
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
        } header: {
            Text("Time of Day")
        } footer: {
            Text("Filter data to specific times of day")
        }
    }
    
    // MARK: - Custom Time Ranges
    
    private var customTimeRangesSection: some View {
        Section {
            if filterStore.selectedTimeSlot == nil {
                ForEach(Array(filterStore.timeOfDayRanges.enumerated()), id: \.element.id) { index, range in
                    CustomTimeRangeRow(
                        range: range,
                        onUpdate: { updatedRange in
                            filterStore.timeOfDayRanges[index] = updatedRange
                        },
                        onDelete: {
                            withAnimation {
                                filterStore.removeTimeRange(at: index)
                            }
                        }
                    )
                }
                
                Button {
                    withAnimation {
                        filterStore.addTimeRange(TimeOfDayRange(startHour: 9, endHour: 17))
                    }
                } label: {
                    Label("Add Custom Range", systemImage: "plus.circle.fill")
                }
            } else {
                HStack {
                    Image(systemName: filterStore.selectedTimeSlot!.icon)
                        .foregroundStyle(Color.accentColor)
                    
                    Text("Using \(filterStore.selectedTimeSlot!.name) preset")
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text(filterStore.selectedTimeSlot!.timeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                Button("Customize") {
                    withAnimation {
                        filterStore.selectedTimeSlot = nil
                    }
                }
                .font(.subheadline)
            }
        } header: {
            Text("Custom Time Ranges")
        }
    }
    
    // MARK: - Weekday Section
    
    private var weekdaySection: some View {
        Section {
            // Weekday pills
            HStack(spacing: 8) {
                ForEach(0..<7, id: \.self) { day in
                    WeekdayPill(
                        name: weekdayNames[day],
                        isSelected: filterStore.selectedWeekdays.contains(day),
                        isEmpty: filterStore.selectedWeekdays.isEmpty,
                        action: {
                            withAnimation(.spring(response: 0.2)) {
                                filterStore.toggleWeekday(day)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
            
            // Quick presets
            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        filterStore.applyWeekdaysPreset()
                    }
                } label: {
                    Text("Weekdays")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            filterStore.selectedWeekdays == Set([1, 2, 3, 4, 5])
                            ? Color.accentColor
                            : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            filterStore.selectedWeekdays == Set([1, 2, 3, 4, 5])
                            ? .white
                            : .primary
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                Button {
                    withAnimation(.spring(response: 0.25)) {
                        filterStore.applyWeekendPreset()
                    }
                } label: {
                    Text("Weekend")
                        .font(.subheadline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            filterStore.selectedWeekdays == Set([0, 6])
                            ? Color.accentColor
                            : Color(.systemGray5)
                        )
                        .foregroundStyle(
                            filterStore.selectedWeekdays == Set([0, 6])
                            ? .white
                            : .primary
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                
                if !filterStore.selectedWeekdays.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.25)) {
                            filterStore.selectedWeekdays.removeAll()
                        }
                    } label: {
                        Text("All")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
        } header: {
            Text("Days of Week")
        } footer: {
            if filterStore.selectedWeekdays.isEmpty {
                Text("All days included")
            } else {
                Text("\(filterStore.selectedWeekdays.count) day\(filterStore.selectedWeekdays.count == 1 ? "" : "s") selected")
            }
        }
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        Section {
            // Duration preset buttons
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(DurationPreset.allCases, id: \.name) { preset in
                    DurationPresetButton(
                        preset: preset,
                        isSelected: isDurationPresetSelected(preset),
                        action: {
                            withAnimation(.spring(response: 0.2)) {
                                applyDurationPreset(preset)
                            }
                        }
                    )
                }
            }
            .padding(.vertical, 8)
            
            // Current filter display
            if filterStore.minDurationSeconds != nil || filterStore.maxDurationSeconds != nil {
                HStack {
                    Image(systemName: "timer")
                        .foregroundStyle(.tint)
                    
                    Text(LocalizedStringKey(durationFilterLabel))
                        .font(.subheadline)
                    
                    Spacer()
                    
                    Button("Clear") {
                        withAnimation {
                            filterStore.minDurationSeconds = nil
                            filterStore.maxDurationSeconds = nil
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.red)
                }
            }
        } header: {
            Text("Session Duration")
        } footer: {
            Text("Filter by how long each session lasted")
        }
    }
    
    // MARK: - Helpers
    
    private func isDurationPresetSelected(_ preset: DurationPreset) -> Bool {
        preset.minSeconds == filterStore.minDurationSeconds &&
        preset.maxSeconds == filterStore.maxDurationSeconds
    }
    
    private func applyDurationPreset(_ preset: DurationPreset) {
        filterStore.minDurationSeconds = preset.minSeconds
        filterStore.maxDurationSeconds = preset.maxSeconds
    }
    
    private var durationFilterLabel: String {
        var parts: [String] = []
        if let min = filterStore.minDurationSeconds {
            parts.append("≥ \(formatDuration(min))")
        }
        if let max = filterStore.maxDurationSeconds {
            parts.append("≤ \(formatDuration(max))")
        }
        return parts.joined(separator: " and ")
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        if seconds < 60 {
            return "\(Int(seconds))s"
        } else if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        } else {
            return "\(Int(seconds / 3600))h"
        }
    }
}

// MARK: - Supporting Views

struct TimeSlotButton: View {
    let preset: TimeSlotPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: preset.icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? Color.white : Color.accentColor)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    
                    Text(verbatim: preset.timeLabel)
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.8) : .secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct WeekdayPill: View {
    let name: String
    let isSelected: Bool
    let isEmpty: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(LocalizedStringKey(name))
                .font(.caption)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : (isEmpty ? Color.accentColor.opacity(0.15) : Color(.systemGray6)))
                )
                .foregroundStyle(isSelected ? .white : (isEmpty ? .primary : .secondary))
        }
        .buttonStyle(.plain)
    }
}

struct DurationPresetButton: View {
    let preset: DurationPreset
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(preset.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isSelected ? Color.accentColor : Color(.systemGray6))
                )
                .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct CustomTimeRangeRow: View {
    let range: TimeOfDayRange
    let onUpdate: (TimeOfDayRange) -> Void
    let onDelete: () -> Void
    
    var body: some View {
        HStack {
            // Start hour picker
            Picker("From", selection: Binding(
                get: { range.startHour },
                set: { onUpdate(TimeOfDayRange(startHour: $0, endHour: range.endHour)) }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(verbatim: formatHour(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            
            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // End hour picker
            Picker("To", selection: Binding(
                get: { range.endHour },
                set: { onUpdate(TimeOfDayRange(startHour: range.startHour, endHour: $0)) }
            )) {
                ForEach(0..<24, id: \.self) { hour in
                    Text(verbatim: formatHour(hour)).tag(hour)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 90)
            
            Spacer()
            
            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
    }
}

// MARK: - Filter Badge (for compact display)

struct IOSFilterBadge: View {
    @ObservedObject var filterStore: IOSFilterStore
    @State private var showFilters = false
    
    var body: some View {
        Button {
            showFilters = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.subheadline)
                
                if let label = filterStore.activeFiltersLabel {
                    Text(LocalizedStringKey(label))
                        .font(.caption)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(filterStore.hasActiveFilters ? Color.accentColor : Color(.systemGray5))
            )
            .foregroundStyle(filterStore.hasActiveFilters ? .white : .primary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showFilters) {
            IOSTimeFiltersView(filterStore: filterStore)
        }
    }
}

// MARK: - Compact Date Navigator

struct IOSDateNavigator: View {
    @ObservedObject var filterStore: IOSFilterStore
    
    var body: some View {
        HStack(spacing: 0) {
            // Previous button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    filterStore.goToPreviousPeriod()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Granularity selector
            Menu {
                ForEach(TimeGranularity.allCases) { granularity in
                    Button {
                        filterStore.granularity = granularity
                    } label: {
                        HStack {
                            Text(granularity.title)
                            if filterStore.granularity == granularity {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(LocalizedStringKey(filterStore.dateRangeLabel))
                        .font(.headline)

                    Image(systemName: "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6), in: Capsule())
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Next button
            Button {
                withAnimation(.spring(response: 0.3)) {
                    filterStore.goToNextPeriod()
                }
            } label: {
                Image(systemName: "chevron.right")
                    .font(.headline)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .disabled(filterStore.isCurrentPeriod)
            .opacity(filterStore.isCurrentPeriod ? 0.3 : 1)
        }
    }
}

#Preview {
    IOSTimeFiltersView(filterStore: IOSFilterStore())
}
