import SwiftUI

// MARK: - Animated Number View

/// Displays a number with a count-up animation when the value changes.
struct AnimatedNumber: View, Animatable {
    var value: Double
    let formatter: (Double) -> String
    let font: Font
    let color: Color

    init(
        _ value: Double,
        font: Font = .system(size: 28, weight: .heavy, design: .rounded),
        color: Color = BrutalTheme.textPrimary,
        formatter: @escaping (Double) -> String = { String(format: "%.0f", $0) }
    ) {
        self.value = value
        self.font = font
        self.color = color
        self.formatter = formatter
    }

    var animatableData: Double {
        get { value }
        set { value = newValue }
    }

    var body: some View {
        Text(formatter(value))
            .font(font)
            .foregroundColor(color)
            .contentTransition(.numericText(value: value))
            .monospacedDigit()
    }
}

/// Duration-specific animated number that formats as "Xh Ym".
struct AnimatedDuration: View {
    let seconds: Double
    let font: Font
    let color: Color

    init(
        _ seconds: Double,
        font: Font = .system(size: 28, weight: .heavy, design: .rounded),
        color: Color = BrutalTheme.textPrimary
    ) {
        self.seconds = seconds
        self.font = font
        self.color = color
    }

    var body: some View {
        AnimatedNumber(
            seconds,
            font: font,
            color: color,
            formatter: { DurationFormatter.short($0) }
        )
    }
}

// MARK: - Sparkline Drawing Animation Modifier

/// Clips a path from left-to-right with animation.
struct SparklineDrawModifier: ViewModifier {
    @State private var progress: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .mask(
                GeometryReader { proxy in
                    Rectangle()
                        .frame(width: proxy.size.width * progress)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            )
            .onAppear {
                withAnimation(.easeOut(duration: 0.8)) {
                    progress = 1
                }
            }
    }
}

extension View {
    /// Animates a sparkline/chart by revealing from left to right.
    func sparklineDrawAnimation() -> some View {
        modifier(SparklineDrawModifier())
    }
}

// MARK: - Hover Scale Effect

struct HoverScaleModifier: ViewModifier {
    let scale: CGFloat
    @State private var isHovered = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isHovered ? scale : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

extension View {
    /// Subtle scale on hover for interactive cards.
    func hoverScale(_ scale: CGFloat = 1.02) -> some View {
        modifier(HoverScaleModifier(scale: scale))
    }
}
