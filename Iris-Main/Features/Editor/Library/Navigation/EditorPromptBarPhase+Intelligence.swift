extension EditorPromptBarPhase {
    var intelligencePhase: IntelligencePromptPhase {
        switch self {
        case .idle:
            return .idle
        case .recording:
            return .recording
        case .typing:
            return .typing
        case .submitting(let status):
            return .submitting(status)
        case .clarification(let message):
            return .clarification(message)
        case .error(let message):
            return .error(message)
        }
    }
}
