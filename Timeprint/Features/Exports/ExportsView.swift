import SwiftUI

struct ExportsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var selectedDestination: NavigationDestination = .overview
    @State private var isExporting = false
    @State private var lastMessage = "No export yet"

    private var exportableDestinations: [NavigationDestination] {
        NavigationDestination.allCases.filter { destination in
            switch destination {
            case .overview, .appsCategories:
                return true
            case .settings:
                return false
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Exports")
                .font(.largeTitle.bold())

            Text("Current filter range: \(filters.rangeLabel)")
                .foregroundStyle(.secondary)

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Scope")
                        .font(.headline)

                    Picker("Destination", selection: $selectedDestination) {
                        ForEach(exportableDestinations) { destination in
                            Text(destination.title).tag(destination)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text("Exports include active date range, granularity, and current cross-filter selections.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 12) {
                exportButton(format: .png, label: "Export PNG")
                exportButton(format: .pdf, label: "Export PDF")
                exportButton(format: .csv, label: "Export CSV")
            }
            .disabled(isExporting)

            GlassCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Status")
                        .font(.headline)
                    Text(lastMessage)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .onAppear {
            if !exportableDestinations.contains(selectedDestination),
               let first = exportableDestinations.first {
                selectedDestination = first
            }
        }
    }

    private func exportButton(format: ExportFormat, label: String) -> some View {
        Button(label) {
            Task {
                await export(format: format)
            }
        }
        .buttonStyle(.borderedProminent)
    }

    private func export(format: ExportFormat) async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await appEnvironment.exportCoordinator.export(
                format: format,
                from: selectedDestination,
                filters: filters.snapshot
            )
            lastMessage = "\(format.displayName) export for \(selectedDestination.title) saved to \(url.path)"
        } catch {
            if let localized = error as? LocalizedError,
               let description = localized.errorDescription {
                if let suggestion = localized.recoverySuggestion {
                    lastMessage = "\(description)\n\n\(suggestion)"
                } else {
                    lastMessage = description
                }
            } else {
                lastMessage = error.localizedDescription
            }
        }
    }
}
