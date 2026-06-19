import Foundation

struct EditorComponentRegistryEntry: Identifiable, Equatable {
    let id: EditorComponentID
    let displayName: String
    let category: EditorComponentCategory
    let supportedSizes: Set<EditorComponentSize>
    let supportedAxes: Set<EditorComponentAxis>
    let workspaceWidgetId: String?

    var idString: String { id.rawValue }
}

enum EditorComponentRegistry {
    static let version = "1"

    static let entries: [EditorComponentRegistryEntry] = [
        EditorComponentRegistryEntry(
            id: "timeline.full",
            displayName: "Timeline Surface",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: "timeline.full"
        ),
        EditorComponentRegistryEntry(
            id: "timeline.organizer",
            displayName: "Timeline Organizer",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "timeline.timeReadout",
            displayName: "Timeline Time Readout",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "timeline.track",
            displayName: "Timeline Track",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: "timeline.primaryTrack"
        ),
        EditorComponentRegistryEntry(
            id: "timeline.ruler",
            displayName: "Timeline Ruler",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "timeline.addButton",
            displayName: "Add Media Button",
            category: .timeline,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "tool.slider",
            displayName: "Parameter Slider",
            category: .tools,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal, .vertical],
            workspaceWidgetId: "toolbar.parameterControls"
        ),
        EditorComponentRegistryEntry(
            id: "playback.viewer",
            displayName: "Playback Viewer",
            category: .playback,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: "playback.viewer"
        ),
        EditorComponentRegistryEntry(
            id: "playback.section",
            displayName: "Playback Section",
            category: .playback,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "playback.transport",
            displayName: "Playback Transport",
            category: .playback,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "navigation.bottomBar",
            displayName: "NavigationComponent",
            category: .navigation,
            supportedSizes: [.standard],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "navigation.intelligence",
            displayName: "IntelligenceComponent",
            category: .navigation,
            supportedSizes: [.standard],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "toolbar.collection",
            displayName: "Component Toolbar",
            category: .chrome,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.horizontal, .vertical],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "chrome.bottomStack",
            displayName: "Bottom Chrome Stack",
            category: .chrome,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.vertical],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "chrome.parameterTier",
            displayName: "Parameter Group Tier",
            category: .chrome,
            supportedSizes: [.compressed, .standard, .expanded],
            supportedAxes: [.vertical],
            workspaceWidgetId: nil
        ),
        EditorComponentRegistryEntry(
            id: "chrome.actionsRow",
            displayName: "Immediate Actions Row",
            category: .chrome,
            supportedSizes: [.standard],
            supportedAxes: [.horizontal],
            workspaceWidgetId: nil
        )
    ]

    static func entry(for id: EditorComponentID) -> EditorComponentRegistryEntry? {
        entries.first { $0.id == id }
    }

    static func entries(for category: EditorComponentCategory) -> [EditorComponentRegistryEntry] {
        entries.filter { $0.category == category }
    }

    static func parseSize(_ variant: String?) -> EditorComponentSize {
        guard let variant else { return .standard }
        if let size = EditorComponentSize(rawValue: variant) {
            return size
        }
        return parseLegacyVariant(variant)
    }

    static func parseLegacyVariant(_ variant: String) -> EditorComponentSize {
        switch variant.lowercased() {
        case "compressed", "compact":
            return .compressed
        case "expanded", "large":
            return .expanded
        default:
            return .standard
        }
    }
}
