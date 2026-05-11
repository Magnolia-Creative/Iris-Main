import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

enum TimelineLLMBackend: String, CaseIterable, Identifiable {
    case appleFoundation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .appleFoundation:
            return "Apple Foundation Model"
        }
    }

    static var selectableCases: [TimelineLLMBackend] {
        [.appleFoundation]
    }

    func makeProvider() -> TimelineLLMProvider {
        switch self {
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
