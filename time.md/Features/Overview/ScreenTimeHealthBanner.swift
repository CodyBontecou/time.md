import SwiftUI

/// Banner that displays when Screen Time data collection has stopped.
/// Provides actionable steps to help users resolve the issue.
struct ScreenTimeHealthBanner: View {
    let status: ScreenTimeHealthStatus
    @State private var isExpanded = false
    @Environment(\.openURL) private var openURL
    
    private let accentColor = BrutalTheme.accent
    
    var body: some View {
        if status.needsAttention {
            VStack(alignment: .leading, spacing: 0) {
                // Main banner
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(bannerTitle)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(BrutalTheme.textPrimary)
                            
                            Text(bannerSubtitle)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(BrutalTheme.textSecondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(BrutalTheme.textTertiary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)
                
                // Expanded troubleshooting steps
                if isExpanded {
                    Divider()
                        .padding(.horizontal, 16)
                    
                    VStack(alignment: .leading, spacing: 16) {
                        Text("TROUBLESHOOTING STEPS")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(BrutalTheme.textTertiary)
                            .tracking(1)

                        VStack(alignment: .leading, spacing: 12) {
                            if case .noFullDiskAccess = status {
                                troubleshootingStep(
                                    number: 1,
                                    title: "Grant Full Disk Access",
                                    description: "Open System Settings → Privacy & Security → Full Disk Access, then enable time.md.",
                                    action: ("Open Privacy Settings", {
                                        openURL(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
                                    })
                                )

                                troubleshootingStep(
                                    number: 2,
                                    title: "Relaunch time.md",
                                    description: "After granting access, quit and reopen time.md for the change to take effect."
                                )
                            } else {
                                troubleshootingStep(
                                    number: 1,
                                    title: "Check Screen Time is enabled",
                                    description: "Open System Settings → Screen Time and ensure it's turned on.",
                                    action: ("Open Settings", {
                                        openURL(URL(string: "x-apple.systempreferences:com.apple.Screen-Time-Settings.extension")!)
                                    })
                                )

                                troubleshootingStep(
                                    number: 2,
                                    title: "Restart your Mac",
                                    description: "This resets the Screen Time daemon and usually fixes data collection issues."
                                )

                                troubleshootingStep(
                                    number: 3,
                                    title: "Toggle Screen Time off and on",
                                    description: "If restarting doesn't help, try disabling Screen Time, waiting 30 seconds, then re-enabling it."
                                )
                            }
                        }
                        
                        Divider()
                        
                        // Technical details + feedback
                        HStack {
                            if case .stale(let lastDate, let hours) = status {
                                HStack(spacing: 8) {
                                    Image(systemName: "info.circle")
                                        .font(.system(size: 11))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                    
                                    Text("Last data: \(lastDate.formatted(date: .abbreviated, time: .shortened)) (\(hours)h ago)")
                                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                }
                            }
                            
                            Spacer()
                            
                            // Feedback button
                            Button {
                                sendFeedbackEmail()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "envelope")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Send Feedback")
                                        .font(.system(size: 11, weight: .semibold))
                                }
                                .foregroundColor(accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(16)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(accentColor.opacity(0.3), lineWidth: 1)
                    )
            )
        }
    }
    
    // MARK: - Computed Properties
    
    private var bannerTitle: String {
        switch status {
        case .noFullDiskAccess:
            return "Full Disk Access required"
        case .stale:
            return "Screen Time data collection paused"
        case .noData:
            return "No Screen Time data available"
        default:
            return "Screen Time issue detected"
        }
    }

    private var bannerSubtitle: String {
        switch status {
        case .noFullDiskAccess:
            return "time.md needs permission to read Screen Time data. Tap for help."
        case .stale(_, let hours):
            return "macOS hasn't recorded any app usage for \(hours) hours. Tap for help."
        case .noData:
            return "Screen Time may be disabled or this is a new Mac. Tap for help."
        default:
            return "Tap for troubleshooting steps."
        }
    }
    
    // MARK: - Subviews
    
    private func troubleshootingStep(
        number: Int,
        title: String,
        description: String,
        action: (label: String, handler: () -> Void)? = nil
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundColor(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(accentColor))
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(BrutalTheme.textPrimary)
                
                Text(description)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(BrutalTheme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                
                if let action {
                    Button(action: action.handler) {
                        HStack(spacing: 4) {
                            Text(action.label)
                                .font(.system(size: 11, weight: .semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundColor(accentColor)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
            }
        }
    }
    
    private func sendFeedbackEmail() {
        let subject = "time.md Feedback - Screen Time Issue"
        var body = "Hi Cody,\n\nI'm experiencing an issue with Screen Time data collection in time.md.\n\n"
        
        // Add diagnostic info
        if case .stale(let lastDate, let hours) = status {
            body += "Diagnostic Info:\n"
            body += "- Last data recorded: \(lastDate.formatted(date: .abbreviated, time: .shortened))\n"
            body += "- Hours since last record: \(hours)\n"
        } else if case .noData = status {
            body += "Diagnostic Info:\n"
            body += "- Status: No Screen Time data available\n"
        }
        
        body += "- macOS version: \(ProcessInfo.processInfo.operatingSystemVersionString)\n"
        body += "\nAdditional details:\n\n"
        
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        
        if let url = URL(string: "mailto:cody@isolated.tech?subject=\(encodedSubject)&body=\(encodedBody)") {
            openURL(url)
        }
    }
}

// MARK: - Preview

#Preview("Stale Data") {
    VStack(spacing: 20) {
        ScreenTimeHealthBanner(
            status: .stale(
                lastRecordDate: Date().addingTimeInterval(-6 * 3600),
                hoursStale: 6
            )
        )
        
        ScreenTimeHealthBanner(status: .noData)
        
        ScreenTimeHealthBanner(status: .healthy)
    }
    .padding()
    .frame(width: 500)
}
