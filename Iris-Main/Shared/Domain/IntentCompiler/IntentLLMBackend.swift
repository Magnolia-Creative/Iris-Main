import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum IntentLLMBackend: String, CaseIterable, Identifiable {
    case appleFoundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleFoundation:
            return "Apple Foundation Model"
        }
    }

    static var selectableCases: [IntentLLMBackend] {
        [.appleFoundation]
    }

    func makeProvider() -> IntentLLMProvider {
        switch self {
        case .appleFoundation:
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return AppleFoundationIntentLLMProvider()
            }
            #endif
            return UnavailableIntentLLMProvider()
        }
    }
}
