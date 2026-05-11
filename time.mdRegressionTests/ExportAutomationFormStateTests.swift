import XCTest
@testable import time_md

@MainActor
final class ExportAutomationFormStateTests: XCTestCase {
    func testHydratingFromSchedulePreservesCustomSectionSelectionAndFormat() {
        let scheduledSections = ExportSectionSelection(sections: [.summary, .webHistory, .topDomains])
        let schedule = ExportSchedule(
            frequency: .daily,
            hour: 22,
            minute: 15,
            format: .json,
            sections: scheduledSections,
            relativeDateRange: .last30Days
        )

        let state = ExportAutomationFormState(schedule: schedule)

        XCTAssertEqual(state.sectionSelection.sections, scheduledSections.sections)
        XCTAssertEqual(state.selectedFormat, .json)
        XCTAssertEqual(state.exportMode, .custom)
        XCTAssertEqual(state.scheduleHour, 22)
        XCTAssertEqual(state.scheduleMinute, 15)
        XCTAssertEqual(state.scheduleRange, .last30Days)
    }

    func testDefaultExportSelectionMatchesGeneralMode() {
        let state = ExportAutomationFormState()

        XCTAssertEqual(state.sectionSelection.sections, [.summary, .apps, .categories, .trends])
        XCTAssertEqual(state.exportMode, .general)
        XCTAssertEqual(ExportAutomationFormState.exportMode(for: state.sectionSelection), .general)
    }

    func testFullSelectionHydratesAsExtensiveModeWithoutDroppingSections() {
        let schedule = ExportSchedule(
            format: .obsidian,
            sections: .full,
            relativeDateRange: .last7Days
        )

        let state = ExportAutomationFormState(schedule: schedule)

        XCTAssertEqual(state.sectionSelection.sections, ExportSectionSelection.full.sections)
        XCTAssertEqual(state.selectedFormat, .obsidian)
        XCTAssertEqual(state.exportMode, .extensive)
    }
}
