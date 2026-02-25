import SwiftUI

/// View displaying top apps by screen time
struct TopAppsView: View {
    let apps: [AppActivityData]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Top Apps")
                    .font(.headline)
                
                Spacer()
                
                Text("\(apps.count) apps")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            if apps.isEmpty {
                Text("No app usage data available")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 20)
            } else {
                // App list
                ForEach(apps.prefix(10)) { app in
                    AppRow(app: app, maxDuration: apps.first?.duration ?? 1)
                }
            }
        }
        .padding()
    }
}

struct AppRow: View {
    let app: AppActivityData
    let maxDuration: TimeInterval
    
    private var progress: CGFloat {
        guard maxDuration > 0 else { return 0 }
        return CGFloat(app.duration / maxDuration)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                // App name and category
                VStack(alignment: .leading, spacing: 2) {
                    Text(app.name)
                        .font(.subheadline)
                        .lineLimit(1)
                    
                    if let category = app.category {
                        Text(category)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                // Duration and stats
                VStack(alignment: .trailing, spacing: 2) {
                    Text(formatDuration(app.duration))
                        .font(.subheadline.monospacedDigit())
                    
                    HStack(spacing: 8) {
                        if app.pickupCount > 0 {
                            Label("\(app.pickupCount)", systemImage: "hand.tap")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        
                        if app.notificationCount > 0 {
                            Label("\(app.notificationCount)", systemImage: "bell")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            
            // Progress bar
            GeometryReader { geometry in
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: geometry.size.width * progress, height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 2))
            }
            .frame(height: 4)
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else if minutes > 0 {
            return "\(minutes)m"
        } else {
            return "<1m"
        }
    }
}

#Preview {
    TopAppsView(apps: [
        AppActivityData(
            name: "Instagram",
            bundleId: "com.instagram.app",
            duration: 3600,
            pickupCount: 25,
            notificationCount: 15,
            category: "Social"
        ),
        AppActivityData(
            name: "Safari",
            bundleId: "com.apple.safari",
            duration: 2400,
            pickupCount: 10,
            notificationCount: 0,
            category: "Productivity"
        ),
        AppActivityData(
            name: "Messages",
            bundleId: "com.apple.messages",
            duration: 1800,
            pickupCount: 45,
            notificationCount: 32,
            category: "Social"
        )
    ])
}
