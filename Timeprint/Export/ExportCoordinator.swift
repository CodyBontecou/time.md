import AppKit
import CoreGraphics
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable {
    case png
    case pdf
    case csv

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
    }
}

enum ExportError: LocalizedError {
    case unsupportedDestination
    case couldNotCreateOutputDirectory(path: String)
    case writeFailed(path: String, details: String)

    var errorDescription: String? {
        switch self {
        case .unsupportedDestination:
            return "This destination does not have exportable data yet."
        case let .couldNotCreateOutputDirectory(path):
            return "Could not create export directory at \(path)."
        case let .writeFailed(path, details):
            return "Failed to write export at \(path). \(details)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .unsupportedDestination:
            return "Choose Overview or Apps & Categories."
        case .couldNotCreateOutputDirectory:
            return "Check directory permissions, then try exporting again."
        case .writeFailed:
            return "Verify disk space and write permissions, then retry."
        }
    }
}

protocol ExportCoordinating: Sendable {
    func export(format: ExportFormat, from destination: NavigationDestination, filters: FilterSnapshot) async throws -> URL
}

struct ExportCoordinator: ExportCoordinating {
    private let dataService: any ScreenTimeDataServing
    private let outputDirectoryOverride: URL?

    init(dataService: any ScreenTimeDataServing = SQLiteScreenTimeDataService(), outputDirectoryOverride: URL? = nil) {
        self.dataService = dataService
        self.outputDirectoryOverride = outputDirectoryOverride
    }

    func export(format: ExportFormat, from destination: NavigationDestination, filters: FilterSnapshot) async throws -> URL {
        let report = try await buildReport(for: destination, filters: filters)
        let outputDirectory = try ensureOutputDirectory()
        let fileURL = outputDirectory
            .appendingPathComponent(exportBaseName(destination: destination, filters: filters))
            .appendingPathExtension(format.fileExtension)

        switch format {
        case .csv:
            try writeCSV(report: report, to: fileURL)
        case .png:
            try writePNG(report: report, to: fileURL)
        case .pdf:
            try writePDF(report: report, to: fileURL)
        }

        return fileURL
    }
}

private extension ExportCoordinator {
    struct ExportReport {
        let title: String
        let destination: NavigationDestination
        let generatedAt: Date
        let filterSummary: String
        let sections: [ExportSection]
    }

    struct ExportSection {
        let title: String
        let headers: [String]
        let rows: [[String]]
    }

    func buildReport(for destination: NavigationDestination, filters: FilterSnapshot) async throws -> ExportReport {
        let generatedAt = Date()
        let filterSummary = summary(for: filters)

        switch destination {
        case .overview:
            async let summaryValue = dataService.fetchDashboardSummary(filters: filters)
            async let trendValue = dataService.fetchTrend(filters: filters)

            let summary = try await summaryValue
            let trend = try await trendValue

            let summarySection = ExportSection(
                title: "Summary",
                headers: ["metric", "value"],
                rows: [
                    ["total_seconds", formatSeconds(summary.totalSeconds)],
                    ["average_daily_seconds", formatSeconds(summary.averageDailySeconds)],
                    ["focus_blocks", String(summary.focusBlocks)],
                    ["current_streak_days", String(summary.currentStreakDays)]
                ]
            )

            let trendSection = ExportSection(
                title: "Trend",
                headers: ["date", "total_seconds"],
                rows: trend.map { [isoDate($0.date), formatSeconds($0.totalSeconds)] }
            )

            return ExportReport(
                title: "Overview Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [summarySection, trendSection]
            )

        case .appsCategories:
            async let appsValue = dataService.fetchTopApps(filters: filters, limit: 200)
            async let categoriesValue = dataService.fetchTopCategories(filters: filters, limit: 200)

            let apps = try await appsValue
            let categories = try await categoriesValue

            return ExportReport(
                title: "Apps & Categories Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSection(
                        title: "Apps",
                        headers: ["app_name", "total_seconds", "session_count"],
                        rows: apps.map { [$0.appName, formatSeconds($0.totalSeconds), String($0.sessionCount)] }
                    ),
                    ExportSection(
                        title: "Categories",
                        headers: ["category", "total_seconds"],
                        rows: categories.map { [$0.category, formatSeconds($0.totalSeconds)] }
                    )
                ]
            )

        case .webHistory:
            throw ExportError.unsupportedDestination

        case .settings:
            throw ExportError.unsupportedDestination
        }
    }

    func ensureOutputDirectory() throws -> URL {
        if let outputDirectoryOverride {
            return try createDirectoryIfNeeded(outputDirectoryOverride)
        }

        let fileManager = FileManager.default
        let base = fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory

        let exportsDirectory = base.appendingPathComponent("Timeprint Exports", isDirectory: true)
        return try createDirectoryIfNeeded(exportsDirectory)
    }

    func createDirectoryIfNeeded(_ directory: URL) throws -> URL {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory
        } catch {
            throw ExportError.couldNotCreateOutputDirectory(path: directory.path)
        }
    }

    func exportBaseName(destination: NavigationDestination, filters: FilterSnapshot) -> String {
        let timestamp = exportTimestamp(Date())
        let range = "\(shortDate(filters.startDate))_to_\(shortDate(filters.endDate))"
        return "screentime-\(destination.rawValue)-\(range)-\(timestamp)"
    }

    func writeCSV(report: ExportReport, to fileURL: URL) throws {
        var lines: [String] = []
        lines.append("# Timeprint Export")
        lines.append("# Title: \(report.title)")
        lines.append("# Destination: \(report.destination.title)")
        lines.append("# Generated At: \(isoDateTime(report.generatedAt))")
        lines.append("# Filters: \(report.filterSummary)")

        for section in report.sections {
            lines.append("")
            lines.append("[\(section.title)]")
            lines.append(section.headers.map(csvEscape).joined(separator: ","))
            for row in section.rows {
                lines.append(row.map(csvEscape).joined(separator: ","))
            }
        }

        let content = lines.joined(separator: "\n") + "\n"

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }

    func writePNG(report: ExportReport, to fileURL: URL) throws {
        let width = 1800
        let height = 1200

        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw ExportError.writeFailed(path: fileURL.path, details: "Could not create bitmap context")
        }

        let graphicsContext = NSGraphicsContext(cgContext: bitmapContext, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        drawReport(report, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        NSGraphicsContext.restoreGraphicsState()

        guard let cgImage = bitmapContext.makeImage() else {
            throw ExportError.writeFailed(path: fileURL.path, details: "Could not create CGImage")
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
            throw ExportError.writeFailed(path: fileURL.path, details: "Could not encode PNG data")
        }

        do {
            try pngData.write(to: fileURL)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }

    func writePDF(report: ExportReport, to fileURL: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape points

        guard let context = CGContext(fileURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.writeFailed(path: fileURL.path, details: "Could not create PDF context")
        }

        context.beginPDFPage(nil)

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext

        drawReport(report, in: mediaBox)

        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage()
        context.closePDF()
    }

    func drawReport(_ report: ExportReport, in bounds: CGRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()

        let textColor = NSColor.labelColor
        let secondaryTextColor = NSColor.secondaryLabelColor

        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .bold),
            .foregroundColor: textColor
        ]

        let bodyAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
            .foregroundColor: textColor
        ]

        let secondaryAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: secondaryTextColor
        ]

        var cursorY = bounds.maxY - 48
        NSString(string: report.title).draw(at: CGPoint(x: 36, y: cursorY), withAttributes: titleAttributes)
        cursorY -= 28

        NSString(string: "Generated: \(isoDateTime(report.generatedAt))").draw(at: CGPoint(x: 36, y: cursorY), withAttributes: secondaryAttributes)
        cursorY -= 20
        NSString(string: "Filters: \(report.filterSummary)").draw(at: CGPoint(x: 36, y: cursorY), withAttributes: secondaryAttributes)
        cursorY -= 28

        let sectionLimit = 5
        let rowLimit = 18

        for section in report.sections.prefix(sectionLimit) {
            guard cursorY > 80 else { break }

            NSString(string: "[\(section.title)]").draw(at: CGPoint(x: 36, y: cursorY), withAttributes: bodyAttributes)
            cursorY -= 20

            let headerLine = section.headers.joined(separator: " | ")
            NSString(string: headerLine).draw(at: CGPoint(x: 52, y: cursorY), withAttributes: bodyAttributes)
            cursorY -= 18

            for row in section.rows.prefix(rowLimit) {
                guard cursorY > 60 else { break }
                let line = row.joined(separator: " | ")
                NSString(string: line).draw(at: CGPoint(x: 52, y: cursorY), withAttributes: bodyAttributes)
                cursorY -= 16
            }

            if section.rows.count > rowLimit {
                NSString(string: "… \(section.rows.count - rowLimit) more rows").draw(
                    at: CGPoint(x: 52, y: cursorY),
                    withAttributes: secondaryAttributes
                )
                cursorY -= 18
            }

            cursorY -= 12
        }
    }

    func summary(for filters: FilterSnapshot) -> String {
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

    func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    func isoDate(_ date: Date) -> String {
        shortDate(date)
    }

    func isoDateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZZ"
        return formatter.string(from: date)
    }

    func exportTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    func formatSeconds(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    func csvEscape(_ value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}
