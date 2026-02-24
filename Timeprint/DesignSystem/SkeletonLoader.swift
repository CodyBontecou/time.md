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

#Preview {
    VStack(spacing: 20) {
        WebHistorySkeletonView()
    }
    .padding()
    .frame(width: 800, height: 600)
}
#endif
