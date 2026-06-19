import Foundation

enum EditorJITRenderTransitionCoordinator {
    static func plan(from previous: EditorJITRenderState?, to next: EditorJITRenderState) -> [EditorJITTransitionPlan] {
        guard let previous else {
            return enterPlans(for: next)
        }

        var plans: [EditorJITTransitionPlan] = []

        plans.append(contentsOf: diffSlot(
            previous: previous.playback,
            next: next.playback
        ))
        plans.append(contentsOf: diffSlot(
            previous: previous.timeline,
            next: next.timeline
        ))

        if previous.chromePlan.visibleTiers != next.chromePlan.visibleTiers {
            plans.append(EditorJITTransitionPlan(componentId: "chrome.bottomStack", style: .replace))
        } else if previous.chromePlan.density != next.chromePlan.density {
            plans.append(EditorJITTransitionPlan(componentId: "chrome.bottomStack", style: .resize))
        }

        return plans
    }

    private static func enterPlans(for state: EditorJITRenderState) -> [EditorJITTransitionPlan] {
        var plans: [EditorJITTransitionPlan] = []
        if state.playback.isVisible {
            plans.append(EditorJITTransitionPlan(componentId: state.playback.componentId, style: .enter))
        }
        if state.timeline.isVisible {
            plans.append(EditorJITTransitionPlan(componentId: state.timeline.componentId, style: .enter))
        }
        if !state.chromePlan.visibleTiers.isEmpty {
            plans.append(EditorJITTransitionPlan(componentId: "chrome.bottomStack", style: .enter))
        }
        return plans
    }

    private static func diffSlot(
        previous: EditorJITComponentState,
        next: EditorJITComponentState
    ) -> [EditorJITTransitionPlan] {
        if previous.isVisible == next.isVisible {
            if !next.isVisible { return [] }
            if previous.componentId == next.componentId {
                if previous.size != next.size {
                    return [EditorJITTransitionPlan(componentId: next.componentId, style: .resize)]
                }
                return [EditorJITTransitionPlan(componentId: next.componentId, style: .persist)]
            }
            return [
                EditorJITTransitionPlan(componentId: previous.componentId, style: .exit),
                EditorJITTransitionPlan(componentId: next.componentId, style: .replace)
            ]
        }

        if next.isVisible {
            return [EditorJITTransitionPlan(componentId: next.componentId, style: .enter)]
        }
        return [EditorJITTransitionPlan(componentId: previous.componentId, style: .exit)]
    }
}
