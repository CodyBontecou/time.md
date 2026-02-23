import Foundation

struct FeatureFlags {
    var enableInspector: Bool
    var enableAdvancedInteractions: Bool
    var enableExperimentalCategoryMapping: Bool

    static let `default` = FeatureFlags(
        enableInspector: true,
        enableAdvancedInteractions: true,
        enableExperimentalCategoryMapping: false
    )
}
