import AppKit
import CoreGraphics
import Foundation

enum ExportFormat: String, CaseIterable, Identifiable, Codable {
    case png
    case pdf
    case csv
    case json

    var id: String { rawValue }

    var displayName: String {
        rawValue.uppercased()
    }

    var fileExtension: String {
        rawValue
    }

    var systemImage: String {
        switch self {
        case .png: "photo"
        case .pdf: "doc.richtext"
        case .csv: "tablecells"
        case .json: "curlybraces"
        }
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
    func export(format: ExportFormat, from destination: NavigationDestination, filters: FilterSnapshot, settings: ExportSettings, progress: ExportProgress?) async throws -> URL
    func generateWeeklySummaryCard(filters: FilterSnapshot) async throws -> URL
    func copyStatsToClipboard(filters: FilterSnapshot) async throws -> String
    func estimateExport(from destination: NavigationDestination, filters: FilterSnapshot, format: ExportFormat) async throws -> ExportEstimate
    
    // Combined export methods
    func exportCombined(config: CombinedExportConfig, filters: FilterSnapshot, settings: ExportSettings, progress: ExportProgress?) async throws -> URL
    func estimateCombinedExport(sections: ExportSectionSelection, filters: FilterSnapshot, format: ExportFormat) async throws -> ExportEstimate
}

struct ExportCoordinator: ExportCoordinating {
    private let dataService: any ScreenTimeDataServing
    private let outputDirectoryOverride: URL?

    init(dataService: any ScreenTimeDataServing = SQLiteScreenTimeDataService(), outputDirectoryOverride: URL? = nil) {
        self.dataService = dataService
        self.outputDirectoryOverride = outputDirectoryOverride
    }

    func export(format: ExportFormat, from destination: NavigationDestination, filters: FilterSnapshot) async throws -> URL {
        try await export(format: format, from: destination, filters: filters, settings: ExportSettings.load(), progress: nil)
    }

    func export(format: ExportFormat, from destination: NavigationDestination, filters: FilterSnapshot, settings: ExportSettings, progress: ExportProgress?) async throws -> URL {
        // For raw sessions, use specialized export path
        if destination == .rawSessions {
            return try await exportRawSessions(format: format, filters: filters, settings: settings, progress: progress)
        }

        let report = try await buildReport(for: destination, filters: filters, settings: settings)
        let outputDirectory = try ensureOutputDirectory()
        let fileURL = outputDirectory
            .appendingPathComponent(exportBaseName(destination: destination, filters: filters))
            .appendingPathExtension(format.fileExtension)

        switch format {
        case .csv:
            try writeCSV(report: report, to: fileURL, settings: settings)
        case .png:
            try writePNG(report: report, to: fileURL)
        case .pdf:
            try writePDF(report: report, to: fileURL)
        case .json:
            try writeJSON(report: report, to: fileURL, settings: settings)
        }

        return fileURL
    }

    func estimateExport(from destination: NavigationDestination, filters: FilterSnapshot, format: ExportFormat) async throws -> ExportEstimate {
        let rowCount: Int

        switch destination {
        case .rawSessions:
            rowCount = try await dataService.fetchRawSessionCount(filters: filters)
        case .overview:
            // Summary + trend points
            let trend = try await dataService.fetchTrend(filters: filters)
            rowCount = 4 + trend.count  // 4 summary metrics + trend points
        case .appsCategories:
            let apps = try await dataService.fetchTopApps(filters: filters, limit: 200)
            let categories = try await dataService.fetchTopCategories(filters: filters, limit: 200)
            rowCount = apps.count + categories.count
        case .trends:
            let trend = try await dataService.fetchTrend(filters: filters)
            rowCount = trend.count
        case .sessions:
            let buckets = try await dataService.fetchSessionBuckets(filters: filters)
            rowCount = buckets.count
        case .heatmap:
            rowCount = 7 * 24  // Full heatmap grid
        case .calendar:
            let focusDays = try await dataService.fetchFocusDays(filters: filters)
            rowCount = focusDays.count
        case .webHistory, .exports, .settings:
            rowCount = 0
        }

        return ExportEstimate.estimate(rowCount: rowCount, format: format)
    }
    
    // MARK: - Combined Export
    
    func exportCombined(config: CombinedExportConfig, filters: FilterSnapshot, settings: ExportSettings, progress: ExportProgress?) async throws -> URL {
        guard !config.sections.isEmpty else {
            throw ExportError.unsupportedDestination
        }
        
        if let progress {
            await MainActor.run { progress.reset() }
        }
        
        // Build reports for all selected sections
        var reports: [ExportSection: ExportReport] = [:]
        let totalSections = config.sections.count
        
        for (index, section) in config.sections.sections.enumerated() {
            // Check for cancellation
            if let progress, await MainActor.run(body: { progress.isCancelled }) {
                throw CancellationError()
            }
            
            if let progress {
                await MainActor.run {
                    progress.update(current: index, total: totalSections)
                }
            }
            
            let report = try await buildSectionReport(section: section, filters: filters, settings: settings)
            reports[section] = report
        }
        
        // Generate output file
        let outputDirectory = try ensureOutputDirectory()
        let filename = config.generateFilename()
        let fileURL = outputDirectory
            .appendingPathComponent(filename)
            .appendingPathExtension(config.format.fileExtension)
        
        // Write combined output
        switch config.format {
        case .csv:
            try writeCombinedCSV(reports: reports, sections: config.sections.sections, to: fileURL, settings: settings)
        case .json:
            try writeCombinedJSON(reports: reports, sections: config.sections.sections, to: fileURL, settings: settings, filters: filters)
        case .pdf:
            try writeCombinedPDF(reports: reports, sections: config.sections.sections, to: fileURL)
        case .png:
            try writeCombinedPNG(reports: reports, sections: config.sections.sections, to: fileURL)
        }
        
        if let progress {
            await MainActor.run { progress.markComplete() }
        }
        
        return fileURL
    }
    
    func estimateCombinedExport(sections: ExportSectionSelection, filters: FilterSnapshot, format: ExportFormat) async throws -> ExportEstimate {
        var totalRows = 0
        
        for section in sections.sections {
            switch section {
            case .summary:
                totalRows += 4  // 4 summary metrics
            case .apps:
                let apps = try await dataService.fetchTopApps(filters: filters, limit: 200)
                totalRows += apps.count
            case .categories:
                let categories = try await dataService.fetchTopCategories(filters: filters, limit: 200)
                totalRows += categories.count
            case .trends:
                let trend = try await dataService.fetchTrend(filters: filters)
                totalRows += trend.count
            case .sessions:
                let buckets = try await dataService.fetchSessionBuckets(filters: filters)
                totalRows += buckets.count
            case .heatmap:
                totalRows += 7 * 24
            case .rawSessions:
                totalRows += try await dataService.fetchRawSessionCount(filters: filters)
                
            // Analytics sections
            case .contextSwitches:
                let switches = try await dataService.fetchContextSwitchRate(filters: filters)
                totalRows += switches.count
            case .appTransitions:
                let transitions = try await dataService.fetchAppTransitions(filters: filters, limit: 100)
                totalRows += transitions.count
            case .periodComparison:
                let comparison = try await dataService.fetchPeriodComparison(current: filters, previous: filters)
                totalRows += 5 + min(comparison.appDeltas.count, 20)  // Base metrics + app deltas
            }
        }
        
        return ExportEstimate.estimate(rowCount: totalRows, format: format)
    }
    
    private func buildSectionReport(section: ExportSection, filters: FilterSnapshot, settings: ExportSettings) async throws -> ExportReport {
        let generatedAt = Date()
        let filterSummary = summary(for: filters)
        
        switch section {
        case .summary:
            let summaryData = try await dataService.fetchDashboardSummary(filters: filters)
            return ExportReport(
                title: "Summary",
                destination: .overview,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Summary",
                        headers: ["metric", "value"],
                        rows: [
                            ["total_seconds", formatSeconds(summaryData.totalSeconds)],
                            ["average_daily_seconds", formatSeconds(summaryData.averageDailySeconds)],
                            ["focus_blocks", String(summaryData.focusBlocks)]
                        ]
                    )
                ]
            )
            
        case .apps:
            let apps = try await dataService.fetchTopApps(filters: filters, limit: 200)
            return ExportReport(
                title: "Top Apps",
                destination: .appsCategories,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Apps",
                        headers: ["app_name", "total_seconds", "session_count"],
                        rows: apps.map { [$0.appName, formatSeconds($0.totalSeconds), String($0.sessionCount)] }
                    )
                ]
            )
            
        case .categories:
            let categories = try await dataService.fetchTopCategories(filters: filters, limit: 200)
            return ExportReport(
                title: "Categories",
                destination: .appsCategories,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Categories",
                        headers: ["category", "total_seconds"],
                        rows: categories.map { [$0.category, formatSeconds($0.totalSeconds)] }
                    )
                ]
            )
            
        case .trends:
            let trend = try await dataService.fetchTrend(filters: filters)
            return ExportReport(
                title: "Trends",
                destination: .trends,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Trend",
                        headers: ["date", "total_seconds"],
                        rows: trend.map { [isoDate($0.date), formatSeconds($0.totalSeconds)] }
                    )
                ]
            )
            
        case .sessions:
            let buckets = try await dataService.fetchSessionBuckets(filters: filters)
            return ExportReport(
                title: "Session Distribution",
                destination: .sessions,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Session Distribution",
                        headers: ["duration_range", "session_count"],
                        rows: buckets.map { [$0.label, String($0.sessionCount)] }
                    )
                ]
            )
            
        case .heatmap:
            let cells = try await dataService.fetchHeatmap(filters: filters)
            return ExportReport(
                title: "Heatmap",
                destination: .heatmap,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Heatmap",
                        headers: ["weekday", "hour", "total_seconds"],
                        rows: cells.map { [String($0.weekday), String($0.hour), formatSeconds($0.totalSeconds)] }
                    )
                ]
            )
            
        case .rawSessions:
            let sessions = try await dataService.fetchRawSessions(filters: filters)
            return ExportReport(
                title: "Raw Sessions",
                destination: .rawSessions,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Raw Sessions",
                        headers: ["app_name", "start_time", "end_time", "duration_seconds"],
                        rows: sessions.map { [
                            $0.appName,
                            settings.timestampFormat.format($0.startTime),
                            settings.timestampFormat.format($0.endTime),
                            String(format: "%.3f", $0.durationSeconds)
                        ] }
                    )
                ]
            )
            
        // ── Analytics Sections ──
            
        case .contextSwitches:
            let switches = try await dataService.fetchContextSwitchRate(filters: filters)
            return ExportReport(
                title: "Context Switches",
                destination: .overview,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Context Switch Rate",
                        headers: ["date", "hour", "switch_count"],
                        rows: switches.map { [isoDate($0.date), String($0.hour), String($0.switchCount)] }
                    )
                ]
            )
            
        case .appTransitions:
            let transitions = try await dataService.fetchAppTransitions(filters: filters, limit: 100)
            let totalCount = transitions.reduce(0) { $0 + $1.count }
            return ExportReport(
                title: "App Transitions",
                destination: .overview,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "App Transitions",
                        headers: ["from_app", "to_app", "count", "percentage"],
                        rows: transitions.map { [
                            $0.fromApp,
                            $0.toApp,
                            String($0.count),
                            totalCount > 0 ? String(format: "%.1f", Double($0.count) / Double(totalCount) * 100) : "0.0"
                        ] }
                    )
                ]
            )
            
        case .periodComparison:
            // Calculate previous period based on current range
            let duration = filters.endDate.timeIntervalSince(filters.startDate)
            let previousStart = filters.startDate.addingTimeInterval(-duration)
            let previousEnd = filters.startDate
            
            var previousFilters = filters
            previousFilters.startDate = previousStart
            previousFilters.endDate = previousEnd
            
            let comparison = try await dataService.fetchPeriodComparison(current: filters, previous: previousFilters)
            
            var rows: [[String]] = [
                ["current_total_seconds", formatSeconds(comparison.currentTotalSeconds)],
                ["previous_total_seconds", formatSeconds(comparison.previousTotalSeconds)],
                ["percent_change", String(format: "%.1f", comparison.percentChange)],
                ["current_apps_used", String(comparison.currentAppsUsed)],
                ["previous_apps_used", String(comparison.previousAppsUsed)]
            ]
            
            // Add app-level deltas
            for appDelta in comparison.appDeltas.prefix(20) {
                rows.append([
                    "app_delta:\(appDelta.appName)",
                    String(format: "%.1f", appDelta.percentChange)
                ])
            }
            
            return ExportReport(
                title: "Period Comparison",
                destination: .overview,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Period Comparison",
                        headers: ["metric", "value"],
                        rows: rows
                    )
                ]
            )
        }
    }
    
    private func writeCombinedCSV(reports: [ExportSection: ExportReport], sections: [ExportSection], to fileURL: URL, settings: ExportSettings) throws {
        let csvOpts = settings.csvOptions
        let delimiter = csvOpts.delimiter.rawValue
        
        var lines: [String] = []
        
        if csvOpts.includeMetadataComments {
            lines.append("# Timeprint Combined Export")
            lines.append("# Sections: \(sections.map(\.displayName).joined(separator: ", "))")
            lines.append("# Generated At: \(isoDateTime(Date()))")
        }
        
        for section in sections {
            guard let report = reports[section] else { continue }
            
            if csvOpts.includeMetadataComments {
                lines.append("")
                lines.append("# ═══════════════════════════════════════")
                lines.append("# SECTION: \(section.displayName.uppercased())")
                lines.append("# ═══════════════════════════════════════")
            } else if !lines.isEmpty {
                lines.append("")  // Separator
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
        
        let content = lines.joined(separator: "\n") + "\n"
        
        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }
    
    private func writeCombinedJSON(reports: [ExportSection: ExportReport], sections: [ExportSection], to fileURL: URL, settings: ExportSettings, filters: FilterSnapshot) throws {
        let jsonOpts = settings.jsonOptions
        
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
                    for (index, header) in sectionData.headers.enumerated() {
                        if index < row.count {
                            if let doubleValue = Double(row[index]) {
                                rowDict[header] = doubleValue
                            } else {
                                rowDict[header] = row[index]
                            }
                        }
                    }
                    rows.append(rowDict)
                }
                dataArrays.append([
                    "title": sectionData.title,
                    "data": rows
                ])
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
                jsonObject["title"] = "Timeprint Combined Export"
                jsonObject["generated_at"] = isoDateTime(Date())
                jsonObject["section_count"] = sections.count
                jsonObject["filters"] = summary(for: filters)
            }
            
            jsonObject["sections"] = sectionsData
            outputData = jsonObject
        }
        
        do {
            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: jsonOpts.writingOptions)
            try jsonData.write(to: fileURL)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }
    
    private func writeCombinedPDF(reports: [ExportSection: ExportReport], sections: [ExportSection], to fileURL: URL) throws {
        var mediaBox = CGRect(x: 0, y: 0, width: 842, height: 595) // A4 landscape
        
        guard let context = CGContext(fileURL as CFURL, mediaBox: &mediaBox, nil) else {
            throw ExportError.writeFailed(path: fileURL.path, details: "Could not create PDF context")
        }
        
        for section in sections {
            guard let report = reports[section] else { continue }
            
            context.beginPDFPage(nil)
            
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            
            drawReport(report, in: mediaBox)
            
            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }
        
        context.closePDF()
    }
    
    private func writeCombinedPNG(reports: [ExportSection: ExportReport], sections: [ExportSection], to fileURL: URL) throws {
        // For PNG, we create a single tall image with all sections stacked
        let sectionHeight = 400
        let width = 1800
        let totalHeight = sectionHeight * sections.count
        
        guard let bitmapContext = CGContext(
            data: nil,
            width: width,
            height: totalHeight,
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
        
        // Fill background
        NSColor.windowBackgroundColor.setFill()
        CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(totalHeight)).fill()
        
        // Draw each section
        for (index, section) in sections.enumerated() {
            guard let report = reports[section] else { continue }
            
            let yOffset = CGFloat((sections.count - 1 - index) * sectionHeight)
            let sectionBounds = CGRect(x: 0, y: yOffset, width: CGFloat(width), height: CGFloat(sectionHeight))
            
            drawReport(report, in: sectionBounds)
        }
        
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

    private func exportRawSessions(format: ExportFormat, filters: FilterSnapshot, settings: ExportSettings, progress: ExportProgress?) async throws -> URL {
        // Update progress on main actor if provided
        if let progress {
            await MainActor.run { progress.reset() }
        }

        let sessions = try await dataService.fetchRawSessions(filters: filters)

        if let progress {
            await MainActor.run { progress.update(current: 0, total: sessions.count) }
        }

        // Check for cancellation
        if let progress, await MainActor.run(body: { progress.isCancelled }) {
            throw CancellationError()
        }

        let outputDirectory = try ensureOutputDirectory()
        let fileURL = outputDirectory
            .appendingPathComponent(exportBaseName(destination: .rawSessions, filters: filters))
            .appendingPathExtension(format.fileExtension)

        switch format {
        case .csv:
            try writeRawSessionsCSV(sessions: sessions, to: fileURL, settings: settings, progress: progress)
        case .json:
            try writeRawSessionsJSON(sessions: sessions, to: fileURL, settings: settings, progress: progress)
        case .png, .pdf:
            // For image formats, fall back to summary visualization
            let report = try await buildReport(for: .sessions, filters: filters, settings: settings)
            if format == .png {
                try writePNG(report: report, to: fileURL)
            } else {
                try writePDF(report: report, to: fileURL)
            }
        }

        if let progress {
            await MainActor.run { progress.markComplete() }
        }

        return fileURL
    }

    /// Generate a shareable weekly summary card image
    func generateWeeklySummaryCard(filters: FilterSnapshot) async throws -> URL {
        let summary = try await dataService.fetchDashboardSummary(filters: filters)
        let topApps = try await dataService.fetchTopApps(filters: filters, limit: 5)
        let trend = try await dataService.fetchTrend(filters: filters)

        let outputDirectory = try ensureOutputDirectory()
        let fileURL = outputDirectory
            .appendingPathComponent("timeprint-weekly-summary-\(exportTimestamp(Date()))")
            .appendingPathExtension("png")

        try renderWeeklySummaryCard(
            summary: summary,
            topApps: topApps,
            trend: trend,
            filters: filters,
            to: fileURL
        )

        return fileURL
    }

    /// Copy formatted stats to clipboard
    func copyStatsToClipboard(filters: FilterSnapshot) async throws -> String {
        let summary = try await dataService.fetchDashboardSummary(filters: filters)
        let topApps = try await dataService.fetchTopApps(filters: filters, limit: 5)

        let text = formatStatsForClipboard(summary: summary, topApps: topApps, filters: filters)

        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        return text
    }
}

private extension ExportCoordinator {
    struct ExportReport {
        let title: String
        let destination: NavigationDestination
        let generatedAt: Date
        let filterSummary: String
        let sections: [ExportSectionData]
    }

    struct ExportSectionData {
        let title: String
        let headers: [String]
        let rows: [[String]]
    }

    func buildReport(for destination: NavigationDestination, filters: FilterSnapshot, settings: ExportSettings = ExportSettings()) async throws -> ExportReport {
        let generatedAt = Date()
        let filterSummary = summary(for: filters)

        switch destination {
        case .overview:
            async let summaryValue = dataService.fetchDashboardSummary(filters: filters)
            async let trendValue = dataService.fetchTrend(filters: filters)

            let summary = try await summaryValue
            let trend = try await trendValue

            let summarySection = ExportSectionData(
                title: "Summary",
                headers: ["metric", "value"],
                rows: [
                    ["total_seconds", formatSeconds(summary.totalSeconds)],
                    ["average_daily_seconds", formatSeconds(summary.averageDailySeconds)],
                    ["focus_blocks", String(summary.focusBlocks)]
                ]
            )

            let trendSection = ExportSectionData(
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
                    ExportSectionData(
                        title: "Apps",
                        headers: ["app_name", "total_seconds", "session_count"],
                        rows: apps.map { [$0.appName, formatSeconds($0.totalSeconds), String($0.sessionCount)] }
                    ),
                    ExportSectionData(
                        title: "Categories",
                        headers: ["category", "total_seconds"],
                        rows: categories.map { [$0.category, formatSeconds($0.totalSeconds)] }
                    )
                ]
            )

        case .trends:
            let trend = try await dataService.fetchTrend(filters: filters)
            return ExportReport(
                title: "Trends Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Trend",
                        headers: ["date", "total_seconds"],
                        rows: trend.map { [isoDate($0.date), formatSeconds($0.totalSeconds)] }
                    )
                ]
            )

        case .sessions:
            let buckets = try await dataService.fetchSessionBuckets(filters: filters)
            return ExportReport(
                title: "Sessions Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Session Distribution",
                        headers: ["duration_range", "session_count"],
                        rows: buckets.map { [$0.label, String($0.sessionCount)] }
                    )
                ]
            )

        case .heatmap:
            let cells = try await dataService.fetchHeatmap(filters: filters)
            return ExportReport(
                title: "Heatmap Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Heatmap",
                        headers: ["weekday", "hour", "total_seconds"],
                        rows: cells.map { [String($0.weekday), String($0.hour), formatSeconds($0.totalSeconds)] }
                    )
                ]
            )

        case .rawSessions:
            // Raw sessions handled by dedicated export path; this is a fallback for summary
            let buckets = try await dataService.fetchSessionBuckets(filters: filters)
            return ExportReport(
                title: "Raw Sessions Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Session Distribution (Use CSV/JSON for raw data)",
                        headers: ["duration_range", "session_count"],
                        rows: buckets.map { [$0.label, String($0.sessionCount)] }
                    )
                ]
            )

        case .calendar:
            let focusDays = try await dataService.fetchFocusDays(filters: filters)
            return ExportReport(
                title: "Calendar Export",
                destination: destination,
                generatedAt: generatedAt,
                filterSummary: filterSummary,
                sections: [
                    ExportSectionData(
                        title: "Daily Usage",
                        headers: ["date", "total_seconds", "focus_blocks"],
                        rows: focusDays.map { [isoDate($0.date), formatSeconds($0.totalSeconds), String($0.focusBlocks)] }
                    )
                ]
            )

        case .webHistory, .exports, .settings:
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

    func writeCSV(report: ExportReport, to fileURL: URL, settings: ExportSettings = ExportSettings()) throws {
        let csvOpts = settings.csvOptions
        let delimiter = csvOpts.delimiter.rawValue
        
        var lines: [String] = []
        
        // Add metadata comments if enabled
        if csvOpts.includeMetadataComments {
            lines.append("# Timeprint Export")
            lines.append("# Title: \(report.title)")
            lines.append("# Destination: \(report.destination.title)")
            lines.append("# Generated At: \(isoDateTime(report.generatedAt))")
            lines.append("# Filters: \(report.filterSummary)")
        }

        for section in report.sections {
            if csvOpts.includeMetadataComments {
                lines.append("")
                lines.append("[\(section.title)]")
            } else if lines.isEmpty == false {
                lines.append("") // Empty line separator between sections
            }
            
            if csvOpts.includeHeader {
                lines.append(section.headers.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
            }
            
            for row in section.rows {
                lines.append(row.map { csvEscape($0, options: csvOpts) }.joined(separator: delimiter))
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
    
    func csvEscape(_ value: String, options: CSVExportOptions) -> String {
        options.escape(value)
    }

    // MARK: - JSON Export

    func writeJSON(report: ExportReport, to fileURL: URL, settings: ExportSettings = ExportSettings()) throws {
        let jsonOpts = settings.jsonOptions
        
        var sectionsArray: [[String: Any]] = []
        for section in report.sections {
            var rows: [[String: Any]] = []
            for row in section.rows {
                var rowDict: [String: Any] = [:]
                for (index, header) in section.headers.enumerated() {
                    if index < row.count {
                        // Try to parse as number for cleaner JSON
                        if let doubleValue = Double(row[index]) {
                            rowDict[header] = doubleValue
                        } else {
                            rowDict[header] = row[index]
                        }
                    }
                }
                rows.append(rowDict)
            }

            sectionsArray.append([
                "name": section.title,
                "data": rows
            ])
        }

        let outputData: Any
        
        if jsonOpts.structure == .flat {
            // Flat: just the first section's data array (or merged if multiple)
            if sectionsArray.count == 1, let data = sectionsArray[0]["data"] {
                outputData = data
            } else {
                // Multiple sections: flatten into array of arrays
                outputData = sectionsArray.compactMap { $0["data"] }
            }
        } else {
            // Nested with metadata
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

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: jsonOpts.writingOptions)
            try jsonData.write(to: fileURL)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }

    // MARK: - Raw Session Export

    func writeRawSessionsCSV(sessions: [RawSession], to fileURL: URL, settings: ExportSettings, progress: ExportProgress?) throws {
        let csvOpts = settings.csvOptions
        let delimiter = csvOpts.delimiter.rawValue
        let fieldSelection = settings.fieldSelection(for: .rawSessions)
        let selectedFields = fieldSelection.filter(ExportField.rawSessionFields)
        
        // If no fields selected, export all
        let fieldsToExport = selectedFields.isEmpty ? ExportField.rawSessionFields : selectedFields
        
        var lines: [String] = []
        
        // Add metadata comments if enabled
        if csvOpts.includeMetadataComments {
            lines.append("# Timeprint Raw Sessions Export")
            lines.append("# Timestamp Format: \(settings.timestampFormat.displayName)")
            lines.append("# Row Count: \(sessions.count)")
            lines.append("# Generated At: \(isoDateTime(Date()))")
            lines.append("# Fields: \(fieldsToExport.map(\.rawValue).joined(separator: ", "))")
            lines.append("")
        }
        
        // Add header row if enabled
        if csvOpts.includeHeader {
            let headers = fieldsToExport.map { csvEscape($0.rawValue, options: csvOpts) }
            lines.append(headers.joined(separator: delimiter))
        }

        for (index, session) in sessions.enumerated() {
            // Check cancellation every 1000 rows
            if let progress, index % 1000 == 0 {
                Task { @MainActor in
                    if progress.isCancelled { return }
                    progress.update(current: index, total: sessions.count)
                }
            }

            var rowValues: [String] = []
            for field in fieldsToExport {
                switch field {
                case .appName:
                    rowValues.append(csvEscape(session.appName, options: csvOpts))
                case .startTime:
                    rowValues.append(csvEscape(settings.timestampFormat.format(session.startTime), options: csvOpts))
                case .endTime:
                    rowValues.append(csvEscape(settings.timestampFormat.format(session.endTime), options: csvOpts))
                case .durationSeconds:
                    rowValues.append(String(format: "%.3f", session.durationSeconds))
                default:
                    break // Field not applicable to raw sessions
                }
            }
            lines.append(rowValues.joined(separator: delimiter))
        }

        let content = lines.joined(separator: "\n") + "\n"

        do {
            try content.write(to: fileURL, atomically: true, encoding: .utf8)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }

    func writeRawSessionsJSON(sessions: [RawSession], to fileURL: URL, settings: ExportSettings, progress: ExportProgress?) throws {
        let jsonOpts = settings.jsonOptions
        let fieldSelection = settings.fieldSelection(for: .rawSessions)
        let selectedFields = fieldSelection.filter(ExportField.rawSessionFields)
        
        // If no fields selected, export all
        let fieldsToExport = selectedFields.isEmpty ? ExportField.rawSessionFields : selectedFields
        
        var sessionObjects: [[String: Any]] = []
        sessionObjects.reserveCapacity(sessions.count)

        for (index, session) in sessions.enumerated() {
            // Check cancellation every 1000 rows
            if let progress, index % 1000 == 0 {
                Task { @MainActor in
                    if progress.isCancelled { return }
                    progress.update(current: index, total: sessions.count)
                }
            }

            var obj: [String: Any] = [:]
            for field in fieldsToExport {
                switch field {
                case .appName:
                    obj["app_name"] = session.appName
                case .startTime:
                    obj["start_time"] = settings.timestampFormat.format(session.startTime)
                case .endTime:
                    obj["end_time"] = settings.timestampFormat.format(session.endTime)
                case .durationSeconds:
                    obj["duration_seconds"] = session.durationSeconds
                default:
                    break
                }
            }
            sessionObjects.append(obj)
        }

        let outputData: Any
        
        if jsonOpts.structure == .flat {
            outputData = sessionObjects
        } else {
            // Nested structure with metadata
            var jsonObject: [String: Any] = [:]
            
            if jsonOpts.includeMetadata {
                jsonObject["title"] = "Timeprint Raw Sessions Export"
                jsonObject["timestamp_format"] = settings.timestampFormat.displayName
                jsonObject["row_count"] = sessions.count
                jsonObject["generated_at"] = isoDateTime(Date())
                jsonObject["fields"] = fieldsToExport.map(\.rawValue)
            }
            
            jsonObject["sessions"] = sessionObjects
            outputData = jsonObject
        }

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: outputData, options: jsonOpts.writingOptions)
            try jsonData.write(to: fileURL)
        } catch {
            throw ExportError.writeFailed(path: fileURL.path, details: error.localizedDescription)
        }
    }

    // MARK: - Weekly Summary Card

    func renderWeeklySummaryCard(
        summary: DashboardSummary,
        topApps: [AppUsageSummary],
        trend: [TrendPoint],
        filters: FilterSnapshot,
        to fileURL: URL
    ) throws {
        let width = 1080
        let height = 1920

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

        let bounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        drawWeeklySummaryCard(
            summary: summary,
            topApps: topApps,
            trend: trend,
            filters: filters,
            in: bounds
        )

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

    func drawWeeklySummaryCard(
        summary: DashboardSummary,
        topApps: [AppUsageSummary],
        trend: [TrendPoint],
        filters: FilterSnapshot,
        in bounds: CGRect
    ) {
        // Background gradient — dark elegant
        let gradientColors = [
            NSColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1.0).cgColor,
            NSColor(red: 0.08, green: 0.10, blue: 0.16, alpha: 1.0).cgColor,
            NSColor(red: 0.06, green: 0.08, blue: 0.12, alpha: 1.0).cgColor
        ]
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: gradientColors as CFArray,
            locations: [0, 0.5, 1]
        )!

        let context = NSGraphicsContext.current!.cgContext
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: bounds.midX, y: bounds.maxY),
            end: CGPoint(x: bounds.midX, y: bounds.minY),
            options: []
        )

        // Colors
        let accentColor = NSColor(red: 0.40, green: 0.85, blue: 0.95, alpha: 1.0)
        let textPrimary = NSColor.white
        let textSecondary = NSColor(white: 0.7, alpha: 1.0)
        let textTertiary = NSColor(white: 0.5, alpha: 1.0)

        let margin: CGFloat = 60
        var cursorY = bounds.maxY - 120

        // ─── Header ───
        let brandAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .heavy),
            .foregroundColor: accentColor
        ]
        NSString(string: "TIMEPRINT").draw(at: CGPoint(x: margin, y: cursorY), withAttributes: brandAttributes)
        cursorY -= 60

        // ─── Title ───
        let titleAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 48, weight: .bold),
            .foregroundColor: textPrimary
        ]
        NSString(string: "Weekly Summary").draw(at: CGPoint(x: margin, y: cursorY), withAttributes: titleAttributes)
        cursorY -= 40

        // ─── Date Range ───
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .medium),
            .foregroundColor: textSecondary
        ]
        let rangeText = "\(shortDate(filters.startDate)) → \(shortDate(filters.endDate))"
        NSString(string: rangeText).draw(at: CGPoint(x: margin, y: cursorY), withAttributes: dateAttributes)
        cursorY -= 100

        // ─── Total Time (Hero Stat) ───
        let totalHours = summary.totalSeconds / 3600
        let heroAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 96, weight: .black),
            .foregroundColor: textPrimary
        ]
        let heroText = String(format: "%.1fh", totalHours)
        NSString(string: heroText).draw(at: CGPoint(x: margin, y: cursorY), withAttributes: heroAttributes)
        cursorY -= 40

        let heroLabelAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: textTertiary
        ]
        NSString(string: "TOTAL SCREEN TIME").draw(at: CGPoint(x: margin, y: cursorY), withAttributes: heroLabelAttributes)
        cursorY -= 100

        // ─── Stats Row ───
        let statLabelAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 14, weight: .medium),
            .foregroundColor: textTertiary
        ]
        let statValueAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 36, weight: .bold),
            .foregroundColor: textPrimary
        ]

        // Daily average
        let dailyAvgHours = summary.averageDailySeconds / 3600
        NSString(string: "DAILY AVG").draw(at: CGPoint(x: margin, y: cursorY), withAttributes: statLabelAttrs)
        cursorY -= 45
        NSString(string: String(format: "%.1fh", dailyAvgHours)).draw(at: CGPoint(x: margin, y: cursorY), withAttributes: statValueAttrs)

        // Focus blocks (right side)
        let rightCol: CGFloat = bounds.width / 2 + 20
        NSString(string: "FOCUS BLOCKS").draw(at: CGPoint(x: rightCol, y: cursorY + 45), withAttributes: statLabelAttrs)
        NSString(string: "\(summary.focusBlocks)").draw(at: CGPoint(x: rightCol, y: cursorY), withAttributes: statValueAttrs)
        cursorY -= 100

        // ─── Sparkline Trend ───
        if !trend.isEmpty {
            let sparkHeight: CGFloat = 120
            let sparkWidth = bounds.width - margin * 2
            let sparkY = cursorY - sparkHeight

            // Draw trend line
            let maxVal = trend.map(\.totalSeconds).max() ?? 1
            let minVal = trend.map(\.totalSeconds).min() ?? 0
            let range = max(maxVal - minVal, 1)

            let path = NSBezierPath()
            for (index, point) in trend.enumerated() {
                let x = margin + (sparkWidth / CGFloat(max(trend.count - 1, 1))) * CGFloat(index)
                let y = sparkY + ((point.totalSeconds - minVal) / range) * sparkHeight

                if index == 0 {
                    path.move(to: CGPoint(x: x, y: y))
                } else {
                    path.line(to: CGPoint(x: x, y: y))
                }
            }
            path.lineWidth = 3
            accentColor.setStroke()
            path.stroke()

            cursorY = sparkY - 60
        }

        // ─── Top Apps ───
        let sectionHeaderAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 16, weight: .heavy),
            .foregroundColor: textTertiary
        ]
        NSString(string: "TOP APPS").draw(at: CGPoint(x: margin, y: cursorY), withAttributes: sectionHeaderAttrs)
        cursorY -= 50

        let appNameAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 24, weight: .semibold),
            .foregroundColor: textPrimary
        ]
        let appTimeAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 24, weight: .bold),
            .foregroundColor: accentColor
        ]

        let totalAppSeconds = topApps.reduce(0) { $0 + $1.totalSeconds }

        for (index, app) in topApps.prefix(5).enumerated() {
            let displayName = extractAppName(app.appName)
            let hours = app.totalSeconds / 3600
            let pct = totalAppSeconds > 0 ? (app.totalSeconds / totalAppSeconds * 100) : 0

            // Rank number
            let rankAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedSystemFont(ofSize: 18, weight: .bold),
                .foregroundColor: textTertiary
            ]
            NSString(string: String(format: "%02d", index + 1)).draw(at: CGPoint(x: margin, y: cursorY), withAttributes: rankAttrs)

            // App name
            NSString(string: displayName).draw(at: CGPoint(x: margin + 50, y: cursorY), withAttributes: appNameAttrs)

            // Time
            let timeText = String(format: "%.1fh (%.0f%%)", hours, pct)
            let timeSize = (timeText as NSString).size(withAttributes: appTimeAttrs)
            NSString(string: timeText).draw(at: CGPoint(x: bounds.width - margin - timeSize.width, y: cursorY), withAttributes: appTimeAttrs)

            cursorY -= 55

            // Progress bar
            let barY = cursorY + 20
            let barWidth = bounds.width - margin * 2 - 50
            let barHeight: CGFloat = 6

            // Background
            let bgPath = NSBezierPath(roundedRect: CGRect(x: margin + 50, y: barY, width: barWidth, height: barHeight), xRadius: 3, yRadius: 3)
            NSColor(white: 0.2, alpha: 1.0).setFill()
            bgPath.fill()

            // Fill
            let fillWidth = barWidth * CGFloat(pct / 100)
            let fillPath = NSBezierPath(roundedRect: CGRect(x: margin + 50, y: barY, width: fillWidth, height: barHeight), xRadius: 3, yRadius: 3)
            accentColor.setFill()
            fillPath.fill()

            cursorY -= 30
        }

        // ─── Footer ───
        let footerY: CGFloat = 80
        let footerAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14, weight: .medium),
            .foregroundColor: textTertiary
        ]
        let footerText = "Generated by Timeprint • \(isoDateTime(Date()))"
        let footerSize = (footerText as NSString).size(withAttributes: footerAttrs)
        NSString(string: footerText).draw(at: CGPoint(x: (bounds.width - footerSize.width) / 2, y: footerY), withAttributes: footerAttrs)
    }

    func extractAppName(_ bundleOrName: String) -> String {
        // Extract last component of bundle ID or return as-is
        if bundleOrName.contains(".") {
            return bundleOrName.components(separatedBy: ".").last ?? bundleOrName
        }
        return bundleOrName
    }

    // MARK: - Clipboard Stats Formatting

    func formatStatsForClipboard(
        summary: DashboardSummary,
        topApps: [AppUsageSummary],
        filters: FilterSnapshot
    ) -> String {
        var lines: [String] = []

        lines.append("📊 TIMEPRINT SUMMARY")
        lines.append("━━━━━━━━━━━━━━━━━━━━")
        lines.append("")
        lines.append("📅 \(shortDate(filters.startDate)) → \(shortDate(filters.endDate))")
        lines.append("")

        let totalHours = summary.totalSeconds / 3600
        let dailyAvgHours = summary.averageDailySeconds / 3600

        lines.append("⏱️ Total: \(String(format: "%.1f", totalHours)) hours")
        lines.append("📈 Daily Avg: \(String(format: "%.1f", dailyAvgHours)) hours")
        lines.append("🎯 Focus Blocks: \(summary.focusBlocks)")
        lines.append("")

        if !topApps.isEmpty {
            lines.append("🏆 TOP APPS")
            lines.append("────────────")
            for (index, app) in topApps.prefix(5).enumerated() {
                let hours = app.totalSeconds / 3600
                let name = extractAppName(app.appName)
                lines.append("\(index + 1). \(name): \(String(format: "%.1f", hours))h")
            }
        }

        lines.append("")
        lines.append("Generated by Timeprint")

        return lines.joined(separator: "\n")
    }
}
