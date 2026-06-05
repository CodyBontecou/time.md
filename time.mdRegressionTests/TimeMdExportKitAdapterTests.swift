import XCTest
@testable import time_md
import ExportKit
import ExportAutomationKit

@MainActor
final class TimeMdExportKitAdapterTests: XCTestCase {
    func testTimeMdRenderersProduceExpectedOutputPerFormat() throws {
        let record = makeCombinedRecord()
        let registry = try TimeMdExportKitAdapter.rendererRegistry()

        let csv = try registry.render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .csv).id).content
        XCTAssertTrue(csv.contains("# time.md Combined Export"))
        XCTAssertTrue(csv.contains("metric,value"))

        let json = try registry.render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .json).id).content
        let jsonData = try XCTUnwrap(json.data(using: .utf8))
        let jsonObject = try XCTUnwrap(JSONSerialization.jsonObject(with: jsonData) as? [String: Any])
        XCTAssertEqual(jsonObject["title"] as? String, "time.md Combined Export")

        let yaml = try registry.render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .yaml).id).content
        XCTAssertTrue(yaml.contains("metadata:"))
        XCTAssertTrue(yaml.contains("section_count: 1"))

        let markdown = try registry.render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .markdown).id).content
        XCTAssertTrue(markdown.contains("# 📊 time.md Data Export"))
        XCTAssertTrue(markdown.contains("| metric"))

        let obsidian = try registry.render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .obsidian).id).content
        XCTAssertTrue(obsidian.contains("type: screentime-export"))
        XCTAssertTrue(obsidian.contains("# 📊 time.md Data Export"))
    }

    func testPathPlanningRejectsTraversalAndAllowsNestedRelativePaths() throws {
        let record = makeCombinedRecord()
        let rendered = try TimeMdExportKitAdapter.rendererRegistry()
            .render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .csv).id)

        XCTAssertThrowsError(try TimeMdExportKitAdapter.planFile(
            record: record,
            format: .csv,
            baseFilename: "../escape",
            rendered: rendered
        )) { error in
            XCTAssertTrue(error is ExportPathTemplateError)
        }

        let planned = try TimeMdExportKitAdapter.planFile(
            record: record,
            format: .csv,
            baseFilename: "daily/summary",
            rendered: rendered
        )
        XCTAssertEqual(planned.relativePath, "daily/summary.csv")
    }

    func testDestinationWriterSupportsOverwriteAndAppendModes() throws {
        let record = makeCombinedRecord()
        let fileSystem = InMemoryExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = URL(fileURLWithPath: "/tmp/timemd-exportkit-tests", isDirectory: true)

        let firstURL = try TimeMdExportKitAdapter.write(
            record: record,
            format: .markdown,
            baseFilename: "summary",
            to: destination,
            mode: .overwrite,
            fileWriter: writer
        )
        let firstContent = try XCTUnwrap(fileSystem.files[firstURL.path])

        _ = try TimeMdExportKitAdapter.write(
            record: record,
            format: .markdown,
            baseFilename: "summary",
            to: destination,
            mode: .append,
            fileWriter: writer
        )

        let appended = try XCTUnwrap(fileSystem.files[firstURL.path])
        XCTAssertEqual(appended, firstContent + "\n\n" + firstContent)
    }

    func testPreviewBuilderPlansContentWithoutWriting() async throws {
        let record = makeCombinedRecord()
        let preview = try await TimeMdExportKitAdapter.buildPreview(
            record: record,
            format: .markdown,
            baseFilename: "preview-summary"
        )

        XCTAssertEqual(preview.records.count, 1)
        XCTAssertEqual(preview.records.first?.files.first?.relativePath, "preview-summary.md")
        XCTAssertTrue(preview.records.first?.files.first?.content.contains("time.md Data Export") == true)
        XCTAssertEqual(preview.totalRecordCount, 1)
        XCTAssertEqual(preview.renderedRecordCount, 1)
    }

    func testExportKitOrchestrationReportsPartialSuccessForAppRecords() async throws {
        let record = makeCombinedRecord()
        let fileSystem = InMemoryExportFileSystem()
        let writer = ExportFileWriter(fileSystem: fileSystem)
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/timemd-orchestration"))

        let orchestrator = ExportRunOrchestrator<String, TimeMdExportRecord>(
            dataSource: AnyExportRecordDataSource { input in
                if input == "missing" { return ExportFetchedRecord(record: nil) }
                if input == "bad" {
                    return ExportFetchedRecord(record: TimeMdExportRecord(
                        id: "bad",
                        title: record.title,
                        generatedAt: record.generatedAt,
                        filters: record.filters,
                        settings: record.settings,
                        payload: record.payload
                    ))
                }
                return ExportFetchedRecord(record: record)
            },
            writer: AnyExportRecordWriter { record, context in
                if record.exportRecordID == "bad" {
                    throw NSError(domain: "TimeMdExportKitAdapterTests", code: 1)
                }
                let rendered = try TimeMdExportKitAdapter.rendererRegistry()
                    .render(record: record, formatID: TimeMdExportKitAdapter.descriptor(for: .csv).id)
                let file = try TimeMdExportKitAdapter.planFile(
                    record: record,
                    format: .csv,
                    baseFilename: "\(record.exportRecordID)-summary",
                    rendered: rendered
                )
                guard let destination = context.destination else {
                    throw NSError(domain: "TimeMdExportKitAdapterTests", code: 2)
                }
                _ = try writer.write(file, to: destination, mode: .overwrite)
                return ExportRecordWriteSummary(filesWritten: 1)
            },
            failureMapper: { error in
                ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
            }
        )

        let success = await orchestrator.run(ExportRunRequest(
            recordInputs: ["ok"],
            formatIDs: [TimeMdExportKitAdapter.descriptor(for: .csv).id],
            destination: destination,
            recordReference: { ExportRecordReference(id: $0) }
        ))
        XCTAssertEqual(success.status, .fullSuccess)
        XCTAssertEqual(success.filesWritten, 1)

        let partial = await orchestrator.run(ExportRunRequest(
            recordInputs: ["ok", "missing", "bad"],
            formatIDs: [TimeMdExportKitAdapter.descriptor(for: .csv).id],
            destination: destination,
            recordReference: { ExportRecordReference(id: $0) }
        ))
        XCTAssertEqual(partial.status, .partialSuccess)
        XCTAssertEqual(partial.successCount, 1)
        XCTAssertEqual(partial.failedRecords.count, 2)
    }

    func testScheduledExportBridgesTimingToExportAutomationKit() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(year: 2026, month: 5, day: 18, hour: 7, minute: 30)
        let schedule = ExportSchedule(
            frequency: .daily,
            hour: 8,
            minute: 15,
            format: .json,
            sections: ExportSectionSelection(sections: [.summary]),
            relativeDateRange: .last7Days
        )

        let automationSchedule = try XCTUnwrap(schedule.automationSchedule)
        XCTAssertEqual(automationSchedule.frequency, .daily)
        XCTAssertEqual(automationSchedule.preferredHour, 8)
        XCTAssertEqual(automationSchedule.preferredMinute, 15)
        XCTAssertEqual(automationSchedule.lookbackDays, 7)

        XCTAssertEqual(schedule.nextRunDate(from: now, calendar: calendar), date(year: 2026, month: 5, day: 18, hour: 8, minute: 15))
        XCTAssertEqual(schedule.mostRecentFireDate(at: now, calendar: calendar), date(year: 2026, month: 5, day: 17, hour: 8, minute: 15))
        XCTAssertTrue(schedule.isDue(at: date(year: 2026, month: 5, day: 18, hour: 9), lastRun: nil))
    }

    func testNonDomainInvoiceSampleUsesExportKitGenerically() throws {
        let invoice = InvoiceRecord(id: "inv-001", issuedDate: date(year: 2026, month: 5, day: 18), customer: "Acme Labs", totalCents: 12_500)
        let descriptor = ExportFormatDescriptor(
            id: "invoice-markdown",
            displayName: "Invoice Markdown",
            fileExtension: "md",
            contentType: "text/markdown"
        )
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer<InvoiceRecord>(descriptor: descriptor) { invoice, _ in
                RenderedExport(
                    content: "# Invoice \(invoice.id)\nCustomer: \(invoice.customer)\nTotal: \(invoice.totalCents)",
                    contentType: descriptor.contentType
                )
            }
        ])
        let rendered = try registry.render(record: invoice, formatID: descriptor.id)
        let relativePath = try ExportPathTemplate(
            folderTemplate: "Invoices/{year}/{month}",
            filenameTemplate: "{recordID}",
            fileExtension: descriptor.fileExtension
        ).plannedRelativePath(
            variables: ExportPathVariables(date: invoice.exportDate, values: ["recordID": invoice.exportRecordID]),
            safetyPolicy: .rejectTraversalAndAbsolutePaths
        )
        let file = PlannedExportFile(
            id: "\(invoice.exportRecordID)-markdown",
            role: .aggregate(formatID: descriptor.id),
            relativePath: relativePath,
            content: rendered.content,
            format: descriptor,
            contentType: descriptor.contentType,
            displayName: descriptor.displayName
        )
        let fileSystem = InMemoryExportFileSystem()
        let destination = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/invoice-exportkit"))
        let result = try ExportFileWriter(fileSystem: fileSystem).write(file, to: destination, mode: .overwrite)

        XCTAssertEqual(result.relativePath, "Invoices/2026/05/inv-001.md")
        XCTAssertEqual(fileSystem.files[result.url.path], rendered.content)
    }
}

private extension TimeMdExportKitAdapterTests {
    func makeCombinedRecord() -> TimeMdExportRecord {
        let generatedAt = date(year: 2026, month: 5, day: 18, hour: 9)
        let filters = FilterSnapshot(
            startDate: date(year: 2026, month: 5, day: 17),
            endDate: date(year: 2026, month: 5, day: 18),
            granularity: .day
        )
        let report = ExportCoordinator.ExportReport(
            title: "Summary",
            destination: .overview,
            generatedAt: generatedAt,
            filterSummary: "date_range=2026-05-17..2026-05-18; granularity=day; apps=all; categories=all; heatmap=all",
            sections: [
                ExportCoordinator.ExportSectionData(
                    title: "Summary",
                    headers: ["metric", "value"],
                    rows: [
                        ["total_seconds", "3600.000"],
                        ["average_daily_seconds", "1800.000"],
                        ["focus_blocks", "2"]
                    ]
                )
            ]
        )
        return TimeMdExportRecord.combined(
            reports: [.summary: report],
            sections: [.summary],
            filters: filters,
            settings: ExportSettings(),
            generatedAt: generatedAt
        )
    }

    func date(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }
}

private struct InvoiceRecord: ExportRecord {
    let id: String
    let issuedDate: Date
    let customer: String
    let totalCents: Int

    var exportRecordID: String { id }
    var exportDate: Date { issuedDate }
}

private final class InMemoryExportFileSystem: ExportFileSystem {
    var files: [String: String] = [:]
    var directories: Set<String> = []

    func fileExists(at url: URL) -> Bool {
        files[url.path] != nil || directories.contains(url.path)
    }

    func createDirectory(at url: URL) throws {
        directories.insert(url.path)
    }

    func readString(at url: URL) throws -> String {
        guard let value = files[url.path] else {
            throw NSError(domain: "InMemoryExportFileSystem", code: 1)
        }
        return value
    }

    func writeString(_ value: String, to url: URL, atomically: Bool) throws {
        files[url.path] = value
    }
}
