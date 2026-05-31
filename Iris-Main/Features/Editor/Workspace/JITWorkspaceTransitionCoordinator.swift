import Foundation

enum JITWorkspaceTransitionStyle: Equatable {
    case persist
    case resize
    case replace
    case enter
    case exit
}

struct JITWorkspaceTransitionPlan: Equatable {
    let widgetId: String
    let style: JITWorkspaceTransitionStyle
}

enum JITWorkspaceTransitionCoordinator {
    static func plan(
        from previous: UIWorkspacePlan?,
        to next: UIWorkspacePlan
    ) -> [JITWorkspaceTransitionPlan] {
        let previousIds = Set(widgetIds(in: previous?.layout))
        let nextIds = widgetIds(in: next.layout)
        var plans: [JITWorkspaceTransitionPlan] = []

        for widgetId in nextIds {
            if previousIds.contains(widgetId) {
                if previous?.workspaceId != next.workspaceId {
                    plans.append(JITWorkspaceTransitionPlan(widgetId: widgetId, style: .resize))
                } else {
                    plans.append(JITWorkspaceTransitionPlan(widgetId: widgetId, style: .persist))
                }
            } else {
                plans.append(JITWorkspaceTransitionPlan(widgetId: widgetId, style: .enter))
            }
        }
        for widgetId in previousIds where !nextIds.contains(widgetId) {
            plans.append(JITWorkspaceTransitionPlan(widgetId: widgetId, style: .exit))
        }
        return plans
    }

    private static func widgetIds(in node: UILayoutNode?) -> [String] {
        guard let node else { return [] }
        var ids: [String] = []
        if let widget = node.widget {
            ids.append(widget.widgetId)
        }
        for child in node.children {
            ids.append(contentsOf: widgetIds(in: child))
        }
        return ids
    }
}
