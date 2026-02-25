import SwiftUI

/// A popover view for configuring advanced time filters
struct AdvancedTimeFiltersView: View {
    @Bindable var filters: GlobalFilterStore
    @Environment(\.dismiss) private var dismiss
    
    // Weekday names for display
    private let weekdayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    
    // Duration presets
    private let durationPresets: [(String, Double?)] = [
        ("Any", nil),
        ("30s+", 30),
        ("1m+", 60),
        ("5m+", 300),
        ("15m+", 900),
        ("30m+", 1800),
        ("1h+", 3600)
    ]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Text("Advanced Filters")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)
                
                Spacer()
                
                if filters.hasAdvancedFilters {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            filters.clearAdvancedFilters()
                        }
                    } label: {
                        Text("Clear All")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(BrutalTheme.danger)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            Divider().opacity(0.3)
            
            // Time of Day Ranges
            timeOfDaySection
            
            Divider().opacity(0.3)
            
            // Weekday Filter
            weekdaySection
            
            Divider().opacity(0.3)
            
            // Duration Filter
            durationSection
            
            Spacer()
            
            // Done button
            Button {
                dismiss()
            } label: {
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(BrutalTheme.accent)
        }
        .padding(20)
        .frame(width: 360, height: 520)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
        )
    }
    
    // MARK: - Time of Day Section
    
    private var timeOfDaySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Time of Day")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textSecondary)
                
                Spacer()
                
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        filters.timeOfDayRanges.append(TimeOfDayRange())
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add Range")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundColor(BrutalTheme.accent)
                }
                .buttonStyle(.plain)
            }
            
            if filters.timeOfDayRanges.isEmpty {
                Text("No time ranges set — showing all hours")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(Array(filters.timeOfDayRanges.enumerated()), id: \.element.id) { index, range in
                    timeRangeRow(index: index, range: range)
                }
            }
            
            // Quick presets
            HStack(spacing: 6) {
                quickTimePreset(label: "Morning", start: 6, end: 12)
                quickTimePreset(label: "Work", start: 9, end: 17)
                quickTimePreset(label: "Evening", start: 17, end: 22)
                quickTimePreset(label: "Night", start: 22, end: 6)
            }
        }
    }
    
    private func timeRangeRow(index: Int, range: TimeOfDayRange) -> some View {
        HStack(spacing: 8) {
            // Start hour picker
            hourPicker(label: "From", hour: Binding(
                get: { range.startHour },
                set: { newValue in
                    filters.timeOfDayRanges[index] = TimeOfDayRange(startHour: newValue, endHour: range.endHour)
                }
            ))
            
            Text("→")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(BrutalTheme.textTertiary)
            
            // End hour picker
            hourPicker(label: "To", hour: Binding(
                get: { range.endHour },
                set: { newValue in
                    filters.timeOfDayRanges[index] = TimeOfDayRange(startHour: range.startHour, endHour: newValue)
                }
            ))
            
            Spacer()
            
            // Delete button
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    _ = filters.timeOfDayRanges.remove(at: index)
                }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 14))
                    .foregroundColor(BrutalTheme.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background {
            RoundedRectangle(cornerRadius: 8)
                .fill(BrutalTheme.accent)
                .opacity(0.1)
        }
    }
    
    private func hourPicker(label: String, hour: Binding<Int>) -> some View {
        Picker(label, selection: hour) {
            ForEach(0..<24, id: \.self) { h in
                Text(formatHour(h))
                    .tag(h)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(width: 80)
    }
    
    private func quickTimePreset(label: String, start: Int, end: Int) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                // Clear existing and add preset
                filters.timeOfDayRanges = [TimeOfDayRange(startHour: start, endHour: end)]
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
    }
    
    // MARK: - Weekday Section
    
    private var weekdaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Days of Week")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textSecondary)
                
                Spacer()
                
                if !filters.weekdayFilter.isEmpty {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            filters.weekdayFilter.removeAll()
                        }
                    } label: {
                        Text("All Days")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            HStack(spacing: 6) {
                ForEach(0..<7, id: \.self) { day in
                    weekdayButton(day: day)
                }
            }
            
            // Quick presets
            HStack(spacing: 6) {
                weekdayPreset(label: "Weekdays", days: [1, 2, 3, 4, 5])
                weekdayPreset(label: "Weekend", days: [0, 6])
            }
        }
    }
    
    private func weekdayButton(day: Int) -> some View {
        let isSelected = filters.weekdayFilter.contains(day)
        let isEmpty = filters.weekdayFilter.isEmpty
        
        return Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                if isSelected {
                    filters.weekdayFilter.remove(day)
                } else {
                    filters.weekdayFilter.insert(day)
                }
            }
        } label: {
            Text(weekdayNames[day])
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .white : (isEmpty ? BrutalTheme.textSecondary : BrutalTheme.textTertiary))
                .frame(width: 36, height: 32)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? BrutalTheme.accent : (isEmpty ? BrutalTheme.accent.opacity(0.3) : .clear))
    }
    
    private func weekdayPreset(label: String, days: [Int]) -> some View {
        let isActive = Set(days) == filters.weekdayFilter
        
        return Button {
            withAnimation(.easeInOut(duration: 0.15)) {
                filters.weekdayFilter = Set(days)
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isActive ? .white : BrutalTheme.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(isActive ? BrutalTheme.accent : .clear)
    }
    
    // MARK: - Duration Section
    
    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Session Duration")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.textSecondary)
            
            // Minimum duration presets
            VStack(alignment: .leading, spacing: 6) {
                Text("Minimum")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                HStack(spacing: 6) {
                    ForEach(durationPresets, id: \.0) { preset in
                        durationPresetButton(label: preset.0, value: preset.1, isMin: true)
                    }
                }
            }
            
            // Maximum duration
            VStack(alignment: .leading, spacing: 6) {
                Text("Maximum")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(BrutalTheme.textTertiary)
                
                HStack(spacing: 6) {
                    maxDurationPresetButton(label: "Any", value: nil)
                    maxDurationPresetButton(label: "<1m", value: 60)
                    maxDurationPresetButton(label: "<5m", value: 300)
                    maxDurationPresetButton(label: "<15m", value: 900)
                    maxDurationPresetButton(label: "<1h", value: 3600)
                }
            }
            
            // Current filter display
            if filters.minDurationSeconds != nil || filters.maxDurationSeconds != nil {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.system(size: 10))
                    Text(durationFilterLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                }
                .foregroundColor(BrutalTheme.accent)
                .padding(.top, 4)
            }
        }
    }
    
    private func durationPresetButton(label: String, value: Double?, isMin: Bool) -> some View {
        let isSelected = filters.minDurationSeconds == value
        
        return Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                filters.minDurationSeconds = value
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .white : BrutalTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? BrutalTheme.accent : .clear)
    }
    
    private func maxDurationPresetButton(label: String, value: Double?) -> some View {
        let isSelected = filters.maxDurationSeconds == value
        
        return Button {
            withAnimation(.easeInOut(duration: 0.1)) {
                filters.maxDurationSeconds = value
            }
        } label: {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundColor(isSelected ? .white : BrutalTheme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? BrutalTheme.accent : .clear)
    }
    
    private var durationFilterLabel: String {
        var parts: [String] = []
        if let min = filters.minDurationSeconds {
            parts.append("≥ \(formatDuration(min))")
        }
        if let max = filters.maxDurationSeconds {
            parts.append("≤ \(formatDuration(max))")
        }
        return parts.joined(separator: " and ")
    }
    
    // MARK: - Helpers
    
    private func formatHour(_ hour: Int) -> String {
        let h12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
        let ampm = hour < 12 ? "AM" : "PM"
        return "\(h12) \(ampm)"
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

// MARK: - Compact Filter Badge

/// A compact badge showing active advanced filter count, with tap to open
struct AdvancedFiltersBadge: View {
    @Bindable var filters: GlobalFilterStore
    @State private var showFiltersPopover = false
    
    var body: some View {
        Button {
            showFiltersPopover.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 10, weight: .semibold))
                
                if filters.hasAdvancedFilters {
                    if let label = filters.advancedFiltersLabel {
                        Text(label)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                    }
                } else {
                    Text("Filters")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundColor(filters.hasAdvancedFilters ? .white : BrutalTheme.textTertiary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(filters.hasAdvancedFilters ? BrutalTheme.accent : BrutalTheme.accent.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showFiltersPopover, arrowEdge: .bottom) {
            AdvancedTimeFiltersView(filters: filters)
        }
    }
}
