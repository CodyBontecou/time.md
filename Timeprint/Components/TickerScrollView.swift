import SwiftUI

/// Scroll mode for the ticker view
enum TickerScrollMode {
    case automatic  // Continuously scrolls left, pauses on hover
    case manual     // User drags/scrolls horizontally
}

/// A horizontally scrolling ticker view that continuously scrolls left
/// and pauses on hover, or allows manual scrolling.
struct TickerScrollView<Content: View>: View {
    let speed: Double // Points per second
    let scrollMode: TickerScrollMode
    @ViewBuilder let content: () -> Content
    
    @State private var contentWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var accumulatedOffset: CGFloat = 0
    @State private var lastUpdate: Date = .now
    
    init(speed: Double = 30, scrollMode: TickerScrollMode = .automatic, @ViewBuilder content: @escaping () -> Content) {
        self.speed = speed
        self.scrollMode = scrollMode
        self.content = content
    }
    
    var body: some View {
        switch scrollMode {
        case .automatic:
            automaticScrollView
        case .manual:
            manualScrollView
        }
    }
    
    // MARK: - Automatic Scrolling View
    
    private var automaticScrollView: some View {
        GeometryReader { geometry in
            let containerWidth = geometry.size.width
            let shouldScroll = contentWidth > 0 && contentWidth > containerWidth
            
            TimelineView(.animation(paused: isHovering)) { timeline in
                let now = timeline.date
                let offset = calculateOffset(now: now, shouldScroll: shouldScroll)
                
                HStack(spacing: 0) {
                    // First copy
                    content()
                        .fixedSize(horizontal: true, vertical: false)
                        .background(
                            GeometryReader { contentGeo in
                                Color.clear
                                    .preference(key: ContentWidthKey.self, value: contentGeo.size.width)
                            }
                        )
                    
                    // Second copy for seamless loop
                    if shouldScroll {
                        content()
                            .fixedSize(horizontal: true, vertical: false)
                    }
                }
                .offset(x: offset)
            }
            .onPreferenceChange(ContentWidthKey.self) { width in
                contentWidth = width
            }
        }
        .clipped()
        .onHover { hovering in
            if hovering {
                // Save current offset when pausing
                accumulatedOffset = fmod(accumulatedOffset + Date.now.timeIntervalSince(lastUpdate) * speed, max(contentWidth, 1))
            }
            lastUpdate = .now
            isHovering = hovering
        }
        .onAppear {
            lastUpdate = .now
        }
    }
    
    // MARK: - Manual Scrolling View
    
    private var manualScrollView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            content()
                .fixedSize(horizontal: true, vertical: false)
        }
    }
    
    private func calculateOffset(now: Date, shouldScroll: Bool) -> CGFloat {
        guard shouldScroll, contentWidth > 0 else { return 0 }
        
        let elapsed = now.timeIntervalSince(lastUpdate)
        let totalOffset = accumulatedOffset + elapsed * speed
        let wrappedOffset = fmod(totalOffset, contentWidth)
        
        return -wrappedOffset
    }
}

private struct ContentWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

#Preview {
    TickerScrollView(speed: 40) {
        HStack(spacing: 12) {
            ForEach(0..<5) { i in
                Text("Insight \(i + 1): Some interesting data point")
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                    )
            }
        }
        .padding(.trailing, 40) // Gap between end and start
    }
    .frame(height: 50)
    .padding()
}
