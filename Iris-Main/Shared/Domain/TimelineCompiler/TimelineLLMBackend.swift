import Foundation

enum TimelineLLMBackend: String, CaseIterable, Identifiable {
    case zeticGemma
    case appleFoundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .zeticGemma:
            return "Zetic (Gemma)"
        case .appleFoundation:
            return "Apple Foundation Model"
        }
    }

    static var selectableCases: [TimelineLLMBackend] {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            return allCases
        }
        #endif
        return [.zeticGemma]
    }

    func makeProvider() -> TimelineLLMProvider {
        switch self {
        case .zeticGemma:
            return ZeticGemmaTimelineLLMProvider()
        case .appleFoundation:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return AppleFoundationTimelineLLMProvider()
            }
            #endif
            return UnavailableTimelineLLMProvider()
        }
    }
}
