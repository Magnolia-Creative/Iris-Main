import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

#if canImport(ZeticMLange)
import ZeticMLange
#endif

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
        var backends: [TimelineLLMBackend] = []

        #if canImport(ZeticMLange)
        backends.append(.zeticGemma)
        #endif

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            backends.append(.appleFoundation)
        }
        #endif

        return backends.isEmpty ? [.zeticGemma] : backends
    }

    func makeProvider() -> TimelineLLMProvider {
        switch self {
        case .zeticGemma:
            #if canImport(ZeticMLange)
            return ZeticGemmaTimelineLLMProvider()
            #else
            return UnavailableTimelineLLMProvider()
            #endif
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
