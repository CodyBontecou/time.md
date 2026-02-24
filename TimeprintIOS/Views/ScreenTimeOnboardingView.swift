import SwiftUI
import FamilyControls

/// Onboarding flow for Screen Time permissions
struct ScreenTimeOnboardingView: View {
    @StateObject private var authService = AuthorizationService()
    @StateObject private var scheduler = MonitoringScheduler()
    
    @State private var currentStep = 0
    @Binding var isPresented: Bool
    
    let onComplete: (Bool) -> Void // true if authorized
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<4) { step in
                    Capsule()
                        .fill(step <= currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 16)
            
            // Content
            TabView(selection: $currentStep) {
                WelcomeStep(onNext: { currentStep = 1 })
                    .tag(0)
                
                PermissionExplanationStep(onNext: { currentStep = 2 }, onSkip: { skipOnboarding() })
                    .tag(1)
                
                AuthorizationStep(
                    authService: authService,
                    onNext: { currentStep = 3 },
                    onSkip: { skipOnboarding() }
                )
                .tag(2)
                
                CompletionStep(
                    isAuthorized: authService.isAuthorized,
                    scheduler: scheduler,
                    onComplete: { completeOnboarding() }
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)
        }
        .background(Color(.systemGroupedBackground))
    }
    
    private func skipOnboarding() {
        UserDefaults.standard.set(true, forKey: "screenTimeOnboardingSkipped")
        UserDefaults.standard.set(Date(), forKey: "onboardingCompletedDate")
        onComplete(false)
        isPresented = false
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "screenTimeOnboardingCompleted")
        UserDefaults.standard.set(Date(), forKey: "onboardingCompletedDate")
        onComplete(authService.isAuthorized)
        isPresented = false
    }
}

// MARK: - Welcome Step

private struct WelcomeStep: View {
    let onNext: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            
            // Title and description
            VStack(spacing: 12) {
                Text("Track Your Screen Time")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                
                Text("Timeprint can track your iPhone screen time directly, giving you detailed insights into your digital habits.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // Features preview
            VStack(alignment: .leading, spacing: 16) {
                ScreenTimeFeatureRow(
                    icon: "iphone",
                    title: "iPhone Usage",
                    description: "Track time spent in each app"
                )
                
                ScreenTimeFeatureRow(
                    icon: "arrow.triangle.2.circlepath",
                    title: "Sync Everywhere",
                    description: "See your data on all devices"
                )
                
                ScreenTimeFeatureRow(
                    icon: "bell.badge",
                    title: "Smart Insights",
                    description: "Get notified about usage patterns"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Continue button
            Button(action: onNext) {
                Text("Continue")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Permission Explanation Step

private struct PermissionExplanationStep: View {
    let onNext: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            // Icon
            Image(systemName: "lock.shield")
                .font(.system(size: 80))
                .foregroundStyle(.tint)
            
            // Title and description
            VStack(spacing: 12) {
                Text("Privacy First")
                    .font(.title.bold())
                    .multilineTextAlignment(.center)
                
                Text("To track your iPhone usage, Timeprint needs Screen Time permission. Here's what that means:")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            
            // Privacy points
            VStack(alignment: .leading, spacing: 16) {
                ScreenTimePrivacyPoint(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Data stays on your device"
                )
                
                ScreenTimePrivacyPoint(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "We can't see your content"
                )
                
                ScreenTimePrivacyPoint(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Only aggregate usage times"
                )
                
                ScreenTimePrivacyPoint(
                    icon: "checkmark.circle.fill",
                    iconColor: .green,
                    text: "Sync is end-to-end encrypted"
                )
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                Button(action: onNext) {
                    Text("Grant Permission")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                
                Button(action: onSkip) {
                    Text("Skip for now")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Authorization Step

private struct AuthorizationStep: View {
    @ObservedObject var authService: AuthorizationService
    let onNext: () -> Void
    let onSkip: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            if authService.isLoading {
                // Loading state
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                    
                    Text("Requesting permission...")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                }
            } else if authService.isAuthorized {
                // Success state
                VStack(spacing: 16) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.green)
                        .symbolEffect(.bounce)
                    
                    Text("Permission Granted!")
                        .font(.title.bold())
                    
                    Text("Timeprint can now track your screen time.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            } else {
                // Request state
                VStack(spacing: 16) {
                    Image(systemName: "hand.tap")
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)
                    
                    Text("Tap to Allow")
                        .font(.title.bold())
                    
                    Text("A system dialog will appear asking for Screen Time access.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                    
                    if let error = authService.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                }
            }
            
            Spacer()
            
            // Buttons
            VStack(spacing: 12) {
                if authService.isAuthorized {
                    Button(action: onNext) {
                        Text("Continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                } else if !authService.isLoading {
                    Button {
                        Task {
                            await authService.requestAuthorization()
                        }
                    } label: {
                        Text("Request Permission")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundColor(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    
                    Button(action: onSkip) {
                        Text("Continue without tracking")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - Completion Step

private struct CompletionStep: View {
    let isAuthorized: Bool
    @ObservedObject var scheduler: MonitoringScheduler
    @State private var isSettingUpMonitoring = false
    let onComplete: () -> Void
    
    var body: some View {
        VStack(spacing: 32) {
            Spacer()
            
            if isAuthorized {
                // Authorized completion
                VStack(spacing: 16) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 80))
                        .foregroundStyle(.yellow)
                    
                    Text("You're All Set!")
                        .font(.title.bold())
                    
                    Text("Timeprint will now track your screen time and sync it across your devices.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            } else {
                // Non-authorized completion
                VStack(spacing: 16) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 80))
                        .foregroundStyle(.tint)
                    
                    Text("Cloud Sync Only")
                        .font(.title.bold())
                    
                    Text("You can still view your Mac's screen time data synced via iCloud. Enable iPhone tracking anytime in Settings.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }
            
            Spacer()
            
            // Complete button
            Button {
                if isAuthorized {
                    setupMonitoringAndComplete()
                } else {
                    onComplete()
                }
            } label: {
                if isSettingUpMonitoring {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                } else {
                    Text("Get Started")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .disabled(isSettingUpMonitoring)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
    
    private func setupMonitoringAndComplete() {
        isSettingUpMonitoring = true
        
        Task {
            do {
                try scheduler.startDailyMonitoring()
            } catch {
                print("Failed to start monitoring: \(error)")
            }
            
            await MainActor.run {
                isSettingUpMonitoring = false
                onComplete()
            }
        }
    }
}

// MARK: - Helper Views

private struct ScreenTimeFeatureRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ScreenTimePrivacyPoint: View {
    let icon: String
    let iconColor: Color
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(iconColor)
            
            Text(text)
                .font(.subheadline)
        }
    }
}

// MARK: - Preview

#Preview {
    ScreenTimeOnboardingView(
        isPresented: .constant(true),
        onComplete: { _ in }
    )
}
