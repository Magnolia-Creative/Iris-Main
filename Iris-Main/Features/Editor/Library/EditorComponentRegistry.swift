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
        )
    ]

    static func entry(for id: EditorComponentID) -> EditorComponentRegistryEntry? {
        entries.first { $0.id == id }
    }

    static func entries(for category: EditorComponentCategory) -> [EditorComponentRegistryEntry] {
        entries.filter { $0.category == category }
    }

    static func parseSize(_ variant: String?) -> EditorComponentSize {
        guard let variant, let size = EditorComponentSize(rawValue: variant) else {
            return .standard
        }
        return size
    }
}
