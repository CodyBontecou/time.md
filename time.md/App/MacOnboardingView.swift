import SwiftUI

// MARK: - macOS Onboarding Flow

/// First-launch onboarding for macOS — explains features, data flow, and limitations.
struct MacOnboardingView: View {
    @Binding var isPresented: Bool
    /// When true, the paywall slide is included as the final page and the user
    /// must subscribe (or restore) before the flow can complete. When false
    /// (e.g. for grandfathered users), onboarding ends at the informational
    /// slides with a normal "Get Started" close button.
    var requiresPaywall: Bool = false
    @State private var currentPage = 0
    @State private var animateIn = false
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared

    /// Index used by the paywall slide. -1 means "no paywall".
    private var paywallIndex: Int { requiresPaywall ? pages.count : -1 }
    private var totalSlides: Int { pages.count + (requiresPaywall ? 1 : 0) }
    private var isOnPaywall: Bool { currentPage == paywallIndex }
    private var isOnLastInfoSlide: Bool { currentPage == pages.count - 1 }

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
            icon: "chart.pie.fill",
            iconColor: .blue,
            tag: "02 / OVERVIEW",
            title: "Your day at a glance",
            subtitle: "Total time, daily averages, peak hour, and a session timeline — all on one screen.",
            features: [],
            screenshot: "OnboardingOverview"
        ),
        MacOnboardingPage(
            icon: "chart.bar.xaxis",
            iconColor: .blue,
            tag: "03 / REVIEW",
            title: "Compare & visualize",
            subtitle: "Bar, pie, and trend charts grouped by app or category. Spot patterns with the activity heatmap.",
            features: [],
            screenshot: "OnboardingReview"
        ),
        MacOnboardingPage(
            icon: "list.bullet.rectangle",
            iconColor: .blue,
            tag: "04 / DETAILS",
            title: "Every session, every switch",
            subtitle: "Inspect individual sessions, top app transitions, and your peak context-switching hours.",
            features: [],
            screenshot: "OnboardingDetails"
        ),
        MacOnboardingPage(
            icon: "folder.fill",
            iconColor: .blue,
            tag: "05 / PROJECTS",
            title: "Roll apps into projects",
            subtitle: "Group apps into categories like Productivity, Games, or Business — and see how your time splits.",
            features: [],
            screenshot: "OnboardingProjects"
        ),
        MacOnboardingPage(
            icon: "wand.and.stars",
            iconColor: .blue,
            tag: "06 / RULES",
            title: "Smart auto-categorization",
            subtitle: "Map every app once with built-in suggestions. Coverage tracking shows what's still uncategorized.",
            features: [],
            screenshot: "OnboardingRules"
        ),
        MacOnboardingPage(
            icon: "chart.line.uptrend.xyaxis",
            iconColor: .blue,
            tag: "07 / REPORTS",
            title: "Trends & weekday patterns",
            subtitle: "Time distribution over any range, weekday averages, and one-click export to CSV, JSON, or Markdown.",
            features: [],
            screenshot: "OnboardingReports"
        ),
        MacOnboardingPage(
            icon: "globe",
            iconColor: .blue,
            tag: "08 / WEB HISTORY",
            title: "Where you spend time online",
            subtitle: "Top domains, daily visit averages, and peak browsing hours — across Safari, Chrome, and Arc.",
            features: [],
            screenshot: "OnboardingWebHistory"
        ),
        MacOnboardingPage(
            icon: "square.and.arrow.up.fill",
            iconColor: .blue,
            tag: "09 / EXPORT",
            title: "Your data, your format",
            subtitle: "Pick exactly which sections, filters, and date ranges to export. CSV, JSON, or Markdown.",
            features: [],
            screenshot: "OnboardingExport"
        ),
        MacOnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .blue,
            tag: "10 / PRIVACY",
            title: "Local-first, by design",
            subtitle: "Tracks app switches in real-time. Everything stays on your Mac.",
            features: [
                MacOnboardingFeature(icon: "bolt.fill", text: "Real-time tracking via macOS workspace events"),
                MacOnboardingFeature(icon: "lock.fill", text: "All data stays in time.md's sandbox"),
                MacOnboardingFeature(icon: "person.slash", text: "No account or sign-up required"),
                MacOnboardingFeature(icon: "antenna.radiowaves.left.and.right.slash", text: "Zero tracking or analytics collected"),
            ]
        ),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Navigation dots — top
            HStack(spacing: 10) {
                ForEach(0..<totalSlides, id: \.self) { index in
                    Capsule()
                        .fill(index == currentPage ? Color.accentColor : Color.primary.opacity(0.12))
                        .frame(width: index == currentPage ? 28 : 8, height: 8)
                        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: currentPage)
                }
            }
            .padding(.top, 32)

            // Page content
            Group {
                if isOnPaywall {
                    PaywallView(onEntitled: completeOnboarding)
                } else {
                    MacOnboardingPageView(page: pages[currentPage], isActive: true)
                }
            }
            .id(currentPage)
            .transition(.asymmetric(
                insertion: .opacity.combined(with: .offset(x: 20)),
                removal: .opacity.combined(with: .offset(x: -20))
            ))
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Bottom actions — hidden on paywall slide; the paywall has its own CTA.
            if !isOnPaywall {
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

                    // Skip — only on intermediate info slides, never when a paywall awaits.
                    if !isOnLastInfoSlide && !requiresPaywall {
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
                        if !isOnLastInfoSlide {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage += 1
                            }
                        } else if requiresPaywall {
                            withAnimation(.easeInOut(duration: 0.3)) {
                                currentPage = paywallIndex
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text(continueLabel)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            Image(systemName: !isOnLastInfoSlide ? "chevron.right" : "arrow.right")
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
        }
        .frame(width: 640, height: 600)
        .background(BrutalTheme.background)
        .overlay(alignment: .topLeading) {
            if isOnPaywall {
                Button {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        currentPage = pages.count - 1
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(BrutalTheme.textSecondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: BrutalTheme.pillCornerRadius)
                            .fill(Color.primary.opacity(0.06))
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
                .padding(.leading, 24)
            }
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.5)) {
                animateIn = true
            }
        }
    }

    private var continueLabel: String {
        if !isOnLastInfoSlide { return "Continue" }
        return requiresPaywall ? "Continue" : "Get Started"
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
            Spacer(minLength: 0)

            // Tag line
            Text(LocalizedStringKey(page.tag))
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(BrutalTheme.textTertiary)
                .tracking(2)
                .padding(.bottom, 14)

            // Icon — hidden on screenshot slides; the screenshot is the visual.
            if page.screenshot == nil {
                Image(systemName: page.icon)
                    .font(.system(size: 48, weight: .thin))
                    .foregroundStyle(page.iconColor)
                    .padding(.bottom, 20)
            }

            // Title
            Text(LocalizedStringKey(page.title))
                .font(.system(size: page.screenshot == nil ? 28 : 22, weight: .black, design: .monospaced))
                .foregroundColor(BrutalTheme.textPrimary)
                .padding(.bottom, 8)

            // Subtitle
            Text(LocalizedStringKey(page.subtitle))
                .font(.system(size: 12, weight: .regular, design: .monospaced))
                .foregroundColor(BrutalTheme.textSecondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .frame(maxWidth: 440)
                .padding(.bottom, page.screenshot == nil ? 24 : 18)

            // Screenshot mockup — rendered as a window-styled card
            if let screenshot = page.screenshot {
                ScreenshotCard(imageName: screenshot)
                    .frame(maxWidth: 500, maxHeight: 320)
                    .padding(.horizontal, 40)
            }

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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Screenshot Card

/// Renders an asset-catalog image as a macOS-window-styled card with traffic
/// lights, rounded corners, and a soft shadow.
private struct ScreenshotCard: View {
    let imageName: String

    var body: some View {
        VStack(spacing: 0) {
            // Title bar with traffic lights
            HStack(spacing: 6) {
                Circle().fill(Color(red: 1.0, green: 0.37, blue: 0.36)).frame(width: 9, height: 9)
                Circle().fill(Color(red: 1.0, green: 0.74, blue: 0.20)).frame(width: 9, height: 9)
                Circle().fill(Color(red: 0.16, green: 0.79, blue: 0.27)).frame(width: 9, height: 9)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.04))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.primary.opacity(0.08))
                    .frame(height: 0.5)
            }

            // Screenshot
            Image(imageName)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 18, x: 0, y: 8)
        .shadow(color: Color.black.opacity(0.06), radius: 2, x: 0, y: 1)
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
    /// Optional asset-catalog image rendered as a window-styled mockup.
    var screenshot: String? = nil
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
