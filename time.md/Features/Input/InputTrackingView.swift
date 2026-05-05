import Charts
import SwiftUI

/// Top-level dashboard view for opt-in keystroke + cursor tracking. Three
/// tabs: cursor heatmap, top typed words, typing intensity timeline.
struct InputTrackingView: View {
    let filters: GlobalFilterStore

    @AppStorage(InputEventTracker.enabledKey) private var inputTrackingEnabled: Bool = false
    @AppStorage(InputEventTracker.keystrokeLevelKey) private var keystrokeLevelRaw: String = ""
    @AppStorage(InputEventTracker.cursorLevelKey) private var cursorLevelRaw: String = ""
    @State private var selectedTab: Tab = .heatmap

    private var keystrokeLevel: KeystrokeTrackingLevel {
        KeystrokeTrackingLevel(rawValue: keystrokeLevelRaw) ?? InputEventTracker.resolveKeystrokeLevel()
    }

    private var cursorLevel: CursorTrackingLevel {
        CursorTrackingLevel(rawValue: cursorLevelRaw) ?? InputEventTracker.resolveCursorLevel()
    }

    enum Tab: String, CaseIterable, Identifiable {
        case heatmap = "Cursor Heatmap"
        case words = "Top Typed"
        case intensity = "Intensity"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
            HStack(alignment: .firstTextBaseline) {
                Text("Input Tracking")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)

                Spacer()

                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: BrutalTheme.sectionSpacing) {
                    if !inputTrackingEnabled {
                        disabledHero
                    } else {
                        switch selectedTab {
                        case .heatmap:
                            if cursorLevel.isOff {
                                streamOffMessage(streamName: "Cursor", instruction: "Set Cursor to \"Heatmap only\" or higher in Settings → Input Tracking.")
                            } else {
                                CursorHeatmapView(filters: filters)
                            }
                        case .words:
                            TopTypedWordsView(filters: filters, keystrokeLevel: keystrokeLevel)
                        case .intensity:
                            if keystrokeLevel.isOff {
                                streamOffMessage(streamName: "Keystroke", instruction: "Set Keystrokes to \"Activity only\" or higher in Settings → Input Tracking.")
                            } else {
                                TypingIntensityTimelineView(filters: filters)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
        }
    }

    private func streamOffMessage(streamName: String, instruction: String) -> some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(streamName) tracking is off")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(BrutalTheme.textPrimary)
                Text(instruction)
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineSpacing(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var disabledHero: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "keyboard.badge.eye")
                        .font(.system(size: 24))
                        .foregroundColor(BrutalTheme.accent)
                    Text("Input tracking is off")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(BrutalTheme.textPrimary)
                }
                Text("Enable in Settings → Input Tracking. Off by default — captures keystrokes and mouse events while time.md is running. All data stays local.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .lineSpacing(3)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Cursor Heatmap

struct CursorHeatmapView: View {
    let filters: GlobalFilterStore
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var bins: [CursorHeatmapBin] = []
    @State private var clicks: [ClickLocation] = []
    @State private var availableScreens: [Int] = []
    @State private var availableBundleIDs: [String] = []
    @State private var selectedScreenID: Int = 0
    @State private var selectedBundleID: String? = nil
    @State private var isLoading: Bool = true
    @State private var errorMessage: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                headerRow
                Text("Where your cursor spent its time. Each square is a 32-pixel grid bin; brighter = more samples. Red dots = click locations.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else if bins.isEmpty {
                    emptyState
                } else {
                    HeatmapCanvas(
                        bins: bins.filter { $0.screenID == selectedScreenID },
                        clicks: clicks.filter { $0.screenID == selectedScreenID },
                        screenFrame: Self.screenFrame(for: selectedScreenID)
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: filterTaskID) {
            await load()
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("CURSOR HEATMAP")
                .font(BrutalTheme.headingFont)
                .foregroundColor(BrutalTheme.textSecondary)
                .tracking(1.5)
            Spacer()

            if !availableBundleIDs.isEmpty {
                Picker("App", selection: $selectedBundleID) {
                    Text("All apps").tag(String?.none)
                    ForEach(availableBundleIDs, id: \.self) { bundle in
                        Text(Self.displayName(for: bundle)).tag(String?.some(bundle))
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 200)
            }

            if availableScreens.count > 1 {
                Picker("Screen", selection: $selectedScreenID) {
                    ForEach(availableScreens, id: \.self) { id in
                        Text("Screen \(id + 1)").tag(id)
                    }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: 140)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "cursorarrow.motionlines")
                .font(.system(size: 40, weight: .thin))
                .foregroundColor(BrutalTheme.textTertiary)
            Text("No cursor data yet for this range.")
                .font(BrutalTheme.bodyMono)
                .foregroundColor(BrutalTheme.textTertiary)
            Text("Move your cursor — data appears within ~1 minute.")
                .font(BrutalTheme.captionMono)
                .foregroundColor(BrutalTheme.textTertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 360)
    }

    private var filterTaskID: String {
        "\(filters.startDate.timeIntervalSince1970)-\(filters.endDate.timeIntervalSince1970)-\(filters.refreshToken)-\(selectedBundleID ?? "")"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            async let screensTask = appEnvironment.dataService.fetchInputTrackingScreenIDs(
                startDate: filters.startDate,
                endDate: filters.endDate
            )
            async let bundlesTask = appEnvironment.dataService.fetchInputTrackingBundleIDs(
                startDate: filters.startDate,
                endDate: filters.endDate
            )
            async let binsTask = appEnvironment.dataService.fetchCursorHeatmap(
                startDate: filters.startDate,
                endDate: filters.endDate,
                screenID: nil,
                bundleID: selectedBundleID
            )
            async let clicksTask = appEnvironment.dataService.fetchClickLocations(
                startDate: filters.startDate,
                endDate: filters.endDate,
                screenID: nil,
                bundleID: selectedBundleID,
                limit: 5000
            )

            let screens = try await screensTask
            let bundles = try await bundlesTask
            let nextBins = try await binsTask
            let nextClicks = try await clicksTask

            await MainActor.run {
                self.availableScreens = screens.isEmpty ? [0] : screens
                self.availableBundleIDs = bundles
                if !self.availableScreens.contains(self.selectedScreenID) {
                    self.selectedScreenID = self.availableScreens.first ?? 0
                }
                self.bins = nextBins
                self.clicks = nextClicks
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = ScreenTimeDataError.message(for: error)
                self.isLoading = false
            }
        }
    }

    /// Resolves the CG-coord rectangle for the requested screen by walking
    /// `NSScreen.screens` and reading the underlying `CGDirectDisplayID`. Falls
    /// back to nil if the screen is no longer attached — `HeatmapCanvas` then
    /// uses a bounding-box layout.
    static func screenFrame(for screenID: Int) -> CGRect? {
        guard screenID < NSScreen.screens.count else { return nil }
        let screen = NSScreen.screens[screenID]
        guard let nsNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        let displayID = CGDirectDisplayID(nsNumber.uint32Value)
        return CGDisplayBounds(displayID)
    }

    private static func displayName(for bundleID: String) -> String {
        if let last = bundleID.split(separator: ".").last, !last.isEmpty {
            return String(last)
        }
        return bundleID
    }
}

private struct HeatmapCanvas: View {
    let bins: [CursorHeatmapBin]
    let clicks: [ClickLocation]
    /// CG-coord rectangle of the actual display. When nil, the canvas falls
    /// back to a bounding box around the bin data (legacy behavior).
    let screenFrame: CGRect?

    private static let cellSize: Double = 32

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                let frame = screenFrame ?? Self.boundingFrame(bins: bins)
                guard frame.width > 0, frame.height > 0 else { return }

                // Letterbox / pillarbox to preserve the screen's aspect ratio.
                let aspect = frame.width / frame.height
                let availAspect = size.width / size.height
                let canvasSize: CGSize
                if availAspect > aspect {
                    canvasSize = CGSize(width: size.height * aspect, height: size.height)
                } else {
                    canvasSize = CGSize(width: size.width, height: size.width / aspect)
                }
                let xOffset = (size.width - canvasSize.width) / 2
                let yOffset = (size.height - canvasSize.height) / 2
                let scaleX = canvasSize.width / frame.width
                let scaleY = canvasSize.height / frame.height

                // Screen background + border so the user can see where the
                // monitor edges are even if the cursor never visited the corners.
                let screenRect = CGRect(x: xOffset, y: yOffset, width: canvasSize.width, height: canvasSize.height)
                context.fill(Path(screenRect), with: .color(Color.black.opacity(0.22)))
                context.stroke(Path(screenRect), with: .color(Color.gray.opacity(0.4)), lineWidth: 1)

                // Heatmap cells.
                let maxSamples = bins.map(\.samples).max() ?? 1
                let cellSize = Self.cellSize
                let originBinX = Int(floor(frame.minX / cellSize))
                let originBinY = Int(floor(frame.minY / cellSize))
                let cellW = cellSize * scaleX
                let cellH = cellSize * scaleY

                for bin in bins {
                    let localBinX = bin.binX - originBinX
                    let localBinY = bin.binY - originBinY
                    if localBinX < 0 || localBinY < 0 { continue }
                    let intensity = pow(Double(bin.samples) / Double(maxSamples), 0.5)
                    let rect = CGRect(
                        x: xOffset + Double(localBinX) * cellW,
                        y: yOffset + Double(localBinY) * cellH,
                        width: cellW,
                        height: cellH
                    )
                    context.fill(
                        Path(rect),
                        with: .color(Color(red: 0.0, green: 0.6, blue: 1.0).opacity(0.15 + 0.85 * intensity))
                    )
                }

                // Click dots overlay.
                let radius: CGFloat = 3
                for click in clicks {
                    let localX = click.x - frame.minX
                    let localY = click.y - frame.minY
                    if localX < 0 || localY < 0 || localX > frame.width || localY > frame.height {
                        continue
                    }
                    let dotX = xOffset + localX * scaleX
                    let dotY = yOffset + localY * scaleY
                    let dotRect = CGRect(x: dotX - radius, y: dotY - radius, width: radius * 2, height: radius * 2)
                    let dot = Path(ellipseIn: dotRect)
                    context.fill(dot, with: .color(Color.red.opacity(0.45)))
                    context.stroke(dot, with: .color(Color.red.opacity(0.85)), lineWidth: 0.5)
                }
            }
        }
    }

    /// Tight rectangle around the binned cursor positions in CG coords. Used
    /// only as a fallback when `screenFrame` is unavailable.
    private static func boundingFrame(bins: [CursorHeatmapBin]) -> CGRect {
        guard !bins.isEmpty else { return CGRect(x: 0, y: 0, width: 1920, height: 1080) }
        let minBinX = bins.map(\.binX).min() ?? 0
        let maxBinX = bins.map(\.binX).max() ?? 0
        let minBinY = bins.map(\.binY).min() ?? 0
        let maxBinY = bins.map(\.binY).max() ?? 0
        let minX = Double(minBinX) * cellSize
        let maxX = Double(maxBinX + 1) * cellSize
        let minY = Double(minBinY) * cellSize
        let maxY = Double(maxBinY + 1) * cellSize
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Top Typed Words / Keys

struct TopTypedWordsView: View {
    let filters: GlobalFilterStore
    let keystrokeLevel: KeystrokeTrackingLevel
    @Environment(\.appEnvironment) private var appEnvironment

    private var captureContent: Bool { keystrokeLevel == .fullContent }
    private var hasKeyCodes: Bool { keystrokeLevel.capturesKeyCode }

    enum Mode: String, CaseIterable, Identifiable {
        case words = "Words"
        case keys = "Keys"
        var id: String { rawValue }
    }

    @State private var mode: Mode = .words
    @State private var words: [TypedWordRow] = []
    @State private var keys: [TypedKeyRow] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var redacted: Bool = false

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MOST TYPED")
                        .font(BrutalTheme.headingFont)
                        .foregroundColor(BrutalTheme.textSecondary)
                        .tracking(1.5)
                    Spacer()
                    Picker("", selection: $mode) {
                        ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }

                if mode == .words {
                    HStack(spacing: 6) {
                        Image(systemName: redacted ? "eye.slash.fill" : "eye.fill")
                        Toggle("Redact", isOn: $redacted)
                            .toggleStyle(.switch)
                            .tint(.orange)
                            .controlSize(.mini)
                            .labelsHidden()
                        Text("Redact words")
                            .font(BrutalTheme.captionMono)
                            .foregroundColor(BrutalTheme.textTertiary)
                        Spacer()
                    }
                }

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 200)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(.orange)
                } else {
                    Group {
                        switch mode {
                        case .words:
                            if !captureContent {
                                wordsDisabledNote
                            } else if words.isEmpty {
                                emptyState
                            } else {
                                wordsTable
                            }
                        case .keys:
                            if !hasKeyCodes {
                                keysDisabledNote
                            } else if keys.isEmpty {
                                emptyState
                            } else {
                                keysTable
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: filterTaskID) {
            await load()
        }
        .onChange(of: mode) { _, _ in
            Task { await load() }
        }
    }

    private var wordsDisabledNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Word capture requires \"Full content\".")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.textPrimary)
            Text("Set Keystrokes to \"Full content\" in Settings → Input Tracking to populate this view. Counts and key distribution work at lower levels.")
                .font(BrutalTheme.bodyMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 16)
    }

    private var keysDisabledNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Key codes aren't being captured.")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(BrutalTheme.textPrimary)
            Text("Set Keystrokes to \"Per-key counts\" or higher in Settings → Input Tracking. \"Activity only\" records timestamps but not which key was pressed.")
                .font(BrutalTheme.bodyMono)
                .foregroundColor(BrutalTheme.textSecondary)
                .lineSpacing(3)
        }
        .padding(.vertical, 16)
    }

    private var wordsTable: some View {
        VStack(spacing: 4) {
            ForEach(words.prefix(50)) { row in
                HStack {
                    Text(redacted ? String(repeating: "•", count: row.word.count) : row.word)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Spacer()
                    Text("\(row.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrutalTheme.surface.opacity(0.4))
                )
            }
        }
    }

    private var keysTable: some View {
        VStack(spacing: 4) {
            ForEach(keys.prefix(50)) { row in
                HStack {
                    Text(row.label)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.textPrimary)
                    Spacer()
                    Text("\(row.count)")
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(BrutalTheme.accent)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(BrutalTheme.surface.opacity(0.4))
                )
            }
        }
    }

    private var emptyState: some View {
        Text("No data for this range yet.")
            .font(BrutalTheme.bodyMono)
            .foregroundColor(BrutalTheme.textTertiary)
            .frame(maxWidth: .infinity, minHeight: 200)
    }

    private var filterTaskID: String {
        "\(mode.rawValue)-\(filters.startDate.timeIntervalSince1970)-\(filters.endDate.timeIntervalSince1970)-\(filters.refreshToken)"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            switch mode {
            case .words:
                let result = try await appEnvironment.dataService.fetchTopTypedWords(
                    startDate: filters.startDate,
                    endDate: filters.endDate,
                    bundleID: nil,
                    limit: 50
                )
                await MainActor.run {
                    self.words = result
                    self.isLoading = false
                }
            case .keys:
                let result = try await appEnvironment.dataService.fetchTopTypedKeys(
                    startDate: filters.startDate,
                    endDate: filters.endDate,
                    limit: 50
                )
                await MainActor.run {
                    self.keys = result
                    self.isLoading = false
                }
            }
        } catch {
            await MainActor.run {
                self.errorMessage = ScreenTimeDataError.message(for: error)
                self.isLoading = false
            }
        }
    }
}

// MARK: - Typing Intensity Timeline

struct TypingIntensityTimelineView: View {
    let filters: GlobalFilterStore
    @Environment(\.appEnvironment) private var appEnvironment

    @State private var points: [IntensityPoint] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        GlassCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("TYPING INTENSITY")
                    .font(BrutalTheme.headingFont)
                    .foregroundColor(BrutalTheme.textSecondary)
                    .tracking(1.5)

                Text("Keystrokes per \(granularity == .minute ? "minute" : "hour") in this range. Counts only — no characters.")
                    .font(BrutalTheme.bodyMono)
                    .foregroundColor(BrutalTheme.textSecondary)

                if isLoading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 280)
                } else if let errorMessage {
                    Text(errorMessage)
                        .font(BrutalTheme.captionMono)
                        .foregroundColor(.orange)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else if points.isEmpty {
                    Text("No keystroke data yet.")
                        .font(BrutalTheme.bodyMono)
                        .foregroundColor(BrutalTheme.textTertiary)
                        .frame(maxWidth: .infinity, minHeight: 280)
                } else {
                    Chart(points) { point in
                        BarMark(
                            x: .value("Time", point.date),
                            y: .value("Keystrokes", point.count)
                        )
                        .foregroundStyle(BrutalTheme.accent)
                    }
                    .frame(minHeight: 280)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: filterTaskID) {
            await load()
        }
    }

    private var granularity: IntensityGranularity {
        // Day-scale ranges → minute granularity. Anything wider → hour.
        let span = filters.endDate.timeIntervalSince(filters.startDate)
        return span <= 86_400 ? .minute : .hour
    }

    private var filterTaskID: String {
        "\(filters.startDate.timeIntervalSince1970)-\(filters.endDate.timeIntervalSince1970)-\(filters.refreshToken)"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await appEnvironment.dataService.fetchTypingIntensity(
                startDate: filters.startDate,
                endDate: filters.endDate,
                granularity: granularity
            )
            await MainActor.run {
                self.points = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = ScreenTimeDataError.message(for: error)
                self.isLoading = false
            }
        }
    }
}
