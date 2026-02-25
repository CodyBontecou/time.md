import Foundation

enum DurationFormatter {
    static func short(_ seconds: Double) -> String {
        let intSeconds = Int(seconds.rounded())
        let hours = intSeconds / 3600
        let minutes = (intSeconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }
}
