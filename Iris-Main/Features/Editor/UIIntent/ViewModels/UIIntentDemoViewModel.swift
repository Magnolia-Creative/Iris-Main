internal import Combine
import Foundation

@MainActor
final class UIIntentDemoViewModel: ObservableObject {
    @Published var prompt = "Make the timeline bigger"
    @Published var selectedContextId = UICompilerDemoFixtures.defaultContext.id
    @Published private(set) var outputText = ""
    @Published private(set) var statusMessage = "Local UI compiler ready."
    @Published private(set) var resultKind = "Waiting"
    @Published private(set) var renderState: EditorJITRenderState
    @Published private(set) var transitionPlans: [EditorJITTransitionPlan] = []
    @Published private(set) var validationResult: EditorJITValidationResult

    let contexts = UICompilerDemoFixtures.allContexts

    private let compiler: LocalUICompiler
    private let encoder: JSONEncoder

    init(compiler: LocalUICompiler = LocalUICompiler()) {
        self.compiler = compiler
        let defaultState = UICompilerDemoFixtures.defaultContext.currentRenderState
        let (validatedState, validationResult) = EditorJITRenderValidator.validate(defaultState)
        self.renderState = validatedState
        self.validationResult = validationResult
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    var selectedContext: NamedUICompilerContext {
        contexts.first { $0.id == selectedContextId } ?? contexts[0]
    }

    var sampleContextSummary: String {
        let context = selectedContext.context
        return """
        Active space: \(context.activeSpace.rawValue)
        Last interacted: \(context.lastInteractedComponent?.rawValue ?? "none")
        Selected clip: \(context.hasSelectedClip ? "yes" : "no")
        Controls available: \(context.controlsAvailable ? "yes" : "no")
        Current UI: \(context.currentRenderState.title)
        """
    }

    func compilePrompt() async {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Enter a prompt to compile."
            resultKind = "Unsupported"
            outputText = ""
            return
        }

        statusMessage = "Compiling locally..."
        let context = selectedContext.context
        let result = await compiler.compile(prompt: trimmed, context: context)
        apply(result: result, previous: renderState)
    }

    func resetToSelectedContext() {
        let previous = renderState
        let state = selectedContext.context.currentRenderState
        let (validatedState, validationResult) = EditorJITRenderValidator.validate(state)
        renderState = validatedState
        self.validationResult = validationResult
        transitionPlans = EditorJITRenderTransitionCoordinator.plan(from: previous, to: validatedState)
        statusMessage = "Context reset."
        resultKind = "Waiting"
        outputText = ""
    }
}

private extension UIIntentDemoViewModel {
    func apply(result: EditorUICompilerResult, previous: EditorJITRenderState) {
        switch result {
        case .resolved(let renderState, let interpretation, let report):
            let (validatedState, validationResult) = EditorJITRenderValidator.validate(renderState)
            self.renderState = validatedState
            self.validationResult = validationResult
            transitionPlans = EditorJITRenderTransitionCoordinator.plan(from: previous, to: validatedState)
            resultKind = "Resolved"
            statusMessage = interpretation
            outputText = formatted(report: report)
        case .clarificationRequired(let options, let report):
            resultKind = "Ambiguous"
            statusMessage = "Clarification needed: \(options.map(\.title).joined(separator: ", "))"
            outputText = formatted(report: report)
        case .deferredToRemote(let request, let report):
            resultKind = "Deferred"
            statusMessage = request.reason
            outputText = formatted(report: report)
        case .unsupported(let reason, let report):
            resultKind = "Unsupported"
            statusMessage = reason
            outputText = formatted(report: report)
        }
    }

    func formatted(report: UIIntentCompilerReport) -> String {
        do {
            let data = try encoder.encode(report)
            return String(data: data, encoding: .utf8) ?? "{}"
        } catch {
            return #"{"error":"Could not encode compiler report."}"#
        }
    }
}
