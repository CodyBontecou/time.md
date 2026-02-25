import SwiftUI
import FamilyControls

/// First-launch onboarding flow for iOS
struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    @State private var showScreenTimeOnboarding = false
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "clock.badge.checkmark.fill",
            iconColor: .blue,
            title: "Welcome to time.md",
            subtitle: "Understand your screen time across all your Apple devices",
            features: []
        ),
        OnboardingPage(
            icon: "macbook.and.iphone",
            iconColor: .purple,
            title: "Sync from Your Mac",
            subtitle: "time.md reads Screen Time data from your Mac and syncs it via iCloud",
            features: [
                Feature(icon: "desktopcomputer", text: "Install time.md on your Mac"),
                Feature(icon: "icloud.fill", text: "Sign in with the same iCloud account"),
                Feature(icon: "arrow.triangle.2.circlepath", text: "Data syncs automatically")
            ]
        ),
        OnboardingPage(
            icon: "iphone",
            iconColor: .green,
            title: "Track iPhone Too",
            subtitle: "Optionally track your iPhone usage directly on this device",
            features: [
                Feature(icon: "hourglass", text: "Native Screen Time integration"),
                Feature(icon: "chart.bar.xaxis", text: "See iPhone + Mac combined"),
                Feature(icon: "hand.raised.fill", text: "One-time permission required")
            ]
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            iconColor: .teal,
            title: "Beautiful Analytics",
            subtitle: "See your usage patterns with intuitive visualizations",
            features: [
                Feature(icon: "calendar", text: "Daily and weekly trends"),
                Feature(icon: "square.grid.2x2", text: "App-by-app breakdown"),
                Feature(icon: "chart.bar", text: "Session insights")
            ]
        ),
        OnboardingPage(
            icon: "lock.shield.fill",
            iconColor: .orange,
            title: "Privacy First",
            subtitle: "Your data stays on your devices",
            features: [
                Feature(icon: "person.slash", text: "No account required"),
                Feature(icon: "antenna.radiowaves.left.and.right.slash", text: "No tracking or analytics"),
                Feature(icon: "externaldrive.fill", text: "All data stored locally")
            ]
        )
    ]
    
    /// Check if we're on the iPhone tracking page
    private var isOnIPhoneTrackingPage: Bool {
        currentPage == 2 // The "Track iPhone Too" page
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Page content
            TabView(selection: $currentPage) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    OnboardingPageView(page: page)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentPage)
            
            // Bottom section
            VStack(spacing: 20) {
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Circle()
                            .fill(index == currentPage ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .animation(.easeInOut, value: currentPage)
                    }
                }
                
                // Action button(s)
                if isOnIPhoneTrackingPage {
                    // Special handling for iPhone tracking page
                    VStack(spacing: 12) {
                        Button {
                            showScreenTimeOnboarding = true
                        } label: {
                            Text("Enable iPhone Tracking")
                                .font(.headline)
                                .foregroundColor(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                        }
                        
                        Button {
                            withAnimation {
                                currentPage += 1
                            }
                        } label: {
                            Text("Maybe Later")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Standard continue button
                    Button {
                        if currentPage < pages.count - 1 {
                            withAnimation {
                                currentPage += 1
                            }
                        } else {
                            completeOnboarding()
                        }
                    } label: {
                        Text(currentPage < pages.count - 1 ? "Continue" : "Get Started")
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .padding(.horizontal, 24)
                    
                    // Skip button (not on last page or iPhone tracking page)
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    }
                }
            }
            .padding(.bottom, 40)
        }
        .background(Color(.systemBackground))
        .sheet(isPresented: $showScreenTimeOnboarding) {
            ScreenTimeOnboardingView(isPresented: $showScreenTimeOnboarding) { authorized in
                // Move to next page after Screen Time onboarding completes
                withAnimation {
                    currentPage += 1
                }
            }
        }
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation {
            isPresented = false
        }
    }
}

// MARK: - Page View

struct OnboardingPageView: View {
    let page: OnboardingPage
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.iconColor)
                .padding(.bottom, 8)
            
            // Title & subtitle
            VStack(spacing: 12) {
                Text(page.title)
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(page.subtitle)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            // Features list
            if !page.features.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(page.features) { feature in
                        FeatureRow(feature: feature)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.top, 16)
            }
            
            Spacer()
            Spacer()
        }
        .padding()
    }
}

// MARK: - Feature Row

struct FeatureRow: View {
    let feature: Feature
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: feature.icon)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            Text(feature.text)
                .font(.subheadline)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
}

// MARK: - Models

struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let features: [Feature]
}

struct Feature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

// MARK: - Preview

#Preview {
    OnboardingView(isPresented: .constant(true))
}
