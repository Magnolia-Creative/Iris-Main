import Foundation

/// Keys from `ClipColorFilterPatch` / `ClipColorFilter` used by prompt color review and sliders.
enum ClipColorFilterPromptField: String, CaseIterable {
    case temperature
    case tint
    case exposure
    case brightness
    case contrast
    case saturation
    case highlights
    case shadows

    init?(patchKey: String) {
        self.init(rawValue: patchKey)
    }

    var displayTitle: String {
        switch self {
        case .temperature: return "Temperature"
        case .tint: return "Tint"
        case .exposure: return "Exposure"
        case .brightness: return "Brightness"
        case .contrast: return "Contrast"
        case .saturation: return "Saturation"
        case .highlights: return "Highlights"
        case .shadows: return "Shadows"
        }
    }

    var sliderRange: ClosedRange<Float> {
        switch self {
        case .exposure:
            let bound = ClipColorFilter.exposureRange.upperBound / 2
            return -bound...bound
        case .brightness:
            let bound = ClipColorFilter.normalizedRange.upperBound / 2
            return -bound...bound
        default:
            return ClipColorFilter.normalizedRange
        }
    }

    func floatValue(in filter: ClipColorFilter) -> Float {
        switch self {
        case .temperature: return filter.temperature
        case .tint: return filter.tint
        case .exposure: return filter.exposure
        case .brightness: return filter.brightness
        case .contrast: return filter.contrast
        case .saturation: return filter.saturation
        case .highlights: return filter.highlights
        case .shadows: return filter.shadows
        }
    }

    func set(_ value: Float, on filter: inout ClipColorFilter) {
        switch self {
        case .temperature: filter.temperature = value
        case .tint: filter.tint = value
        case .exposure: filter.exposure = value
        case .brightness: filter.brightness = value
        case .contrast: filter.contrast = value
        case .saturation: filter.saturation = value
        case .highlights: filter.highlights = value
        case .shadows: filter.shadows = value
        }
    }
}
