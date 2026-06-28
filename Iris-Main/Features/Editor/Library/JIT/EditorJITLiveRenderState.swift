internal import Combine
import Foundation

@MainActor
final class EditorJITLiveRenderState: ObservableObject {
    static let defaultRenderState: EditorJITRenderState = {
        let (state, _) = EditorJITRenderValidator.validate(EditorJITRecipeCatalog.defaultRecipe.makeRawState())
        return state
    }()

    @Published private(set) var renderState: EditorJITRenderState
    @Published private(set) var previousRenderState: EditorJITRenderState?
    @Published private(set) var transitionPlans: [EditorJITTransitionPlan] = []
    @Published private(set) var currentWorkspaceId: String?
    private let compiler: EditorIntentCompiler
    private let uiPlanAdapter: EditorJITUIPlanAdapter

    init(
        renderState: EditorJITRenderState? = nil,
        compiler: EditorIntentCompiler = EditorIntentCompiler(),
        uiPlanAdapter: EditorJITUIPlanAdapter = EditorJITUIPlanAdapter()
    ) {
        let renderState = renderState ?? EditorJITLiveRenderState.defaultRenderState
        let (validated, _) = EditorJITRenderValidator.validate(renderState)
        self.renderState = validated
        self.compiler = compiler
        self.uiPlanAdapter = uiPlanAdapter
    }

    func apply(_ nextState: EditorJITRenderState) -> Bool {
        let previous = renderState
        let (validated, validation) = EditorJITRenderValidator.validate(nextState)
        guard validation.isValid else { return false }

        previousRenderState = previous
        transitionPlans = EditorJITRenderTransitionCoordinator.plan(from: previous, to: validated)
        renderState = validated
        return true
    }

    func apply(
        uiPlan: RemoteIntentUIPlan,
        prompt: String,
        editResult _: IntentCompileResult
    ) -> Bool {
        let adapted = uiPlanAdapter.adapt(
            uiPlan: uiPlan,
            prompt: prompt,
            fallback: renderState
        )
        guard adapted.validationResult.isValid else { return false }
        guard apply(adapted.renderState) else { return false }
        currentWorkspaceId = uiPlan.workspaceId
        return true
    }

    func compileAndApply(
        prompt: String,
        activeSpace: EditorSpace,
        hasSelectedClip: Bool
    ) async -> Bool {
        let context = EditorIntentCompilerContext(
            activeSpace: activeSpace,
            currentRenderState: renderState,
            lastInteractedComponent: nil,
            activeParameterGroupId: renderState.chromePlan.activeParameterGroupId,
            hasSelectedClip: hasSelectedClip,
            controlsAvailable: hasSelectedClip || renderState.chromePlan.showsDock
        )

        let result = await compiler.compile(prompt: prompt, context: context)
        switch result {
        case .resolved(let nextState, _, _):
            return apply(nextState)
        case .clarificationRequired, .deferredToRemote, .unsupported:
            return false
        }
    }
}
