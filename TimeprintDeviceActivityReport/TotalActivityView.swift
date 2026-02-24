import SwiftUI

/// View displaying total screen time activity
struct TotalActivityView: View {
    let totalActivity: TotalActivityContext
    
    private var hasData: Bool {
        totalActivity.totalDuration > 0
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if hasData {
                // Main total
                VStack(alignment: .leading, spacing: 4) {
                    Text("Screen Time Today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Text(formatDuration(totalActivity.totalDuration))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                }
                
                // Category breakdown
                if !totalActivity.categoryDurations.isEmpty {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("By Category")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        
                        ForEach(totalActivity.categoryDurations.prefix(5), id: \.name) { category in
                            HStack {
                                Text(category.name)
                                    .font(.subheadline)
                                
                                Spacer()
                                
                                Text(formatDuration(category.duration))
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                // Empty state
                VStack(spacing: 12) {
                    Image(systemName: "clock")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    
                    Text("No activity recorded yet")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Text("Start using your iPhone to see screen time data")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
        .padding()
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}

#Preview {
    TotalActivityView(
        totalActivity: TotalActivityContext(
            totalDuration: 7200, // 2 hours
            categoryDurations: [
                (name: "Social", duration: 3600),
                (name: "Productivity", duration: 1800),
                (name: "Entertainment", duration: 1200),
                (name: "Games", duration: 600)
            ],
            date: Date()
        )
    )
}
