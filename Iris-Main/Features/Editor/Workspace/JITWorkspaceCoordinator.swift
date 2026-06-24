internal import Combine
import Foundation
import OSLog

@MainActor
final class JITWorkspaceCoordinator: ObservableObject {
    @Published private(set) var activePlan: UIWorkspacePlan
    @Published private(set) var transitionPlans: [JITWorkspaceTransitionPlan] = []
    @Published private(set) var isLoadingPlan = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var lastCompiledPrompt: String = ""
    @Published private(set) var lastIntentResult: IntentCompileResult?

    private let service: UIWorkspaceService
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "JITWorkspace"
    )

    var usesIntentWorkspace: Bool {
        !activePlan.isDefaultWorkspace
    }

    var showsBottomNavigation: Bool {
        activePlan.toolbar.showNavigation
    }

    var showsPromptBar: Bool {
        activePlan.toolbar.showPromptBar
    }

    func timelinePresentation(for plan: UIWorkspacePlan) -> JITTimelinePresentation {
        let widgetIds = widgetIds(in: plan.layout)
        if widgetIds.contains("timeline.focusedClipStrip") || widgetIds.contains("timeline.primaryTrack") {
            return .focusedClipStrip
        }
        if widgetIds.contains("timeline.full") {
            return .full
        }
        if plan.hiddenBecauseIrrelevant.contains("timeline.full") {
            return .hidden
        }
        return .hidden
    }

    func previewUsesBeforeAfter(for plan: UIWorkspacePlan) -> Bool {
        widgetIds(in: plan.layout).contains("playback.beforeAfterViewer")
    }

    init(
        activeSpace: EditorSpace,
        hasSelectedClip: Bool,
        service: UIWorkspaceService = UIWorkspaceService()
    ) {
        self.service = service
        self.activePlan = UIWorkspaceCatalog.fallbackDefaultPlan(
            activeSpace: activeSpace,
            hasSelectedClip: hasSelectedClip
        )
    }

    func syncDefaultWorkspace(activeSpace: EditorSpace, hasSelectedClip: Bool) {
        guard !usesIntentWorkspace else { return }
        applyPlan(
            UIWorkspaceCatalog.fallbackDefaultPlan(
                activeSpace: activeSpace,
                hasSelectedClip: hasSelectedClip
            ),
            previous: activePlan
        )
    }

    func restoreDefaultWorkspace(activeSpace: EditorSpace, hasSelectedClip: Bool) {
        applyPlan(
            UIWorkspaceCatalog.fallbackDefaultPlan(
                activeSpace: activeSpace,
                hasSelectedClip: hasSelectedClip
            ),
            previous: activePlan
        )
    }

    func activateIntentWorkspace(
        prompt: String,
        context: IntentCompilerContext,
        editorContext: UIEditorContext,
        intentResult: IntentCompileResult? = nil,
        projectId: String?
    ) async {
        lastCompiledPrompt = prompt
        lastIntentResult = intentResult

        if let localPlan = UIWorkspaceCatalog.localPlan(for: prompt, editorContext: editorContext) {
            lastErrorMessage = nil
            applyPlan(sanitize(plan: localPlan), previous: activePlan)
            return
        }

        guard let projectId, !projectId.isEmpty else {
            lastErrorMessage = UIWorkspaceServiceError.missingProjectId.localizedDescription
            return
        }
        isLoadingPlan = true
        lastErrorMessage = nil
        defer { isLoadingPlan = false }

        let request = UIWorkspacePlanRequest(
            prompt: prompt,
            context: context,
            editorContext: editorContext,
            intentResult: intentResult,
            currentWorkspaceId: activePlan.workspaceId
        )
        do {
            let plan = try await service.fetchPlan(request: request, projectId: projectId)
            let sanitized = sanitize(plan: plan)
            applyPlan(sanitized, previous: activePlan)
        } catch {
            Self.logger.error("Failed to fetch workspace plan: \(error.localizedDescription, privacy: .public)")
            lastErrorMessage = error.localizedDescription
        }
    }

    func advanceToNextSlice(
        context: IntentCompilerContext,
        editorContext: UIEditorContext,
        projectId: String?,
        activeSpace: EditorSpace,
        hasSelectedClip: Bool
    ) async {
        guard !activePlan.isDefaultWorkspace else { return }
        let nextIndex = activePlan.currentSliceIndex + 1
        guard nextIndex < activePlan.intentSlices.count else {
            restoreDefaultWorkspace(activeSpace: activeSpace, hasSelectedClip: hasSelectedClip)
            return
        }
        let nextSlice = activePlan.intentSlices[nextIndex]
        let request = UIWorkspacePlanRequest(
            prompt: lastCompiledPrompt,
            context: context,
            editorContext: editorContext,
            intentResult: lastIntentResult,
            currentWorkspaceId: nextSlice.id
        )
        guard let projectId, !projectId.isEmpty else {
            restoreDefaultWorkspace(activeSpace: activeSpace, hasSelectedClip: hasSelectedClip)
            return
        }
        do {
            let plan = try await service.fetchPlan(request: request, projectId: projectId)
            applyPlan(sanitize(plan: plan), previous: activePlan)
        } catch {
            restoreDefaultWorkspace(activeSpace: activeSpace, hasSelectedClip: hasSelectedClip)
        }
    }

    func completeIntentFlow(activeSpace: EditorSpace, hasSelectedClip: Bool) {
        if activePlan.restoreDefaultOnComplete {
            restoreDefaultWorkspace(activeSpace: activeSpace, hasSelectedClip: hasSelectedClip)
        }
    }

    private func applyPlan(_ plan: UIWorkspacePlan, previous: UIWorkspacePlan?) {
        transitionPlans = JITWorkspaceTransitionCoordinator.plan(from: previous, to: plan)
        activePlan = plan
    }

    private func widgetIds(in node: UILayoutNode) -> [String] {
        var ids: [String] = []
        if let widget = node.widget {
            ids.append(widget.widgetId)
        }
        for child in node.children {
            ids.append(contentsOf: widgetIds(in: child))
        }
        return ids
    }

    func sanitizedPlan(_ plan: UIWorkspacePlan) -> UIWorkspacePlan {
        sanitize(plan: plan)
    }

    private func sanitize(plan: UIWorkspacePlan) -> UIWorkspacePlan {
        func sanitizeNode(_ node: UILayoutNode) -> UILayoutNode? {
            switch node.type {
            case .widget:
                guard let widget = node.widget, UIWorkspaceCatalog.isSupported(widgetId: widget.widgetId) else {
                    return nil
                }
                return UILayoutNode(type: .widget, widget: widget, size: node.size)
            case .vstack, .hstack, .zstack:
                let children = node.children.compactMap(sanitizeNode)
                guard !children.isEmpty else { return nil }
                return UILayoutNode(type: node.type, children: children, size: node.size)
            case .toolbar:
                return nil
            }
        }

        guard let layout = sanitizeNode(plan.layout) else {
            return plan
        }
        let toolbarWidgets = plan.toolbar.widgets.filter { UIWorkspaceCatalog.isSupported(widgetId: $0.widgetId) }
        return UIWorkspacePlan(
            catalogVersion: plan.catalogVersion,
            workspaceId: plan.workspaceId,
            intentSummary: plan.intentSummary,
            intentSlices: plan.intentSlices,
            currentSliceId: plan.currentSliceId,
            currentSliceIndex: plan.currentSliceIndex,
            layout: layout,
            toolbar: UIToolbarPlacement(
                widgets: toolbarWidgets,
                showNavigation: plan.toolbar.showNavigation,
                showPromptBar: plan.toolbar.showPromptBar
            ),
            hiddenBecauseIrrelevant: plan.hiddenBecauseIrrelevant,
            warnings: plan.warnings,
            isDefaultWorkspace: plan.isDefaultWorkspace,
            restoreDefaultOnComplete: plan.restoreDefaultOnComplete
        )
    }
}
