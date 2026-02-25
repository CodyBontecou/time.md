import AppKit
import SwiftUI

/// Manages zoom (scale) and pan (offset) state for a chart's X-axis.
/// Supports trackpad pinch, mouse scroll-wheel zoom, and drag-to-pan.
@Observable
final class ChartZoomState {

    // MARK: - Public state

    var scale: CGFloat = 1.0
    var panOffset: CGFloat = 0.0          // 0 … max(0, 1 − 1/scale)

    var steadyScale: CGFloat = 1.0
    var steadyPanOffset: CGFloat = 0.0

    /// Set to `true` while the cursor is over the chart area.
    var isHovered: Bool = false

    /// Position of the cursor in the **full data range** (0 = first day, 1 = last day).
    /// Updated externally from `onContinuousHover` via the chart proxy.
    /// Zoom operations anchor on this point so the data under the cursor stays put.
    var cursorDataFraction: CGFloat = 0.5

    var isZoomed: Bool { scale > 1.01 }

    // MARK: - Scroll-wheel monitor

    private var monitor: Any?

    func startMonitoring() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.isHovered else { return event }
            self.handleScrollWheel(event: event)
            return nil   // consume when chart is hovered
        }
    }

    func stopMonitoring() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    // MARK: - Gesture callbacks

    /// Call from `MagnifyGesture.onChanged`.
    func magnifyChanged(_ magnification: CGFloat) {
        applyScale(min(30, max(1, steadyScale * magnification)))
    }

    /// Call from `MagnifyGesture.onEnded`.
    func magnifyEnded() {
        steadyScale = scale
        steadyPanOffset = panOffset
    }

    /// Call from `DragGesture.onChanged`.
    func dragChanged(translationWidth: CGFloat, chartWidth: CGFloat) {
        guard scale > 1, chartWidth > 0 else { return }
        let visibleFraction = 1.0 / scale
        let dragFraction = -translationWidth / chartWidth * visibleFraction
        panOffset = clampPan(steadyPanOffset + dragFraction)
    }

    /// Call from `DragGesture.onEnded`.
    func dragEnded() {
        steadyPanOffset = panOffset
    }

    /// Reset to fully-zoomed-out state.
    func reset() {
        scale = 1.0
        steadyScale = 1.0
        panOffset = 0.0
        steadyPanOffset = 0.0
    }

    // MARK: - Visible range (continuous — no integer-day rounding)

    /// Returns the start/end dates of the visible window after zoom + pan.
    /// Uses continuous time intervals so the chart domain exactly matches the
    /// zoom model, preventing drift when zooming toward the cursor.
    func visibleRange(fullStart: Date, fullEnd: Date) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let rangeStart = calendar.startOfDay(for: fullStart)
        let rangeEnd   = calendar.startOfDay(for: fullEnd)
        let totalInterval = rangeEnd.timeIntervalSince(rangeStart)
        guard totalInterval > 0 else { return (rangeStart, rangeEnd) }

        let windowStartSec = panOffset * totalInterval
        let windowSizeSec  = totalInterval / scale

        let start = rangeStart.addingTimeInterval(windowStartSec)
        let end   = rangeStart.addingTimeInterval(min(windowStartSec + windowSizeSec, totalInterval))

        return (start, end)
    }

    // MARK: - Private

    private func handleScrollWheel(event: NSEvent) {
        let isTrackpad = event.phase != [] || event.momentumPhase != []

        if isTrackpad {
            if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.2 {
                // Predominantly horizontal → pan
                pan(by: event.scrollingDeltaX * 0.002)
            } else if abs(event.scrollingDeltaY) > 0.5 {
                // Predominantly vertical → zoom
                zoom(by: event.scrollingDeltaY * 0.008)
            }
        } else {
            // Mouse scroll wheel → zoom
            zoom(by: event.scrollingDeltaY * 0.025)
        }
    }

    private func zoom(by delta: CGFloat) {
        applyScale(min(30, max(1, scale * (1.0 + delta))))
        steadyScale = scale
        steadyPanOffset = panOffset
    }

    private func pan(by delta: CGFloat) {
        guard scale > 1 else { return }
        panOffset = clampPan(panOffset + delta / scale)
        steadyPanOffset = panOffset
    }

    /// Zoom while keeping the data point under the cursor pinned in place.
    ///
    /// `cursorDataFraction` is the cursor's position in the full data range (0–1),
    /// computed externally from the chart proxy.  We figure out where that point
    /// currently sits on screen, then adjust `panOffset` so it stays there after
    /// the scale change.
    private func applyScale(_ newScale: CGFloat) {
        let oldScale = scale
        let clamped  = min(30, max(1, newScale))

        // Where is the cursor's data point on screen right now? (0 = left edge, 1 = right edge)
        let screenFrac = ((cursorDataFraction - panOffset) * oldScale)
            .clamped(to: 0 ... 1)

        // Solve for the new panOffset that keeps it at the same screen position
        let newPan = cursorDataFraction - screenFrac / clamped

        scale     = clamped
        panOffset = clampPan(newPan)
    }

    private func clampPan(_ offset: CGFloat) -> CGFloat {
        let maxPan = max(0, 1.0 - 1.0 / scale)
        return min(maxPan, max(0, offset))
    }
}

// MARK: - Comparable clamping helper

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
