import SwiftUI

// MARK: - macOS Onboarding Flow

/// First-launch onboarding for macOS — explains features, data flow, and limitations.
struct MacOnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var animateIn = false

    private let pages: [MacOnboardingPage] = [
        MacOnboardingPage(
            icon: "clock.badge.checkmark.fill",
            iconColor: .blue,
            tag: "01 / WELCOME",
            title: "time.md",
            subtitle: "Privacy-first screen time analytics for macOS.\nUnderstand your digital habits without compromising your data.",
            features: []
        ),
        MacOnboardingPage(
            icon: "square.grid.2x2",
            iconColor: .blue,
            tag: "02 / ANALYTICS",
            title: "Deep Insights",
            subtitle: "Visualize your screen time with precision.",
            features: [
                MacOnboardingFeature(icon: "chart.xyaxis.line", text: "Daily, weekly, and monthly trends"),
                MacOnboardingFeature(icon: "chart.bar.doc.horizontal", text: "App-by-app usage breakdown"),
                MacOnboardingFeature(icon: "timer", text: "Session duration analysis"),
                MacOnboardingFeature(icon: "square.grid.3x3.fill", text: "Hour-by-hour heatmaps"),
                MacOnboardingFeature(icon: "calendar", text: "Calendar view with usage overlays"),
                MacOnboardingFeature(icon: "globe", text: "Web browsing history tracking"),
            ]
        ),
        MacOnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .blue,
            tag: "03 / PRIVACY",
            title: "Your Data, Your Device",
            subtitle: "Everything stays local. No accounts, no telemetry.",
            features: [
                MacOnboardingFeature(icon: "externaldrive.fill", text: "All data stored on this Mac"),
                MacOnboardingFeature(icon: "person.slash", text: "No account or sign-up required"),
                MacOnboardingFeature(icon: "antenna.radiowaves.left.and.right.slash", text: "Zero tracking or analytics collected"),
                MacOnboardingFeature(icon: "square.and.arrow.up", text: "Export your data as CSV or JSON anytime"),
            ]
        ),
        MacOnboardingPage(
            icon: "arrow.triangle.2.circlepath",
            iconColor: .blue,
            tag: "04 / HOW IT WORKS",
            title: "Data & Sync",
            subtitle: "A few things to know about how time.md reads your screen time.",
            features: [
                MacOnboardingFeature(icon: "clock.arrow.2.circlepath", text: "Data refreshes every ~15 minutes from macOS"),
                MacOnboardingFeature(icon: "info.circle", text: "Apple updates screen time data periodically, not in real-time"),
                MacOnboardingFeature(icon: "icloud.fill", text: "Optional iCloud sync shares daily summaries with iOS"),
                MacOnboardingFeature(icon: "desktopcomputer", text: "Background agent syncs every 4 hours when app is closed"),
                MacOnboardingFeature(icon: "checkmark.shield", text: "Full Disk Access required to read screen time database"),
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Navigation dots — top
            HStack(spacing: 10) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: index == currentPage ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentPage)
                }
            }
            .padding(.top, 32)

            // Page content
            MacOnboardingPageView(page: pages[currentPage], isActive: true)
                .id(currentPage)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .offset(x: 20)),
                    removal: .opacity.combined(with: .offset(x: -20))
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom actions
            HStack(spacing: 16) {
                // Back button
                if currentPage > 0 {
                    Button {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage -= 1
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 11, weight: .semibold))
                            Text("Back")
                                .font(.system(size: 13, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(BrutalTheme.textSecondary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                                .fill(Color.primary.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // Skip
                if currentPage < pages.count - 1 {
                    Button {
                        completeOnboarding()
                    } label: {
                        Text("Skip")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }

                // Continue / Get Started
                Button {
                    if currentPage < pages.count - 1 {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            currentPage += 1
                        }
                    } else {
                        completeOnboarding()
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        Image(systemName: currentPage < pages.count - 1 ? "chevron.right" : "arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                            .fill(Color.accentColor)
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 32)
        }
        .frame(width: 640, height: 520)
        .background(BrutalTheme.background)
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedMacOnboarding")
        withAnimation(.easeInOut(duration: 0.25)) {
            isPresented = false
        }
    }
}

// MARK: - Page View

private struct MacOnboardingPageView: View {
    let page: MacOnboardingPage
    let isActive: Bool

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Tag line
            Text(LocalizedStringKey(page.tag))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(2)
                .padding(.bottom, 14)

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 48, weight: .thin))
                .foregroundStyle(page.iconColor)
                .padding(.bottom, 20)

            // Title
            Text(LocalizedStringKey(page.title))
                .font(.system(size: 28, weight: .black, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
                .padding(.bottom, 8)

            // Subtitle
            Text(LocalizedStringKey(page.subtitle))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)
                .padding(.bottom, 24)

            // Feature list
            if !page.features.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(page.features.enumerated()), id: \.offset) { index, feature in
                        HStack(spacing: 14) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(page.iconColor)
                                .frame(width: 22, alignment: .center)

                            Text(LocalizedStringKey(feature.text))
                                .font(.system(size: 12, weight: .regular, design: .monospaced))
                                .foregroundColor(BrutalTheme.textPrimary)

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 80)
            }

            Spacer()
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Models

struct MacOnboardingPage {
    let icon: String
    let iconColor: Color
    let tag: String
    let title: String
    let subtitle: String
    let features: [MacOnboardingFeature]
}

struct MacOnboardingFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

// MARK: - Preview

#Preview {
    MacOnboardingView(isPresented: .constant(true))
}
