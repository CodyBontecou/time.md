import Foundation

/// One bin in a cursor heatmap. `binX` / `binY` are 32-pixel grid coordinates
/// keyed off the absolute screen origin.
struct CursorHeatmapBin: Identifiable, Sendable {
    var id: String { "\(screenID)-\(binX)-\(binY)" }
    let screenID: Int
    let binX: Int
    let binY: Int
    let samples: Int
}

/// One row of the "top typed words" table. `word` is already lowercased and
/// normalized when stored by `InputAggregator`.
struct TypedWordRow: Identifiable, Sendable {
    var id: String { word }
    let word: String
    let count: Int
}

/// One row of the "top typed keys" table. `label` is a human-readable label
/// derived from `keyCode` (e.g. `Space`, `Return`, `A`).
struct TypedKeyRow: Identifiable, Sendable {
    var id: Int { keyCode }
    let keyCode: Int
    let label: String
    let count: Int
}

/// One sample on the typing intensity timeline. `count` is the number of
/// `keystroke_events` rows whose timestamp falls in the bucket.
struct IntensityPoint: Identifiable, Sendable {
    var id: Date { date }
    let date: Date
    let count: Int
}

/// Granularity for typing intensity charts.
enum IntensityGranularity: String, Sendable {
    case minute
    case hour
}

/// One click coordinate in absolute (CG global) screen coordinates.
struct ClickLocation: Sendable {
    let x: Double
    let y: Double
    let screenID: Int
}

/// One raw row from `keystroke_events`, used for export.
struct RawKeystrokeEvent: Sendable {
    let timestamp: Date
    let bundleID: String?
    let appName: String?
    let keyCode: Int
    let modifiers: Int64
    let char: String?
    let isWordBoundary: Bool
    let secureInput: Bool
}

/// One raw row from `mouse_events`, used for export.
struct RawMouseEvent: Sendable {
    let timestamp: Date
    let bundleID: String?
    let appName: String?
    /// 0=move 1=down 2=up 3=scroll 4=drag.
    let kind: Int
    let button: Int
    let x: Double
    let y: Double
    let screenID: Int
    let scrollDX: Double?
    let scrollDY: Double?
}
