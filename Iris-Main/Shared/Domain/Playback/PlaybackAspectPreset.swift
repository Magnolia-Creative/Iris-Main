import Foundation

/// Editor / export canvas aspect presets (width:height).
enum PlaybackAspectPreset: String, CaseIterable, Identifiable {
    case ratio16x9
    case ratio9x16
    case ratio1x1
    case ratio4x5
    case ratio3x4
    case ratio4x3
    case ratio5x4

    var id: String { rawValue }

    var label: String {
        switch self {
        case .ratio16x9: return "16:9"
        case .ratio9x16: return "9:16"
        case .ratio1x1: return "1:1"
        case .ratio4x5: return "4:5"
        case .ratio3x4: return "3:4"
        case .ratio4x3: return "4:3"
        case .ratio5x4: return "5:4"
        }
    }

    var outputAspect: OutputAspectRatio {
        switch self {
        case .ratio16x9: return OutputAspectRatio(width: 16, height: 9)
        case .ratio9x16: return OutputAspectRatio(width: 9, height: 16)
        case .ratio1x1: return OutputAspectRatio(width: 1, height: 1)
        case .ratio4x5: return OutputAspectRatio(width: 4, height: 5)
        case .ratio3x4: return OutputAspectRatio(width: 3, height: 4)
        case .ratio4x3: return OutputAspectRatio(width: 4, height: 3)
        case .ratio5x4: return OutputAspectRatio(width: 5, height: 4)
        }
    }

    static var horizontalPresets: [PlaybackAspectPreset] {
        [.ratio16x9, .ratio4x3, .ratio5x4, .ratio1x1]
    }

    static var verticalPresets: [PlaybackAspectPreset] {
        [.ratio9x16, .ratio4x5, .ratio3x4, .ratio1x1]
    }
}
