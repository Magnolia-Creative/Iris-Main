import Foundation

enum EditorComponentCategory: String, Codable, CaseIterable, Identifiable {
    case timeline
    case tools
    case playback
    case navigation
    case chrome
    case panels

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .timeline: return "Timeline"
        case .tools: return "Tools"
        case .playback: return "Playback"
        case .navigation: return "Navigation"
        case .chrome: return "Chrome"
        case .panels: return "Panels"
        }
    }
}

enum EditorComponentSize: String, Codable, CaseIterable, Identifiable {
    case compressed
    case standard
    case expanded

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .compressed: return "Compressed"
        case .standard: return "Standard"
        case .expanded: return "Expanded"
        }
    }
}

enum EditorComponentAxis: String, Codable, CaseIterable, Identifiable {
    case horizontal
    case vertical

    var id: String { rawValue }
}

enum EditorComponentDensity: String, Codable, CaseIterable {
    case compact
    case regular
    case spacious
}

struct EditorComponentID: Hashable, Codable, ExpressibleByStringLiteral, CustomStringConvertible {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    var description: String { rawValue }
}

protocol EditorLibraryComponentSpec {
    static var componentId: EditorComponentID { get }
    static var category: EditorComponentCategory { get }
    static var supportedSizes: Set<EditorComponentSize> { get }
}

enum EditorTrackInteractionMode: String, Codable, CaseIterable {
    case editable
    case readOnly
    case review
}

enum EditorParameterDisplay: String, Codable, CaseIterable {
    case slider
    case inlineValue
    case compact
}

struct EditorParameterBounds<Value: Comparable>: Equatable {
    let lower: Value?
    let upper: Value?

    func clamped(_ value: Value) -> Value {
        var result = value
        if let lower, result < lower { result = lower }
        if let upper, result > upper { result = upper }
        return result
    }

    func closedRange(defaultLower: Value, defaultUpper: Value) -> ClosedRange<Value> where Value: Strideable {
        let lowerBound = lower ?? defaultLower
        let upperBound = upper ?? defaultUpper
        if lowerBound <= upperBound {
            return lowerBound...upperBound
        }
        return defaultLower...defaultUpper
    }
}
