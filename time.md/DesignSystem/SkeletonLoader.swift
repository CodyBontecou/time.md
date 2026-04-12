#if os(macOS)
import SwiftUI

// MARK: - Skeleton Loader
// Animated placeholder view for loading states.

struct SkeletonLoader: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = 4
    
    @State private var isAnimating = false
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                LinearGradient(
                    colors: [
                        BrutalTheme.textTertiary.opacity(0.15),
                        BrutalTheme.textTertiary.opacity(0.25),
                        BrutalTheme.textTertiary.opacity(0.15)
                    ],
                    startPoint: isAnimating ? .leading : .trailing,
                    endPoint: isAnimating ? .trailing : .leading
                )
            )
            .frame(width: width, height: height)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                ) {
                    isAnimating = true
                }
            }
    }
}

// MARK: - Skeleton Pill (for metric cards)

struct SkeletonPill: View {
    @State private var isAnimating = false
    
    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 7)
                .fill(shimmerGradient)
                .frame(width: 28, height: 28)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonLoader(width: 60, height: 8)
                SkeletonLoader(width: 40, height: 14)
            }
            
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
    
    private var shimmerGradient: some ShapeStyle {
        BrutalTheme.textTertiary.opacity(0.15)
    }
}

// MARK: - Skeleton Table Row

struct SkeletonTableRow: View {
    var body: some View {
        HStack(spacing: 0) {
            SkeletonLoader(width: 50, height: 12)
                .frame(width: 70, alignment: .leading)
            
            VStack(alignment: .leading, spacing: 4) {
                SkeletonLoader(width: 200, height: 12)
                SkeletonLoader(width: 280, height: 8)
            }
            
            Spacer(minLength: 8)
            
            SkeletonLoader(width: 100, height: 12)
                .frame(width: 160, alignment: .trailing)
            
            SkeletonLoader(width: 16, height: 12)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 10)
    }
}

// MARK: - Skeleton Chart

struct SkeletonBarChart: View {
    let barCount: Int
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(0..<barCount, id: \.self) { index in
                SkeletonLoader(
                    width: nil,
                    height: randomHeight(for: index),
                    cornerRadius: 2
                )
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 180)
        .padding(.top, 20)
    }
    
    private func randomHeight(for index: Int) -> CGFloat {
        // Deterministic "random" heights based on index for consistent appearance
        let heights: [CGFloat] = [60, 100, 45, 120, 80, 140, 55, 90, 70, 110]
        return heights[index % heights.count]
    }
}

// MARK: - Web History Skeleton View

struct WebHistorySkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Metrics strip skeleton
            HStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonPill()
                }
            }
            
            // Tab content skeleton
            VStack(alignment: .leading, spacing: 16) {
                // Search bar skeleton
                HStack(spacing: 8) {
                    SkeletonLoader(width: 14, height: 14)
                    SkeletonLoader(width: 200, height: 14)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                
                // Table skeleton
                GlassCard {
                    VStack(spacing: 0) {
                        // Header
                        HStack {
                            SkeletonLoader(width: 40, height: 10)
                                .frame(width: 70, alignment: .leading)
                            SkeletonLoader(width: 80, height: 10)
                            Spacer()
                            SkeletonLoader(width: 50, height: 10)
                                .frame(width: 160, alignment: .trailing)
                            SkeletonLoader(width: 24, height: 10)
                                .frame(width: 36, alignment: .trailing)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 8)
                        
                        Rectangle()
                            .fill(BrutalTheme.borderStrong.opacity(0.3))
                            .frame(height: 1)
                        
                        // Rows
                        ForEach(0..<8, id: \.self) { index in
                            VStack(spacing: 0) {
                                SkeletonTableRow()
                                
                                if index < 7 {
                                    Rectangle()
                                        .fill(BrutalTheme.border)
                                        .frame(height: 0.5)
                                }
                            }
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Overview Skeleton View

struct OverviewSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Insight cards grid skeleton (2 rows of 4)
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
                GridItem(.flexible(), spacing: 12),
            ], spacing: 12) {
                ForEach(0..<8, id: \.self) { _ in
                    SkeletonInsightCard()
                }
            }
            
            // Top Apps chart skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 80, height: 12)
                    
                    SkeletonBarChart(barCount: 8)
                }
            }
            
            // App usage table skeleton
            SkeletonLoader(width: 100, height: 12)
            
            GlassCard {
                VStack(spacing: 0) {
                    // Header
                    HStack {
                        SkeletonLoader(width: 20, height: 10)
                            .frame(width: 28, alignment: .leading)
                        SkeletonLoader(width: 30, height: 10)
                        Spacer()
                        SkeletonLoader(width: 40, height: 10)
                            .frame(width: 80, alignment: .trailing)
                        SkeletonLoader(width: 30, height: 10)
                            .frame(width: 52, alignment: .trailing)
                        SkeletonLoader(width: 20, height: 10)
                            .frame(width: 48, alignment: .trailing)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 8)
                    
                    Rectangle()
                        .fill(BrutalTheme.borderStrong.opacity(0.3))
                        .frame(height: 1)
                    
                    // Rows
                    ForEach(0..<6, id: \.self) { index in
                        VStack(spacing: 0) {
                            SkeletonAppRow()
                            
                            if index < 5 {
                                Rectangle()
                                    .fill(BrutalTheme.border)
                                    .frame(height: 0.5)
                            }
                        }
                    }
                }
            }
            
            // Bottom cards skeleton
            HStack(alignment: .top, spacing: 16) {
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonLoader(width: 120, height: 12)
                        ForEach(0..<7, id: \.self) { _ in
                            HStack(spacing: 8) {
                                SkeletonLoader(width: 28, height: 12)
                                SkeletonLoader(height: 14)
                                SkeletonLoader(width: 48, height: 10)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                
                GlassCard {
                    VStack(alignment: .leading, spacing: 12) {
                        SkeletonLoader(width: 120, height: 12)
                        ForEach(0..<6, id: \.self) { _ in
                            HStack(spacing: 6) {
                                SkeletonLoader(width: 18, height: 12)
                                SkeletonLoader(width: 60, height: 12)
                                SkeletonLoader(width: 12, height: 12)
                                SkeletonLoader(width: 60, height: 12)
                                Spacer()
                                SkeletonLoader(width: 24, height: 12)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Skeleton Insight Card

struct SkeletonInsightCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonLoader(width: 24, height: 24, cornerRadius: 6)
                Spacer()
                SkeletonLoader(width: 40, height: 16)
            }
            
            Spacer()
            
            SkeletonLoader(width: 60, height: 10)
            SkeletonLoader(width: 80, height: 20)
        }
        .padding(12)
        .frame(height: 100)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
    }
}

// MARK: - Skeleton App Row

struct SkeletonAppRow: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SkeletonLoader(width: 20, height: 12)
                    .frame(width: 28, alignment: .leading)
                
                SkeletonLoader(width: 120, height: 12)
                
                Spacer(minLength: 8)
                
                SkeletonLoader(width: 50, height: 12)
                    .frame(width: 80, alignment: .trailing)
                
                SkeletonLoader(width: 24, height: 12)
                    .frame(width: 52, alignment: .trailing)
                
                SkeletonLoader(width: 36, height: 12)
                    .frame(width: 48, alignment: .trailing)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            
            // Percentage bar placeholder
            GeometryReader { geo in
                SkeletonLoader(width: geo.size.width * 0.3, height: 3, cornerRadius: 2)
            }
            .frame(height: 3)
        }
    }
}

// MARK: - Trends Skeleton View

struct TrendsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Controls row skeleton
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonLoader(width: 60, height: 30, cornerRadius: 6)
                }
                Spacer()
            }
            
            // Main chart skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 100, height: 12)
                    
                    // Area chart skeleton
                    GeometryReader { geo in
                        Path { path in
                            let width = geo.size.width
                            let height = geo.size.height
                            path.move(to: CGPoint(x: 0, y: height * 0.7))
                            path.addCurve(
                                to: CGPoint(x: width * 0.3, y: height * 0.4),
                                control1: CGPoint(x: width * 0.1, y: height * 0.6),
                                control2: CGPoint(x: width * 0.2, y: height * 0.5)
                            )
                            path.addCurve(
                                to: CGPoint(x: width * 0.6, y: height * 0.5),
                                control1: CGPoint(x: width * 0.4, y: height * 0.3),
                                control2: CGPoint(x: width * 0.5, y: height * 0.45)
                            )
                            path.addCurve(
                                to: CGPoint(x: width, y: height * 0.3),
                                control1: CGPoint(x: width * 0.75, y: height * 0.55),
                                control2: CGPoint(x: width * 0.9, y: height * 0.35)
                            )
                            path.addLine(to: CGPoint(x: width, y: height))
                            path.addLine(to: CGPoint(x: 0, y: height))
                            path.closeSubpath()
                        }
                        .fill(BrutalTheme.textTertiary.opacity(0.1))
                    }
                    .frame(height: 300)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Sessions Skeleton View

struct SessionsSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Mode toggle skeleton
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonLoader(width: 90, height: 30, cornerRadius: 6)
                }
                Spacer()
            }
            
            // Chart card skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 180, height: 12)
                    SkeletonLoader(width: 260, height: 10)
                    
                    // Bar chart skeleton
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(0..<24, id: \.self) { index in
                            SkeletonLoader(
                                width: nil,
                                height: randomBarHeight(for: index),
                                cornerRadius: 2
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 260)
                }
            }
            
            // Second chart skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 200, height: 12)
                    SkeletonLoader(width: 220, height: 10)
                    
                    HStack(alignment: .bottom, spacing: 6) {
                        ForEach(0..<24, id: \.self) { index in
                            SkeletonLoader(
                                width: nil,
                                height: randomBarHeight2(for: index),
                                cornerRadius: 2
                            )
                            .frame(maxWidth: .infinity)
                        }
                    }
                    .frame(height: 260)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    private func randomBarHeight(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [40, 80, 120, 180, 200, 160, 140, 100, 60, 90, 130, 170, 190, 210, 180, 150, 120, 100, 80, 60, 50, 40, 30, 20]
        return heights[index % heights.count]
    }
    
    private func randomBarHeight2(for index: Int) -> CGFloat {
        let heights: [CGFloat] = [20, 40, 60, 100, 140, 120, 100, 80, 70, 90, 110, 140, 160, 180, 150, 120, 90, 70, 50, 40, 30, 25, 20, 15]
        return heights[index % heights.count]
    }
}

// MARK: - Apps & Categories Skeleton View

struct AppsCategoriesSkeletonView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
            // Mode toggle skeleton
            HStack(spacing: 6) {
                ForEach(0..<2, id: \.self) { _ in
                    SkeletonLoader(width: 80, height: 30, cornerRadius: 6)
                }
            }
            
            // Chart card skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    SkeletonLoader(width: 140, height: 12)
                    
                    // Horizontal bar chart skeleton
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(0..<12, id: \.self) { index in
                            HStack(spacing: 8) {
                                SkeletonLoader(width: 100, height: 12)
                                    .frame(width: 100, alignment: .trailing)
                                
                                GeometryReader { geo in
                                    SkeletonLoader(
                                        width: geo.size.width * randomBarWidth(for: index),
                                        height: 20,
                                        cornerRadius: 0
                                    )
                                }
                                .frame(height: 20)
                            }
                        }
                    }
                    .frame(height: 320)
                    
                    SkeletonLoader(width: 240, height: 10)
                }
            }
            
            // Cross-filter panel skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 100, height: 12)
                    
                    // Chip grid skeleton
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 0)], spacing: 0) {
                        ForEach(0..<12, id: \.self) { _ in
                            HStack(spacing: 6) {
                                SkeletonLoader(width: 8, height: 8, cornerRadius: 2)
                                SkeletonLoader(width: 80, height: 10)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                        }
                    }
                    
                    HStack(spacing: 12) {
                        SkeletonLoader(width: 50, height: 24, cornerRadius: 4)
                        SkeletonLoader(width: 80, height: 10)
                    }
                }
            }
            
            // Mapping editor skeleton
            GlassCard {
                VStack(alignment: .leading, spacing: 12) {
                    SkeletonLoader(width: 140, height: 12)
                    SkeletonLoader(width: 320, height: 10)
                    
                    Rectangle()
                        .fill(BrutalTheme.border)
                        .frame(height: 0.5)
                    
                    ForEach(0..<8, id: \.self) { _ in
                        HStack(spacing: 10) {
                            SkeletonLoader(width: 120, height: 12)
                            Spacer()
                            SkeletonLoader(width: 200, height: 24, cornerRadius: 4)
                            SkeletonLoader(width: 40, height: 24, cornerRadius: 4)
                            SkeletonLoader(width: 30, height: 24, cornerRadius: 4)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
    
    private func randomBarWidth(for index: Int) -> CGFloat {
        let widths: [CGFloat] = [0.9, 0.75, 0.65, 0.55, 0.5, 0.45, 0.4, 0.35, 0.3, 0.25, 0.2, 0.15]
        return widths[index % widths.count]
    }
}

// MARK: - Calendar Day Skeleton View

struct CalendarDaySkeletonView: View {
    private let hourHeight: CGFloat = 52
    private let timeColWidth: CGFloat = 56
    private let sidebarWidth: CGFloat = 240
    
    var body: some View {
        HStack(spacing: 0) {
            // Timeline area
            VStack(spacing: 0) {
                // Day header skeleton
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 4) {
                        SkeletonLoader(width: 40, height: 34, cornerRadius: 4)
                        SkeletonLoader(width: 60, height: 12)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        SkeletonLoader(width: 100, height: 12)
                        SkeletonLoader(width: 60, height: 14)
                    }
                    .padding(.top, 6)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                Rectangle()
                    .fill(BrutalTheme.border.opacity(0.3))
                    .frame(height: 0.5)
                
                // Timeline grid skeleton
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { hour in
                            HStack(alignment: .top, spacing: 0) {
                                // Time label
                                SkeletonLoader(width: 30, height: 10)
                                    .frame(width: timeColWidth - 8, alignment: .trailing)
                                    .padding(.trailing, 8)
                                
                                // Hour row with potential blocks
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(BrutalTheme.border.opacity(0.1))
                                        .frame(height: 0.5)
                                    
                                    // Random blocks for visual effect
                                    if [8, 9, 10, 14, 15, 16, 20].contains(hour) {
                                        SkeletonLoader(
                                            width: .random(in: 100...200),
                                            height: hourHeight - 8,
                                            cornerRadius: 4
                                        )
                                        .padding(.top, 4)
                                        .padding(.leading, 4)
                                    }
                                }
                                .frame(height: hourHeight)
                            }
                        }
                    }
                }
            }
            
            Rectangle()
                .fill(BrutalTheme.border.opacity(0.3))
                .frame(width: 0.5)
            
            // Sidebar skeleton
            VStack(alignment: .leading, spacing: 12) {
                // Stats section
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonLoader(width: 80, height: 10)
                    SkeletonLoader(width: 60, height: 20)
                }
                .padding(.bottom, 8)
                
                Rectangle()
                    .fill(BrutalTheme.border.opacity(0.3))
                    .frame(height: 0.5)
                
                // App list skeleton
                SkeletonLoader(width: 100, height: 10)
                
                ForEach(0..<8, id: \.self) { _ in
                    HStack(spacing: 8) {
                        SkeletonLoader(width: 10, height: 10, cornerRadius: 2)
                        SkeletonLoader(width: .random(in: 60...120), height: 11)
                        Spacer()
                        SkeletonLoader(width: 40, height: 10)
                    }
                    .padding(.vertical, 4)
                }
                
                Spacer()
            }
            .padding(12)
            .frame(width: sidebarWidth)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Calendar Week Skeleton View

struct CalendarWeekSkeletonView: View {
    private let hourHeight: CGFloat = 48
    private let dayHeaderHeight: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 0) {
            // Week header with day names
            HStack(spacing: 0) {
                // Time column spacer
                Color.clear.frame(width: 56)
                
                ForEach(0..<7, id: \.self) { _ in
                    VStack(spacing: 4) {
                        SkeletonLoader(width: 30, height: 10)
                        SkeletonLoader(width: 24, height: 24, cornerRadius: 12)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
            .frame(height: dayHeaderHeight)
            
            Rectangle()
                .fill(BrutalTheme.border.opacity(0.3))
                .frame(height: 0.5)
            
            // Timeline grid
            ScrollView {
                HStack(alignment: .top, spacing: 0) {
                    // Time labels
                    VStack(spacing: 0) {
                        ForEach(0..<24, id: \.self) { _ in
                            SkeletonLoader(width: 30, height: 10)
                                .frame(width: 48, height: hourHeight, alignment: .trailing)
                                .padding(.trailing, 8)
                        }
                    }
                    
                    // Day columns
                    ForEach(0..<7, id: \.self) { dayIndex in
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                ZStack(alignment: .topLeading) {
                                    Rectangle()
                                        .fill(BrutalTheme.border.opacity(0.1))
                                        .frame(height: 0.5)
                                    
                                    // Random blocks
                                    if (dayIndex + hour) % 5 == 0 {
                                        SkeletonLoader(
                                            width: nil,
                                            height: hourHeight - 6,
                                            cornerRadius: 3
                                        )
                                        .padding(.horizontal, 2)
                                        .padding(.top, 3)
                                    }
                                }
                                .frame(height: hourHeight)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        
                        if dayIndex < 6 {
                            Rectangle()
                                .fill(BrutalTheme.border.opacity(0.2))
                                .frame(width: 0.5)
                        }
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Calendar Month Skeleton View

struct CalendarMonthSkeletonView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Weekday header
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(LocalizedStringKey(day))
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            
            Rectangle()
                .fill(BrutalTheme.border.opacity(0.3))
                .frame(height: 0.5)
            
            // Calendar grid (6 weeks)
            VStack(spacing: 0) {
                ForEach(0..<6, id: \.self) { week in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { day in
                            VStack(alignment: .leading, spacing: 4) {
                                SkeletonLoader(width: 20, height: 14, cornerRadius: 2)
                                    .padding(.top, 6)
                                    .padding(.leading, 6)
                                
                                if (week + day) % 3 != 0 {
                                    SkeletonLoader(width: 40, height: 8)
                                        .padding(.leading, 6)
                                }
                                
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(
                                Rectangle()
                                    .fill(BrutalTheme.border.opacity(0.1))
                                    .frame(width: 0.5),
                                alignment: .trailing
                            )
                            .overlay(
                                Rectangle()
                                    .fill(BrutalTheme.border.opacity(0.1))
                                    .frame(height: 0.5),
                                alignment: .bottom
                            )
                        }
                    }
                    .frame(height: 80)
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

// MARK: - Heatmap Skeleton View

struct HeatmapSkeletonView: View {
    private let weekdayLabels = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    private let cellSize: CGFloat = 32
    private let cellSpacing: CGFloat = 3
    private let labelWidth: CGFloat = 36
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Preset controls skeleton
            HStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    SkeletonLoader(width: 60, height: 30, cornerRadius: 6)
                }
                Spacer()
            }
            
            HStack(alignment: .top, spacing: 20) {
                // Main heatmap skeleton
                VStack(alignment: .leading, spacing: 16) {
                    GlassCard {
                        VStack(alignment: .leading, spacing: cellSpacing) {
                            // Hour header
                            HStack(spacing: cellSpacing) {
                                Text("")
                                    .frame(width: labelWidth)
                                
                                ForEach(0..<24, id: \.self) { hour in
                                    if hour % 3 == 0 {
                                        SkeletonLoader(width: cellSize - 8, height: 8)
                                            .frame(width: cellSize)
                                    } else {
                                        Color.clear.frame(width: cellSize, height: 8)
                                    }
                                }
                            }
                            
                            // Grid rows
                            ForEach(0..<7, id: \.self) { weekday in
                                HStack(spacing: cellSpacing) {
                                    Text(weekdayLabels[weekday])
                                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                        .foregroundColor(BrutalTheme.textTertiary)
                                        .frame(width: labelWidth, alignment: .leading)
                                    
                                    ForEach(0..<24, id: \.self) { hour in
                                        SkeletonLoader(
                                            width: cellSize,
                                            height: cellSize,
                                            cornerRadius: 4
                                        )
                                    }
                                }
                            }
                        }
                    }
                    
                    // Color legend skeleton
                    HStack(spacing: 8) {
                        SkeletonLoader(width: 30, height: 10)
                        ForEach(0..<6, id: \.self) { _ in
                            SkeletonLoader(width: 16, height: 12, cornerRadius: 3)
                        }
                        SkeletonLoader(width: 30, height: 10)
                        Spacer()
                    }
                }
            }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.98)))
    }
}

#Preview {
    VStack(spacing: 20) {
        WebHistorySkeletonView()
    }
    .padding()
    .frame(width: 800, height: 600)
}
#endif
