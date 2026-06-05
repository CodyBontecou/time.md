import Foundation
import ExportKit

/// App-owned export payload that adapts time.md reports to ExportKit without
/// teaching the reusable package about screen-time sessions, sections, filters,
/// or user-facing copy.
struct TimeMdExportRecord: ExportRecord {
    enum Payload {
        case report(ExportCoordinator.ExportReport)
        case combined(reports: [ExportSection: ExportCoordinator.ExportReport], sections: [ExportSection])
    }

    let id: String
    let title: String
    let generatedAt: Date
    let filters: FilterSnapshot
    let settings: ExportSettings
    let payload: Payload

    nonisolated var exportRecordID: String { id }
    nonisolated var exportDate: Date { generatedAt }

    static func report(
        _ report: ExportCoordinator.ExportReport,
        filters: FilterSnapshot,
        settings: ExportSettings
    ) -> TimeMdExportRecord {
        TimeMdExportRecord(
            id: "report-\(report.destination.rawValue)-\(Self.stableDateID(report.generatedAt))",
            title: report.title,
            generatedAt: report.generatedAt,
            filters: filters,
            settings: settings,
            payload: .report(report)
        )
    }

    static func combined(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        filters: FilterSnapshot,
        settings: ExportSettings,
        generatedAt: Date = Date()
    ) -> TimeMdExportRecord {
        TimeMdExportRecord(
            id: "combined-\(Self.stableDateID(generatedAt))",
            title: "time.md Data Export",
            generatedAt: generatedAt,
            filters: filters,
            settings: settings,
            payload: .combined(reports: reports, sections: sections)
        )
    }

    private static func stableDateID(_ date: Date) -> String {
        String(Int(date.timeIntervalSince1970))
    }
}

/// Thin app adapter around ExportKit renderers, path planning, previews, writer,
/// and run orchestration. All time.md-specific report shape, filenames, and copy
/// stay in the app target.
enum TimeMdExportKitAdapter {
    static func descriptor(for format: ExportFormat) -> ExportFormatDescriptor {
        ExportFormatDescriptor(
            id: format.formatID,
            displayName: format.displayName,
            fileExtension: format.fileExtension,
            contentType: format.contentType,
            defaultSortKey: format.defaultSortKey
        )
    }

    static func rendererRegistry() throws -> ExportRendererRegistry<TimeMdExportRecord> {
        try ExportRendererRegistry(renderers: ExportFormat.allCases.map { format in
            AnyExportRenderer<TimeMdExportRecord>(descriptor: descriptor(for: format)) { record, _ in
                try TimeMdExportContentRenderer.render(record: record, format: format)
            }
        })
    }

    static func planFile(
        record: TimeMdExportRecord,
        format: ExportFormat,
        baseFilename: String,
        rendered: RenderedExport
    ) throws -> PlannedExportFile {
        let descriptor = descriptor(for: format)
        return try planFile(
            record: record,
            descriptor: descriptor,
            baseFilename: baseFilename,
            rendered: rendered
        )
    }

    static func planFile(
        record: TimeMdExportRecord,
        descriptor: ExportFormatDescriptor,
        baseFilename: String,
        rendered: RenderedExport
    ) throws -> PlannedExportFile {
        let template = ExportPathTemplate(
            filenameTemplate: "{filename}",
            fileExtension: descriptor.fileExtension
        )
        let relativePath = try template.plannedRelativePath(
            variables: ExportPathVariables(date: record.exportDate, values: [
                "filename": baseFilename,
                "format": descriptor.id
            ]),
            safetyPolicy: .rejectTraversalAndAbsolutePaths
        )

        return PlannedExportFile(
            id: "\(record.exportRecordID)-\(descriptor.id)",
            role: .aggregate(formatID: descriptor.id),
            relativePath: relativePath,
            content: rendered.content,
            format: descriptor,
            contentType: rendered.contentType,
            displayName: descriptor.displayName,
            estimatedByteCount: rendered.content.utf8.count
        )
    }

    static func plannedURL(
        outputDirectory: URL,
        relativePath: String
    ) throws -> URL {
        try ExportPathSafetyPolicy.rejectTraversalAndAbsolutePaths
            .appending(relativePath, to: outputDirectory, isDirectory: false)
    }

    static func write(
        record: TimeMdExportRecord,
        format: ExportFormat,
        baseFilename: String,
        to outputDirectory: URL,
        mode: ExportWriteMode = .overwrite,
        fileWriter: ExportFileWriter = ExportFileWriter(fileSystem: FileManagerExportFileSystem())
    ) throws -> URL {
        let registry = try rendererRegistry()
        let descriptor = descriptor(for: format)
        let rendered = try registry.render(record: record, formatID: descriptor.id)
        let plannedFile = try planFile(
            record: record,
            descriptor: descriptor,
            baseFilename: baseFilename,
            rendered: rendered
        )
        let destination = ExportDestination(rootURL: outputDirectory)
        let result = try fileWriter.write(plannedFile, to: destination, mode: mode)
        return result.url
    }

    static func runExport(
        record: TimeMdExportRecord,
        format: ExportFormat,
        baseFilename: String,
        to outputDirectory: URL,
        fileWriter: ExportFileWriter = ExportFileWriter(fileSystem: FileManagerExportFileSystem())
    ) async throws -> URL {
        let descriptor = descriptor(for: format)
        let destination = ExportDestination(rootURL: outputDirectory)
        let plannedRelativePath = try ExportPathTemplate(
            filenameTemplate: "{filename}",
            fileExtension: descriptor.fileExtension
        ).plannedRelativePath(
            variables: ExportPathVariables(date: record.exportDate, values: ["filename": baseFilename]),
            safetyPolicy: .rejectTraversalAndAbsolutePaths
        )
        let expectedURL = try plannedURL(outputDirectory: outputDirectory, relativePath: plannedRelativePath)

        let writer = AnyExportRecordWriter<TimeMdExportRecord> { record, context in
            guard let destination = context.destination else {
                throw ExportError.writeFailed(path: outputDirectory.path, details: "No ExportKit destination was provided.")
            }
            let selectedFormatID = context.formatIDs.first ?? descriptor.id
            let registry = try rendererRegistry()
            let selectedDescriptor = try registry.descriptors(for: [selectedFormatID]).first ?? descriptor
            let rendered = try registry.render(record: record, formatID: selectedDescriptor.id)
            let plannedFile = try planFile(
                record: record,
                descriptor: selectedDescriptor,
                baseFilename: baseFilename,
                rendered: rendered
            )
            let writeResults = try fileWriter.write(
                [plannedFile],
                to: destination,
                mode: context.writeMode
            )
            return ExportRecordWriteSummary(filesWritten: writeResults.count)
        }

        let orchestrator = ExportRunOrchestrator<String, TimeMdExportRecord>(
            dataSource: AnyExportRecordDataSource { _ in
                ExportFetchedRecord(record: record)
            },
            writer: writer,
            failureMapper: { error in
                ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
            }
        )

        let result = await orchestrator.run(ExportRunRequest(
            recordInputs: [record.exportRecordID],
            formatIDs: [descriptor.id],
            destination: destination,
            writeMode: .overwrite,
            recordReference: { _ in
                ExportRecordReference(
                    id: record.exportRecordID,
                    date: record.exportDate,
                    displayName: record.title
                )
            }
        ))

        guard result.successCount > 0 else {
            let details = result.primaryFailure?.errorDescription ?? "ExportKit run failed with status \(result.status.rawValue)."
            throw ExportError.writeFailed(path: expectedURL.path, details: details)
        }

        return expectedURL
    }

    static func buildPreview(
        record: TimeMdExportRecord,
        format: ExportFormat,
        baseFilename: String
    ) async throws -> ExportPreview {
        let registry = try rendererRegistry()
        let descriptor = descriptor(for: format)
        let request = ExportPreviewRequest(
            recordInputs: [record.exportRecordID],
            selectedFormatIDs: [descriptor.id],
            dataSource: AnyExportRecordDataSource { _ in
                ExportFetchedRecord(record: record)
            },
            rendererRegistry: registry,
            recordReference: { _ in
                ExportRecordReference(
                    id: record.exportRecordID,
                    date: record.exportDate,
                    displayName: record.title
                )
            },
            planAggregateFile: { record, descriptor, rendered in
                try planFile(
                    record: record,
                    descriptor: descriptor,
                    baseFilename: baseFilename,
                    rendered: rendered
                )
            }
        )
        return try await ExportPreviewBuilder<String, TimeMdExportRecord>().buildPreview(request)
    }
}

private enum TimeMdExportContentRenderer {
    static func render(record: TimeMdExportRecord, format: ExportFormat) throws -> RenderedExport {
        let content: String
        switch record.payload {
        case .report(let report):
            content = try renderReport(report, record: record, format: format)
        case .combined(let reports, let sections):
            content = try renderCombined(reports: reports, sections: sections, record: record, format: format)
        }
        return RenderedExport(content: content, contentType: TimeMdExportKitAdapter.descriptor(for: format).contentType)
    }

    // MARK: - Single-report renderers

    private static func renderReport(
        _ report: ExportCoordinator.ExportReport,
        record: TimeMdExportRecord,
        format: ExportFormat
    ) throws -> String {
        switch format {
        case .csv:
            return renderReportCSV(report, settings: record.settings)
        case .json:
            return try renderReportJSON(report, settings: record.settings)
        case .yaml:
            return renderReportYAML(report, record: record)
        case .markdown:
            return renderReportMarkdown(report, record: record)
        case .obsidian:
            return renderReportObsidian(report, record: record)
        }
    }

    private static func renderReportCSV(
        _ report: ExportCoordinator.ExportReport,
        settings: ExportSettings
    ) -> String {
        let csvOpts = settings.csvOptions
        let delimiter = csvOpts.delimiter.rawValue
        var lines: [String] = []

        if csvOpts.includeMetadataComments {
            lines.append("# time.md Export")
            lines.append("# Title: \(report.title)")
            lines.append("# Destination: \(report.destination.title)")
            lines.append("# Generated At: \(isoDateTime(report.generatedAt))")
            lines.append("# Filters: \(report.filterSummary)")
        }

        for section in report.sections {
            if csvOpts.includeMetadataComments {
                lines.append("")
                lines.append("[\(section.title)]")
            } else if !lines.isEmpty {
                lines.append("")
            }

            if csvOpts.includeHeader {
                lines.append(section.headers.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
            }

            for row in section.rows {
                lines.append(row.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderReportJSON(
        _ report: ExportCoordinator.ExportReport,
        settings: ExportSettings
    ) throws -> String {
        let jsonOpts = settings.jsonOptions
        var sectionsArray: [[String: Any]] = []

        for section in report.sections {
            var rows: [[String: Any]] = []
            for row in section.rows {
                var rowDict: [String: Any] = [:]
                for (index, header) in section.headers.enumerated() where index < row.count {
                    if let doubleValue = Double(row[index]) {
                        rowDict[header] = doubleValue
                    } else {
                        rowDict[header] = row[index]
                    }
                }
                rows.append(rowDict)
            }
            sectionsArray.append(["name": section.title, "data": rows])
        }

        let outputData: Any
        if jsonOpts.structure == .flat {
            if sectionsArray.count == 1, let data = sectionsArray[0]["data"] {
                outputData = data
            } else {
                outputData = sectionsArray.compactMap { $0["data"] }
            }
        } else {
            var jsonObject: [String: Any] = [:]
            if jsonOpts.includeMetadata {
                jsonObject["title"] = report.title
                jsonObject["destination"] = report.destination.rawValue
                jsonObject["generated_at"] = isoDateTime(report.generatedAt)
                jsonObject["filters"] = report.filterSummary
            }
            jsonObject["sections"] = sectionsArray
            outputData = jsonObject
        }

        return try jsonString(outputData, options: jsonOpts.writingOptions)
    }

    private static func renderReportYAML(
        _ report: ExportCoordinator.ExportReport,
        record: TimeMdExportRecord
    ) -> String {
        var lines: [String] = []
        lines.append("# \(report.title)")
        lines.append("")
        lines.append("metadata:")
        lines.append("  title: \"\(escapeYAMLString(report.title))\"")
        lines.append("  destination: \(report.destination.rawValue)")
        lines.append("  generated_at: \(isoDateTime(report.generatedAt))")
        lines.append("  date_range:")
        lines.append("    start: \(shortDate(record.filters.startDate))")
        lines.append("    end: \(shortDate(record.filters.endDate))")
        lines.append("  granularity: \(record.filters.granularity.rawValue)")
        lines.append("  filters: \"\(escapeYAMLString(report.filterSummary))\"")
        lines.append("")
        lines.append("sections:")
        for section in report.sections {
            lines.append("  - name: \"\(escapeYAMLString(section.title))\"")
            lines.append("    headers:")
            for header in section.headers {
                lines.append("      - \(header)")
            }
            lines.append("    data:")
            for row in section.rows {
                lines.append("      -")
                for (index, header) in section.headers.enumerated() where index < row.count {
                    if Double(row[index]) != nil {
                        lines.append("        \(header): \(row[index])")
                    } else {
                        lines.append("        \(header): \"\(escapeYAMLString(row[index]))\"")
                    }
                }
            }
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderReportMarkdown(
        _ report: ExportCoordinator.ExportReport,
        record: TimeMdExportRecord
    ) -> String {
        let mdOpts = record.settings.markdownOptions
        var lines: [String] = []
        lines.append(formatHeading(report.title, level: 1, style: mdOpts.headingStyle))
        lines.append("")

        if mdOpts.includeMetadataHeader {
            let emoji = mdOpts.includeEmoji ? "📊 " : ""
            lines.append("\(emoji)**Generated:** \(isoDateTime(report.generatedAt))")
            lines.append("\(emoji)**Date Range:** \(shortDate(record.filters.startDate)) → \(shortDate(record.filters.endDate))")
            lines.append("\(emoji)**Granularity:** \(record.filters.granularity.rawValue)")
            lines.append("")
            if mdOpts.includeHorizontalRules {
                lines.append("---")
                lines.append("")
            }
        }

        if mdOpts.includeTableOfContents && report.sections.count > 1 {
            lines.append(formatHeading("Table of Contents", level: 2, style: mdOpts.headingStyle))
            for section in report.sections {
                let anchor = section.title.lowercased().replacingOccurrences(of: " ", with: "-")
                lines.append("- [\(section.title)](#\(anchor))")
            }
            lines.append("")
            if mdOpts.includeHorizontalRules {
                lines.append("---")
                lines.append("")
            }
        }

        for (sectionIndex, section) in report.sections.enumerated() {
            lines.append(formatHeading(section.title, level: 2, style: mdOpts.headingStyle))
            lines.append("")
            lines.append(contentsOf: formatMarkdownTable(
                headers: section.headers,
                rows: section.rows,
                style: mdOpts.tableStyle,
                linkApps: mdOpts.linkAppsToNotes
            ))
            lines.append("")
            if mdOpts.includeHorizontalRules && sectionIndex < report.sections.count - 1 {
                lines.append("---")
                lines.append("")
            }
        }

        let footerEmoji = mdOpts.includeEmoji ? "⏱️ " : ""
        lines.append("")
        lines.append("*\(footerEmoji)Exported by [time.md](https://timemd.isolated.tech)*")
        return lines.joined(separator: "\n")
    }

    private static func renderReportObsidian(
        _ report: ExportCoordinator.ExportReport,
        record: TimeMdExportRecord
    ) -> String {
        let obsOpts = record.settings.obsidianOptions
        let mdOpts = record.settings.markdownOptions
        var lines: [String] = []
        var topApps: [String] = []
        var totalSeconds: Double = 0

        for section in report.sections {
            if section.title == "Apps" || section.title == "Top Apps" {
                topApps = section.rows.prefix(5).compactMap { $0.first }
            }
            if section.title == "Summary" {
                for row in section.rows where row.first == "total_seconds" {
                    totalSeconds = Double(row.last ?? "") ?? totalSeconds
                }
            }
        }

        if obsOpts.includeFrontmatter {
            lines.append(obsOpts.generateFrontmatter(
                title: report.title,
                date: report.generatedAt,
                totalSeconds: totalSeconds,
                topApps: topApps,
                filters: report.filterSummary
            ))
        }

        let titleEmoji = mdOpts.includeEmoji ? "📊 " : ""
        lines.append(formatHeading("\(titleEmoji)\(report.title)", level: 1, style: mdOpts.headingStyle))
        lines.append("")

        if mdOpts.includeMetadataHeader {
            let dateLink = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(report.generatedAt, format: obsOpts.dailyNoteFormat))]]" : isoDateTime(report.generatedAt)
            let rangeStart = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(record.filters.startDate, format: obsOpts.dailyNoteFormat))]]" : shortDate(record.filters.startDate)
            let rangeEnd = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(record.filters.endDate, format: obsOpts.dailyNoteFormat))]]" : shortDate(record.filters.endDate)
            lines.append("| Property | Value |")
            lines.append("|----------|-------|")
            lines.append("| **Generated** | \(dateLink) |")
            lines.append("| **Date Range** | \(rangeStart) → \(rangeEnd) |")
            lines.append("| **Granularity** | \(record.filters.granularity.rawValue) |")
            if totalSeconds > 0 {
                lines.append("| **Total Time** | \(String(format: "%.1f", totalSeconds / 3600)) hours |")
            }
            lines.append("")
            if obsOpts.includeTags {
                var tags = ["#timemd", "#screentime"]
                tags.append(contentsOf: obsOpts.customTags.map { "#\($0)" })
                lines.append(tags.joined(separator: " "))
                lines.append("")
            }
            lines.append("---")
            lines.append("")
        }

        if mdOpts.includeTableOfContents && report.sections.count > 1 {
            lines.append("> [!summary] Table of Contents")
            for section in report.sections {
                let anchor = section.title.lowercased().replacingOccurrences(of: " ", with: "-")
                lines.append("> - [\(section.title)](#\(anchor))")
            }
            lines.append("")
        }

        for section in report.sections {
            let sectionEmoji = sectionEmoji(for: section.title, includeEmoji: mdOpts.includeEmoji)
            lines.append(formatHeading("\(sectionEmoji)\(section.title)", level: 2, style: mdOpts.headingStyle))
            lines.append("")
            let shouldLinkApps = obsOpts.includeWikiLinks &&
                (section.title == "Apps" || section.title == "Top Apps" || section.title == "Raw Sessions")
            lines.append(contentsOf: formatMarkdownTable(
                headers: section.headers,
                rows: section.rows,
                style: mdOpts.tableStyle,
                linkApps: shouldLinkApps,
                appFolder: obsOpts.appNoteFolder
            ))
            lines.append("")
        }

        if obsOpts.createBacklinks {
            lines.append("---")
            lines.append("")
            lines.append(formatHeading("🔗 Related", level: 2, style: mdOpts.headingStyle))
            lines.append("")
            let dateLink = formatObsidianDate(report.generatedAt, format: obsOpts.dailyNoteFormat)
            lines.append("- Daily Note: [[\(dateLink)]]")
            if obsOpts.includeWikiLinks && !topApps.isEmpty {
                lines.append("- Top Apps:")
                for app in topApps.prefix(5) {
                    let appLink = obsOpts.appNoteFolder.isEmpty ? app : "\(obsOpts.appNoteFolder)/\(app)"
                    lines.append("  - [[\(appLink)|\(app)]]")
                }
            }
            lines.append("")
        }

        let footerEmoji = mdOpts.includeEmoji ? "⏱️ " : ""
        lines.append("*\(footerEmoji)Exported by [time.md](https://timemd.isolated.tech)*")
        return lines.joined(separator: "\n")
    }

    // MARK: - Combined renderers

    private static func renderCombined(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        record: TimeMdExportRecord,
        format: ExportFormat
    ) throws -> String {
        switch format {
        case .csv:
            return renderCombinedCSV(reports: reports, sections: sections, settings: record.settings, generatedAt: record.generatedAt)
        case .json:
            return try renderCombinedJSON(reports: reports, sections: sections, record: record)
        case .yaml:
            return renderCombinedYAML(reports: reports, sections: sections, record: record)
        case .markdown:
            return renderCombinedMarkdown(reports: reports, sections: sections, record: record)
        case .obsidian:
            return renderCombinedObsidian(reports: reports, sections: sections, record: record)
        }
    }

    private static func renderCombinedCSV(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        settings: ExportSettings,
        generatedAt: Date
    ) -> String {
        let csvOpts = settings.csvOptions
        let delimiter = csvOpts.delimiter.rawValue
        var lines: [String] = []

        if csvOpts.includeMetadataComments {
            lines.append("# time.md Combined Export")
            lines.append("# Sections: \(sections.map(\.displayName).joined(separator: ", "))")
            lines.append("# Generated At: \(isoDateTime(generatedAt))")
        }

        for section in sections {
            guard let report = reports[section] else { continue }
            if csvOpts.includeMetadataComments {
                lines.append("")
                lines.append("# ═══════════════════════════════════════")
                lines.append("# SECTION: \(section.displayName.uppercased())")
                lines.append("# ═══════════════════════════════════════")
            } else if !lines.isEmpty {
                lines.append("")
            }

            for sectionData in report.sections {
                if csvOpts.includeMetadataComments && report.sections.count > 1 {
                    lines.append("[\(sectionData.title)]")
                }
                if csvOpts.includeHeader {
                    lines.append(sectionData.headers.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
                }
                for row in sectionData.rows {
                    lines.append(row.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderCombinedJSON(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        record: TimeMdExportRecord
    ) throws -> String {
        let jsonOpts = record.settings.jsonOptions
        var sectionsData: [[String: Any]] = []

        for section in sections {
            guard let report = reports[section] else { continue }
            var sectionObject: [String: Any] = [
                "name": section.rawValue,
                "display_name": section.displayName
            ]
            var dataArrays: [[String: Any]] = []
            for sectionData in report.sections {
                var rows: [[String: Any]] = []
                for row in sectionData.rows {
                    var rowDict: [String: Any] = [:]
                    for (index, header) in sectionData.headers.enumerated() where index < row.count {
                        if let doubleValue = Double(row[index]) {
                            rowDict[header] = doubleValue
                        } else {
                            rowDict[header] = row[index]
                        }
                    }
                    rows.append(rowDict)
                }
                dataArrays.append(["title": sectionData.title, "data": rows])
            }
            sectionObject["data"] = dataArrays.count == 1 ? dataArrays[0]["data"] : dataArrays
            sectionsData.append(sectionObject)
        }

        let outputData: Any
        if jsonOpts.structure == .flat {
            outputData = sectionsData
        } else {
            var jsonObject: [String: Any] = [:]
            if jsonOpts.includeMetadata {
                jsonObject["title"] = "time.md Combined Export"
                jsonObject["generated_at"] = isoDateTime(record.generatedAt)
                jsonObject["section_count"] = sections.count
                jsonObject["filters"] = summary(for: record.filters)
            }
            jsonObject["sections"] = sectionsData
            outputData = jsonObject
        }

        return try jsonString(outputData, options: jsonOpts.writingOptions)
    }

    private static func renderCombinedYAML(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        record: TimeMdExportRecord
    ) -> String {
        var lines: [String] = []
        lines.append("# time.md Combined Export")
        lines.append("")
        lines.append("metadata:")
        lines.append("  title: time.md Combined Export")
        lines.append("  generated_at: \(isoDateTime(record.generatedAt))")
        lines.append("  date_range:")
        lines.append("    start: \(shortDate(record.filters.startDate))")
        lines.append("    end: \(shortDate(record.filters.endDate))")
        lines.append("  granularity: \(record.filters.granularity.rawValue)")
        lines.append("  section_count: \(sections.count)")
        lines.append("  filters: \"\(escapeYAMLString(summary(for: record.filters)))\"")
        lines.append("")
        lines.append("sections:")

        for section in sections {
            guard let report = reports[section] else { continue }
            lines.append("  - id: \(section.rawValue)")
            lines.append("    name: \"\(escapeYAMLString(section.displayName))\"")
            for reportSection in report.sections {
                lines.append("    headers:")
                for header in reportSection.headers {
                    lines.append("      - \(header)")
                }
                lines.append("    data:")
                for row in reportSection.rows {
                    lines.append("      -")
                    for (index, header) in reportSection.headers.enumerated() where index < row.count {
                        if Double(row[index]) != nil {
                            lines.append("        \(header): \(row[index])")
                        } else {
                            lines.append("        \(header): \"\(escapeYAMLString(row[index]))\"")
                        }
                    }
                }
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private static func renderCombinedMarkdown(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        record: TimeMdExportRecord
    ) -> String {
        let mdOpts = record.settings.markdownOptions
        var lines: [String] = []
        let titleEmoji = mdOpts.includeEmoji ? "📊 " : ""
        lines.append(formatHeading("\(titleEmoji)time.md Data Export", level: 1, style: mdOpts.headingStyle))
        lines.append("")

        if mdOpts.includeMetadataHeader {
            lines.append("**Generated:** \(isoDateTime(record.generatedAt))")
            lines.append("**Date Range:** \(shortDate(record.filters.startDate)) → \(shortDate(record.filters.endDate))")
            lines.append("**Sections:** \(sections.map(\.displayName).joined(separator: ", "))")
            lines.append("")
            if mdOpts.includeHorizontalRules {
                lines.append("---")
                lines.append("")
            }
        }

        if mdOpts.includeTableOfContents {
            lines.append(formatHeading("Table of Contents", level: 2, style: mdOpts.headingStyle))
            for section in sections {
                let anchor = section.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
                let emoji = sectionEmoji(for: section.displayName, includeEmoji: mdOpts.includeEmoji)
                lines.append("- [\(emoji)\(section.displayName)](#\(anchor))")
            }
            lines.append("")
            if mdOpts.includeHorizontalRules {
                lines.append("---")
                lines.append("")
            }
        }

        for section in sections {
            guard let report = reports[section] else { continue }
            let sectionEmoji = sectionEmoji(for: section.displayName, includeEmoji: mdOpts.includeEmoji)
            lines.append(formatHeading("\(sectionEmoji)\(section.displayName)", level: 2, style: mdOpts.headingStyle))
            lines.append("")
            for sectionData in report.sections {
                if report.sections.count > 1 {
                    lines.append(formatHeading(sectionData.title, level: 3, style: mdOpts.headingStyle))
                    lines.append("")
                }
                lines.append(contentsOf: formatMarkdownTable(
                    headers: sectionData.headers,
                    rows: sectionData.rows,
                    style: mdOpts.tableStyle,
                    linkApps: mdOpts.linkAppsToNotes
                ))
                lines.append("")
            }
            if mdOpts.includeHorizontalRules && section != sections.last {
                lines.append("---")
                lines.append("")
            }
        }

        let footerEmoji = mdOpts.includeEmoji ? "⏱️ " : ""
        lines.append("*\(footerEmoji)Exported by [time.md](https://timemd.isolated.tech)*")
        return lines.joined(separator: "\n")
    }

    private static func renderCombinedObsidian(
        reports: [ExportSection: ExportCoordinator.ExportReport],
        sections: [ExportSection],
        record: TimeMdExportRecord
    ) -> String {
        let obsOpts = record.settings.obsidianOptions
        let mdOpts = record.settings.markdownOptions
        var lines: [String] = []
        var totalSeconds: Double = 0
        var topApps: [String] = []

        for section in sections {
            guard let report = reports[section] else { continue }
            for sectionData in report.sections {
                if sectionData.title == "Summary" {
                    for row in sectionData.rows where row.first == "total_seconds" {
                        totalSeconds = Double(row.last ?? "") ?? totalSeconds
                    }
                }
                if sectionData.title == "Apps" || sectionData.title == "Top Apps" {
                    topApps = sectionData.rows.prefix(5).compactMap { $0.first }
                }
            }
        }

        if obsOpts.includeFrontmatter {
            lines.append(obsOpts.generateFrontmatter(
                title: "time.md Data Export",
                date: record.generatedAt,
                totalSeconds: totalSeconds,
                topApps: topApps,
                filters: summary(for: record.filters),
                additionalFields: [
                    "section_count": sections.count,
                    "export_type": "combined"
                ]
            ))
        }

        let titleEmoji = mdOpts.includeEmoji ? "📊 " : ""
        lines.append(formatHeading("\(titleEmoji)time.md Data Export", level: 1, style: mdOpts.headingStyle))
        lines.append("")

        if mdOpts.includeMetadataHeader {
            let dateLink = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(record.generatedAt, format: obsOpts.dailyNoteFormat))]]" : isoDateTime(record.generatedAt)
            let rangeStart = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(record.filters.startDate, format: obsOpts.dailyNoteFormat))]]" : shortDate(record.filters.startDate)
            let rangeEnd = obsOpts.includeWikiLinks ? "[[\(formatObsidianDate(record.filters.endDate, format: obsOpts.dailyNoteFormat))]]" : shortDate(record.filters.endDate)
            lines.append("| Property | Value |")
            lines.append("|----------|-------|")
            lines.append("| **Generated** | \(dateLink) |")
            lines.append("| **Date Range** | \(rangeStart) → \(rangeEnd) |")
            lines.append("| **Sections** | \(sections.count) |")
            if totalSeconds > 0 {
                lines.append("| **Total Time** | \(String(format: "%.1f", totalSeconds / 3600)) hours |")
            }
            lines.append("")
            if obsOpts.includeTags {
                var tags = ["#timemd", "#screentime", "#data-export"]
                tags.append(contentsOf: obsOpts.customTags.map { "#\($0)" })
                lines.append(tags.joined(separator: " "))
                lines.append("")
            }
            lines.append("---")
            lines.append("")
        }

        if mdOpts.includeTableOfContents {
            lines.append("> [!summary] Sections")
            for section in sections {
                let anchor = section.displayName.lowercased().replacingOccurrences(of: " ", with: "-")
                let emoji = sectionEmoji(for: section.displayName, includeEmoji: mdOpts.includeEmoji)
                lines.append("> - [\(emoji)\(section.displayName)](#\(anchor))")
            }
            lines.append("")
        }

        for section in sections {
            guard let report = reports[section] else { continue }
            let emoji = sectionEmoji(for: section.displayName, includeEmoji: mdOpts.includeEmoji)
            lines.append(formatHeading("\(emoji)\(section.displayName)", level: 2, style: mdOpts.headingStyle))
            lines.append("")
            for sectionData in report.sections {
                if report.sections.count > 1 {
                    lines.append(formatHeading(sectionData.title, level: 3, style: mdOpts.headingStyle))
                    lines.append("")
                }
                let shouldLinkApps = obsOpts.includeWikiLinks &&
                    (sectionData.title == "Apps" || sectionData.title == "Top Apps" || sectionData.title == "Raw Sessions")
                lines.append(contentsOf: formatMarkdownTable(
                    headers: sectionData.headers,
                    rows: sectionData.rows,
                    style: mdOpts.tableStyle,
                    linkApps: shouldLinkApps,
                    appFolder: obsOpts.appNoteFolder
                ))
                lines.append("")
            }
        }

        if obsOpts.createBacklinks && !topApps.isEmpty {
            lines.append("---")
            lines.append("")
            lines.append(formatHeading("🔗 Related", level: 2, style: mdOpts.headingStyle))
            lines.append("")
            lines.append("**Top Apps:**")
            for app in topApps.prefix(5) {
                let appLink = obsOpts.appNoteFolder.isEmpty ? app : "\(obsOpts.appNoteFolder)/\(app)"
                lines.append("- [[\(appLink)|\(app)]]")
            }
            lines.append("")
        }

        let footerEmoji = mdOpts.includeEmoji ? "⏱️ " : ""
        lines.append("*\(footerEmoji)Exported by [time.md](https://timemd.isolated.tech)*")
        return lines.joined(separator: "\n")
    }

    // MARK: - Shared formatting helpers

    private static func jsonString(_ object: Any, options: JSONSerialization.WritingOptions) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: options)
        guard let string = String(data: data, encoding: .utf8) else {
            throw ExportError.writeFailed(path: "", details: "JSON export was not valid UTF-8.")
        }
        return string
    }

    private static func summary(for filters: FilterSnapshot) -> String {
        let selectedApps = filters.selectedApps.isEmpty ? "all" : "\(filters.selectedApps.count) app(s)"
        let selectedCategories = filters.selectedCategories.isEmpty ? "all" : "\(filters.selectedCategories.count) category(s)"
        let selectedCells = filters.selectedHeatmapCells.isEmpty ? "all" : "\(filters.selectedHeatmapCells.count) heatmap cell(s)"
        return [
            "date_range=\(shortDate(filters.startDate))..\(shortDate(filters.endDate))",
            "granularity=\(filters.granularity.rawValue)",
            "apps=\(selectedApps)",
            "categories=\(selectedCategories)",
            "heatmap=\(selectedCells)"
        ].joined(separator: "; ")
    }

    private static func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func isoDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter.string(from: date)
    }

    private static func csvEscape(_ value: String, options: CSVExportOptions) -> String {
        options.escape(value)
    }

    private static func escapeYAMLString(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\t", with: "\\t")
    }

    private static func formatHeading(
        _ text: String,
        level: Int,
        style: MarkdownExportOptions.MarkdownHeadingStyle
    ) -> String {
        switch style {
        case .atx:
            return String(repeating: "#", count: level) + " " + text
        case .setext:
            if level == 1 {
                return "\(text)\n\(String(repeating: "=", count: text.count))"
            } else if level == 2 {
                return "\(text)\n\(String(repeating: "-", count: text.count))"
            }
            return String(repeating: "#", count: level) + " " + text
        }
    }

    private static func formatMarkdownTable(
        headers: [String],
        rows: [[String]],
        style: MarkdownExportOptions.MarkdownTableStyle,
        linkApps: Bool,
        appFolder: String = ""
    ) -> [String] {
        switch style {
        case .github:
            return formatGFMTable(headers: headers, rows: rows, linkApps: linkApps, appFolder: appFolder)
        case .simple:
            return formatSimpleTable(headers: headers, rows: rows, linkApps: linkApps, appFolder: appFolder)
        case .html:
            return formatHTMLTable(headers: headers, rows: rows, linkApps: linkApps, appFolder: appFolder)
        }
    }

    private static let maxTableColumnWidth = 200

    private static func displayRows(
        headers: [String],
        rows: [[String]],
        linkApps: Bool,
        appFolder: String,
        escapePipe: Bool
    ) -> [[String]] {
        let shouldLinkAppColumn = linkApps && headers.first?.lowercased().contains("app") == true
        return rows.map { row in
            row.enumerated().map { index, cell in
                if shouldLinkAppColumn && index == 0 {
                    let appLink = appFolder.isEmpty ? cell : "\(appFolder)/\(cell)"
                    let separator = escapePipe ? "\\|" : "|"
                    return "[[\(appLink)\(separator)\(cell)]]"
                }
                return cell
            }
        }
    }

    private static func tableWidths(headers: [String], displayRows: [[String]]) -> [Int] {
        var widths = headers.map { $0.count }
        for row in displayRows {
            for (index, cell) in row.enumerated() where index < widths.count {
                widths[index] = max(widths[index], cell.count)
            }
        }
        return widths.map { min($0, maxTableColumnWidth) }
    }

    private static func formatGFMTable(
        headers: [String],
        rows: [[String]],
        linkApps: Bool,
        appFolder: String
    ) -> [String] {
        let renderedRows = displayRows(headers: headers, rows: rows, linkApps: linkApps, appFolder: appFolder, escapePipe: true)
        let widths = tableWidths(headers: headers, displayRows: renderedRows)
        var lines: [String] = []
        lines.append("| " + zip(headers, widths).map { padCell($0, to: $1) }.joined(separator: " | ") + " |")
        lines.append("| " + widths.map { String(repeating: "-", count: $0) }.joined(separator: " | ") + " |")
        for row in renderedRows {
            let cells = row.enumerated().compactMap { index, cell in
                index < widths.count ? padCell(cell, to: widths[index]) : nil
            }
            lines.append("| " + cells.joined(separator: " | ") + " |")
        }
        return lines
    }

    private static func formatSimpleTable(
        headers: [String],
        rows: [[String]],
        linkApps: Bool,
        appFolder: String
    ) -> [String] {
        let renderedRows = displayRows(headers: headers, rows: rows, linkApps: linkApps, appFolder: appFolder, escapePipe: true)
        let widths = tableWidths(headers: headers, displayRows: renderedRows)
        var lines: [String] = []
        lines.append(zip(headers, widths).map { padCell($0, to: $1 + 2) }.joined())
        lines.append(widths.map { String(repeating: "-", count: $0 + 2) }.joined())
        for row in renderedRows {
            let cells = row.enumerated().compactMap { index, cell in
                index < widths.count ? padCell(cell, to: widths[index] + 2) : nil
            }
            lines.append(cells.joined())
        }
        return lines
    }

    private static func formatHTMLTable(
        headers: [String],
        rows: [[String]],
        linkApps: Bool,
        appFolder: String
    ) -> [String] {
        var lines: [String] = []
        lines.append("<table>")
        lines.append("  <thead>")
        lines.append("    <tr>")
        for header in headers {
            lines.append("      <th>\(escapeHTML(header))</th>")
        }
        lines.append("    </tr>")
        lines.append("  </thead>")
        lines.append("  <tbody>")
        let shouldLinkAppColumn = linkApps && headers.first?.lowercased().contains("app") == true
        for row in rows {
            lines.append("    <tr>")
            for (index, cell) in row.enumerated() {
                var displayCell = escapeHTML(cell)
                if shouldLinkAppColumn && index == 0 {
                    let appLink = appFolder.isEmpty ? cell : "\(appFolder)/\(cell)"
                    displayCell = "[[\(appLink)|\(cell)]]"
                }
                lines.append("      <td>\(displayCell)</td>")
            }
            lines.append("    </tr>")
        }
        lines.append("  </tbody>")
        lines.append("</table>")
        return lines
    }

    private static func padCell(_ cell: String, to width: Int) -> String {
        if cell.count >= width { return cell }
        return cell.padding(toLength: width, withPad: " ", startingAt: 0)
    }

    private static func escapeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func formatObsidianDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    private static func sectionEmoji(for title: String, includeEmoji: Bool) -> String {
        guard includeEmoji else { return "" }
        switch title.lowercased() {
        case "summary": return "📈 "
        case "apps", "top apps": return "📱 "
        case "categories": return "📁 "
        case "trends", "trend": return "📊 "
        case "sessions", "session distribution": return "⏱️ "
        case "heatmap": return "🔥 "
        case "raw sessions": return "📋 "
        case "context switches", "context switch rate": return "🔄 "
        case "app transitions": return "↔️ "
        case "period comparison": return "📆 "
        default: return "📄 "
        }
    }
}

private extension ExportFormat {
    var formatID: String { "timemd-\(rawValue)" }

    var contentType: String {
        switch self {
        case .csv: return "text/csv"
        case .json: return "application/json"
        case .yaml: return "application/x-yaml"
        case .markdown, .obsidian: return "text/markdown"
        }
    }

    var defaultSortKey: String {
        switch self {
        case .csv: return "10-csv"
        case .json: return "20-json"
        case .yaml: return "30-yaml"
        case .markdown: return "40-markdown"
        case .obsidian: return "50-obsidian"
        }
    }
}
