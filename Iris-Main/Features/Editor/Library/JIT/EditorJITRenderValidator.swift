import Foundation

enum EditorJITRenderValidator {
    static func validate(_ state: EditorJITRenderState) -> (EditorJITRenderState, EditorJITValidationResult) {
        var warnings: [String] = []
        var errors: [String] = []
        var playback = state.playback
        var timeline = state.timeline
        var chromePlan = state.chromePlan

        if state.resolutionCategory == .unsupported {
            errors.append("Recipe category is unsupported — no renderable layout.")
        }

        if state.resolutionCategory == .ambiguous {
            warnings.append("Ambiguous request — showcase renders a clarification-friendly default.")
        }

        playback = sanitizeComponent(playback, slot: "playback", warnings: &warnings, errors: &errors)
        timeline = sanitizeComponent(timeline, slot: "timeline", warnings: &warnings, errors: &errors)
        chromePlan = sanitizeChromePlan(chromePlan, warnings: &warnings, errors: &errors)

        if !playback.isVisible && !timeline.isVisible {
            errors.append("At least one of playback or timeline must remain visible.")
        }

        if chromePlan.visibleTiers.isEmpty {
            errors.append("Bottom chrome must expose at least one tier (typically the dock).")
        }

        let isValid = errors.isEmpty && state.resolutionCategory != .unsupported

        let validated = EditorJITRenderState(
            id: state.id,
            title: state.title,
            promptExample: state.promptExample,
            resolutionCategory: state.resolutionCategory,
            playback: playback,
            timeline: timeline,
            chromePlan: chromePlan,
            validationWarnings: warnings,
            isValid: isValid
        )

        let result = EditorJITValidationResult(
            isValid: isValid,
            warnings: warnings,
            errors: errors
        )

        return (validated, result)
    }

    private static func sanitizeComponent(
        _ component: EditorJITComponentState,
        slot: String,
        warnings: inout [String],
        errors: inout [String]
    ) -> EditorJITComponentState {
        guard component.isVisible else { return component }

        guard let entry = EditorComponentRegistry.entry(for: component.componentId) else {
            errors.append("\(slot): unknown component '\(component.componentId.rawValue)'.")
            return .hidden(component.componentId)
        }

        if entry.category != slotCategory(for: slot), !allowsCrossCategory(component.componentId, slot: slot) {
            warnings.append("\(slot): '\(component.componentId.rawValue)' is not the default \(slot) primitive.")
        }

        var size = component.size
        if !entry.supportedSizes.contains(size) {
            let fallback = entry.supportedSizes.contains(.standard)
                ? EditorComponentSize.standard
                : entry.supportedSizes.sorted(by: { $0.rawValue < $1.rawValue }).first ?? .standard
            warnings.append("\(slot): size '\(size.rawValue)' unsupported — using '\(fallback.rawValue)'.")
            size = fallback
        }

        return EditorJITComponentState(
            componentId: component.componentId,
            size: size,
            isVisible: true
        )
    }

    private static func slotCategory(for slot: String) -> EditorComponentCategory {
        switch slot {
        case "playback": return .playback
        case "timeline": return .timeline
        default: return .chrome
        }
    }

    private static func allowsCrossCategory(_ componentId: EditorComponentID, slot: String) -> Bool {
        switch slot {
        case "playback":
            return componentId.rawValue.hasPrefix("playback.")
        case "timeline":
            return componentId.rawValue.hasPrefix("timeline.")
        default:
            return false
        }
    }

    private static func sanitizeChromePlan(
        _ plan: EditorBottomChromePlan,
        warnings: inout [String],
        errors: inout [String]
    ) -> EditorBottomChromePlan {
        var plan = plan

        if plan.activeParameterGroupId != nil,
           !plan.parameterGroups.contains(where: { $0.id == plan.activeParameterGroupId }) {
            warnings.append("Active parameter group missing — falling back to first group.")
            plan.activeParameterGroupId = plan.parameterGroups.first?.id
        }

        if plan.showsDock == false && plan.visibleTiers.isEmpty {
            errors.append("Chrome plan hides the dock and all tiers.")
        }

        return plan
    }
}
