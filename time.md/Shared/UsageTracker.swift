import Combine
import Foundation

/// Tracks cumulative app foreground usage time.
/// After 12 hours of total usage, the free trial expires.
@MainActor
final class UsageTracker: ObservableObject {
    static let shared = UsageTracker()

    /// 12 hours in seconds
    static let trialDuration: TimeInterval = 12 * 60 * 60

    private static let cumulativeKey = "usageTracker.cumulativeSeconds"
    private static let sessionStartKey = "usageTracker.sessionStart"

    @Published private(set) var cumulativeSeconds: TimeInterval
    @Published private(set) var isTrialExpired: Bool

    private var sessionStart: Date?
    private var ticker: Timer?

    private init() {
        let saved = UserDefaults.standard.double(forKey: Self.cumulativeKey)
        self.cumulativeSeconds = saved
        self.isTrialExpired = saved >= Self.trialDuration
    }

    /// Call when the app becomes active / visible.
    func startSession() {
        guard sessionStart == nil else { return }
        sessionStart = Date()
        ticker = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    /// Call when the app resigns active / goes to background.
    func pauseSession() {
        tick()
        ticker?.invalidate()
        ticker = nil
        sessionStart = nil
    }

    /// Accumulate elapsed time since last tick / session start.
    private func tick() {
        guard let start = sessionStart else { return }
        let elapsed = Date().timeIntervalSince(start)
        sessionStart = Date()
        cumulativeSeconds += elapsed
        UserDefaults.standard.set(cumulativeSeconds, forKey: Self.cumulativeKey)
        isTrialExpired = cumulativeSeconds >= Self.trialDuration
    }

    /// Remaining trial time in seconds (floored to 0).
    var remainingSeconds: TimeInterval {
        max(Self.trialDuration - cumulativeSeconds, 0)
    }

    /// Formatted remaining time string (e.g. "11h 42m").
    var remainingFormatted: String {
        let remaining = remainingSeconds
        let hours = Int(remaining) / 3600
        let minutes = (Int(remaining) % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        } else {
            return "\(minutes)m"
        }
    }
}
