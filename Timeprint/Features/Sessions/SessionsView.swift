import Charts
import SwiftUI

struct SessionsView: View {
    let filters: GlobalFilterStore

    @Environment(\.appEnvironment) private var appEnvironment
    @State private var buckets: [SessionBucket] = []
    @State private var loadError: Error?
    @State private var hoveredBucketLabel: String?
    @State private var selectedBucketLabel: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Session Distribution")
                .font(.largeTitle.bold())

            if let loadError {
                DataLoadErrorView(error: loadError)
            }

            GlassCard {
                VStack(alignment: .leading, spacing: 10) {
                    Chart(buckets) { bucket in
                        BarMark(
                            x: .value("Range", bucket.label),
                            y: .value("Sessions", bucket.sessionCount)
                        )
                        .foregroundStyle(barColor(for: bucket))
                    }
                    .chartOverlay { proxy in
                        GeometryReader { geometry in
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .onContinuousHover { phase in
                                    switch phase {
                                    case let .active(location):
                                        updateHover(locationX: location.x, proxy: proxy, geometry: geometry)
                                    case .ended:
                                        hoveredBucketLabel = nil
                                    }
                                }
                                .gesture(
                                    TapGesture()
                                        .onEnded {
                                            if let hoveredBucketLabel {
                                                if selectedBucketLabel == hoveredBucketLabel {
                                                    selectedBucketLabel = nil
                                                } else {
                                                    selectedBucketLabel = hoveredBucketLabel
                                                }
                                            }
                                        }
                                )
                        }
                    }
                    .frame(height: 300)

                    if let focused = focusedBucket {
                        Text("Focused bucket: \(focused.label) • \(focused.sessionCount) sessions")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Hover bars for details. Click to pin a bucket.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Button("Clear Bucket Focus") {
                            selectedBucketLabel = nil
                        }
                        .buttonStyle(.bordered)
                        .disabled(selectedBucketLabel == nil)

                        Spacer()
                    }
                }
            }

            Spacer()
        }
        .task(id: filters.rangeLabel + filters.granularity.rawValue) {
            await load()
        }
    }

    private var focusedBucket: SessionBucket? {
        if let selectedBucketLabel,
           let selected = buckets.first(where: { $0.label == selectedBucketLabel }) {
            return selected
        }

        if let hoveredBucketLabel,
           let hovered = buckets.first(where: { $0.label == hoveredBucketLabel }) {
            return hovered
        }

        return nil
    }

    private func barColor(for bucket: SessionBucket) -> AnyShapeStyle {
        if let selectedBucketLabel {
            if selectedBucketLabel == bucket.label {
                return AnyShapeStyle(.orange.gradient)
            }
            return AnyShapeStyle(.gray.opacity(0.35))
        }

        if let hoveredBucketLabel {
            if hoveredBucketLabel == bucket.label {
                return AnyShapeStyle(.orange.gradient)
            }
            return AnyShapeStyle(.orange.opacity(0.45))
        }

        return AnyShapeStyle(.orange.gradient)
    }

    private func updateHover(locationX: CGFloat, proxy: ChartProxy, geometry: GeometryProxy) {
        guard let plotFrame = proxy.plotFrame else {
            hoveredBucketLabel = nil
            return
        }

        let plotRect = geometry[plotFrame]
        let relativeX = locationX - plotRect.origin.x

        guard relativeX >= 0, relativeX <= plotRect.width,
              let label: String = proxy.value(atX: relativeX) else {
            hoveredBucketLabel = nil
            return
        }

        hoveredBucketLabel = label
    }

    private func load() async {
        do {
            loadError = nil
            buckets = try await appEnvironment.dataService.fetchSessionBuckets(filters: filters.snapshot)
        } catch {
            loadError = error
            buckets = []
        }
    }
}
