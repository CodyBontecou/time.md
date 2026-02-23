import Observation
import SwiftUI

struct RootSplitView: View {
    let filters: GlobalFilterStore

    @State private var selection: NavigationDestination? = .overview
    @State private var isCalendarExpanded = false

    var body: some View {
        ZStack {
            NavigationSplitView {
                List(NavigationDestination.allCases, selection: $selection) { destination in
                    Label {
                        Text(destination.title.uppercased())
                            .font(BrutalTheme.headingFont)
                            .tracking(1)
                    } icon: {
                        Image(systemName: destination.systemImage)
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                    }
                    .tag(destination)
                }
                .navigationTitle("TIMEPRINT")
                .listStyle(.sidebar)
            } detail: {
                VStack(spacing: 0) {
                    Group {
                        switch selection ?? .overview {
                        case .overview:
                            OverviewView(filters: filters, isCalendarExpanded: $isCalendarExpanded)
                        case .appsCategories:
                            AppsCategoriesView(filters: filters)
                        case .webHistory:
                            WebHistoryView(filters: filters)
                        case .settings:
                            SettingsScaffoldView(filters: filters)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .background(BrutalTheme.background)
                .onChange(of: filters.granularity) { _, newValue in
                    filters.adjustDateRange(for: newValue)
                }
            }

            // Expanded calendar overlay
            if isCalendarExpanded {
                AppleCalendarView(filters: filters, isExpanded: $isCalendarExpanded)
                    .background(CalendarColors.background)
            }
        }
    }
}

// MARK: - Settings

private struct SettingsScaffoldView: View {
    let filters: GlobalFilterStore
    @AppStorage("appNameDisplayMode") private var appNameDisplayModeRaw: String = AppNameDisplayMode.short.rawValue

    private var displayMode: AppNameDisplayMode {
        AppNameDisplayMode(rawValue: appNameDisplayModeRaw) ?? .short
    }

    var body: some View {
        let _ = filters

        ScrollView {
            VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                Text("SETTINGS.")
                    .font(BrutalTheme.displayFont)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .tracking(1)

                Rectangle()
                    .fill(BrutalTheme.borderStrong)
                    .frame(height: 2)

                // ─── App Name Display ───
                GlassCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(BrutalTheme.sectionLabel(1, "APP NAME DISPLAY"))
                            .font(BrutalTheme.headingFont)
                            .foregroundColor(BrutalTheme.textSecondary)
                            .tracking(1.5)

                        Text("Choose how app names appear throughout Timeprint.")
                            .font(BrutalTheme.bodyMono)
                            .foregroundColor(BrutalTheme.textPrimary)
                            .lineSpacing(3)

                        HStack(spacing: 0) {
                            ForEach(AppNameDisplayMode.allCases) { mode in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        appNameDisplayModeRaw = mode.rawValue
                                    }
                                } label: {
                                    VStack(spacing: 4) {
                                        Text(mode.title)
                                            .font(BrutalTheme.captionMono)
                                            .tracking(1)
                                        Text("e.g. \(mode.description)")
                                            .font(.system(size: 9, weight: .regular, design: .monospaced))
                                            .opacity(0.7)
                                    }
                                    .foregroundColor(displayMode == mode ? .white : BrutalTheme.textSecondary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                                    .background(displayMode == mode ? BrutalTheme.accent : Color.clear)
                                }
                                .buttonStyle(.plain)

                                if mode != AppNameDisplayMode.allCases.last {
                                    Rectangle()
                                        .fill(BrutalTheme.border)
                                        .frame(width: 1)
                                }
                            }
                        }
                        .frame(maxWidth: 420)
                        .overlay(
                            Rectangle()
                                .strokeBorder(BrutalTheme.border, lineWidth: BrutalTheme.borderWidth)
                        )

                        Text("Short name extracts the last component of a bundle identifier (com.apple.Safari → Safari).")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsBlock(
                    number: 2,
                    title: "DATA SOURCE",
                    body: "Data loads from local SQLite only (normalized screentime.db or knowledgeC.db fallback).",
                    footnote: "Category mappings saved at ~/Library/Application Support/Timeprint/category-mappings.db."
                )

                settingsBlock(
                    number: 3,
                    title: "CATEGORY MAPPING",
                    body: "Mappings are edited from the Apps & Categories view. Single source of truth — no conflicting state.",
                    footnote: nil
                )

                settingsBlock(
                    number: 4,
                    title: "PRIVACY",
                    body: "Timeprint is local-only. No telemetry. No network sync. Your data stays on this machine.",
                    footnote: nil
                )
            }
        }
    }

    private func settingsBlock(number: Int, title: String, body: String, footnote: String?) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 10) {
                Text(BrutalTheme.sectionLabel(number, title))
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text(body)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textPrimary)
                    .lineSpacing(3)

                if let footnote {
                    Text(footnote)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
