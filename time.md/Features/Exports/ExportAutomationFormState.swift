import Foundation

/// Testable presentation state for the export screen's automation controls.
///
/// Keeps the schedule hydration rules in one place so a saved auto-export
/// selection is restored exactly instead of falling back to the General default.
struct ExportAutomationFormState: Equatable {
    static let generalSectionSelection = ExportSectionSelection(sections: [.summary, .apps, .categories, .trends])

    var selectedFormat: ExportFormat = .csv
    var sectionSelection: ExportSectionSelection = Self.generalSectionSelection
    var exportMode: ExportsView.ExportMode = .general
    var scheduleHour: Int = 8
    var scheduleMinute: Int = 0
    var scheduleRange: RelativeDateRange = .yesterday

    init(
        selectedFormat: ExportFormat = .csv,
        sectionSelection: ExportSectionSelection = Self.generalSectionSelection,
        exportMode: ExportsView.ExportMode? = nil,
        scheduleHour: Int = 8,
        scheduleMinute: Int = 0,
        scheduleRange: RelativeDateRange = .yesterday
    ) {
        self.selectedFormat = selectedFormat
        self.sectionSelection = sectionSelection
        self.exportMode = exportMode ?? Self.exportMode(for: sectionSelection)
        self.scheduleHour = scheduleHour
        self.scheduleMinute = scheduleMinute
        self.scheduleRange = scheduleRange
    }

    init(schedule: ExportSchedule) {
        self.init(
            selectedFormat: schedule.format,
            sectionSelection: schedule.sections,
            scheduleHour: schedule.hour,
            scheduleMinute: schedule.minute,
            scheduleRange: schedule.relativeDateRange
        )
    }

    static func exportMode(for selection: ExportSectionSelection) -> ExportsView.ExportMode {
        if selection.sections == Self.generalSectionSelection.sections {
            return .general
        }
        if selection.sections == ExportSectionSelection.full.sections {
            return .extensive
        }
        return .custom
    }
}
