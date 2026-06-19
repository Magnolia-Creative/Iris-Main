import Foundation

// MARK: - Resolution

enum EditorJITResolutionCategory: String, Codable, CaseIterable, Identifiable {
    case direct
    case contextual
    case workspace
    case ambiguous
    case unsupported

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .direct: return "Direct"
        case .contextual: return "Contextual"
        case .workspace: return "Workspace"
        case .ambiguous: return "Ambiguous"
        case .unsupported: return "Unsupported"
        }
    }
}

// MARK: - Component placement

struct EditorJITComponentState: Equatable {
    let componentId: EditorComponentID
    var size: EditorComponentSize
    var isVisible: Bool

    static func hidden(_ componentId: EditorComponentID) -> EditorJITComponentState {
        EditorJITComponentState(componentId: componentId, size: .standard, isVisible: false)
    }

    static func visible(
        _ componentId: EditorComponentID,
        size: EditorComponentSize = .standard
    ) -> EditorJITComponentState {
        EditorJITComponentState(componentId: componentId, size: size, isVisible: true)
    }
}

// MARK: - Render state

struct EditorJITRenderState: Equatable, Identifiable {
    let id: String
    let title: String
    let promptExample: String
    let resolutionCategory: EditorJITResolutionCategory
    var playback: EditorJITComponentState
    var timeline: EditorJITComponentState
    var chromePlan: EditorBottomChromePlan
    var validationWarnings: [String]
    var isValid: Bool

    var summaryLines: [String] {
        var lines: [String] = []
        if playback.isVisible {
            lines.append("Playback · \(playback.componentId.rawValue) · \(playback.size.rawValue)")
        } else {
            lines.append("Playback · hidden")
        }
        if timeline.isVisible {
            lines.append("Timeline · \(timeline.componentId.rawValue) · \(timeline.size.rawValue)")
        } else {
            lines.append("Timeline · hidden")
        }
        lines.append("Chrome tiers · \(chromePlan.visibleTiers.map(\.displayTitle).joined(separator: ", "))")
        return lines
    }
}

// MARK: - Validation

struct EditorJITValidationResult: Equatable {
    let isValid: Bool
    let warnings: [String]
    let errors: [String]

    static let valid = EditorJITValidationResult(isValid: true, warnings: [], errors: [])
}

// MARK: - Recipe

struct EditorJITRecipe: Identifiable, Equatable {
    let id: String
    let title: String
    let promptExample: String
    let resolutionCategory: EditorJITResolutionCategory
    let playback: EditorJITComponentState
    let timeline: EditorJITComponentState
    let chromePlan: EditorBottomChromePlan

    func makeRawState() -> EditorJITRenderState {
        EditorJITRenderState(
            id: id,
            title: title,
            promptExample: promptExample,
            resolutionCategory: resolutionCategory,
            playback: playback,
            timeline: timeline,
            chromePlan: chromePlan,
            validationWarnings: [],
            isValid: true
        )
    }
}

// MARK: - Transitions

enum EditorJITTransitionStyle: Equatable {
    case persist
    case resize
    case enter
    case exit
    case replace
}

struct EditorJITTransitionPlan: Equatable, Identifiable {
    let componentId: EditorComponentID
    let style: EditorJITTransitionStyle

    var id: String { componentId.rawValue }
}

// MARK: - Tier display

private extension EditorBottomChromeTier {
    var displayTitle: String {
        switch self {
        case .spatialParameters: return "spatial"
        case .parameters: return "parameters"
        case .actions: return "actions"
        case .dock: return "dock"
        }
    }
}
