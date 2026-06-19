import Foundation
import SwiftUI

// MARK: - Tiers

enum EditorBottomChromeTier: Int, CaseIterable, Equatable {
    case spatialParameters
    case parameters
    case actions
    case dock

    /// Visual order from top to bottom.
    static var displayOrder: [EditorBottomChromeTier] {
        [.spatialParameters, .parameters, .actions, .dock]
    }
}

enum EditorBottomChromeDensity: String, CaseIterable, Identifiable {
    case compact
    case standard
    case expanded

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .compact: return "Compact"
        case .standard: return "Standard"
        case .expanded: return "Expanded"
        }
    }

    var tierVerticalSpacing: CGFloat {
        switch self {
        case .compact: return .spacing(.sp1)
        case .standard: return .spacing(.sp2)
        case .expanded: return .spacing(.sp3)
        }
    }

    var parameterControlSpacing: CGFloat {
        switch self {
        case .compact: return .spacing(.sp2)
        case .standard: return .spacing(.sp3)
        case .expanded: return .spacing(.sp4)
        }
    }
}

// MARK: - Actions

enum EditorChromeActionRole: Equatable {
    case neutral
    case destructive
    case accent
}

struct EditorChromeActionItem: Identifiable, Equatable {
    let id: String
    let title: String
    let systemImage: String
    var role: EditorChromeActionRole = .neutral
    var isEnabled: Bool = true
}

// MARK: - Parameter values

enum EditorParameterControlKind: Equatable {
    case slider
    case segmented(options: [EditorSegmentedPillOption])
    case toggle
    case spatialPlaceholder(title: String)
}

enum EditorParameterValue: Equatable {
    case scalar(Double)
    case point2D(x: Double, y: Double)
    case curve([EditorParameterKeyframe])
}

struct EditorParameterKeyframe: Equatable, Identifiable {
    let id: String
    let timeUs: Int64
    let value: Double
}

struct EditorParameterDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    var kind: EditorParameterControlKind = .slider
    var bounds: EditorParameterBounds<Double> = EditorParameterBounds(lower: 0, upper: 1)
    var defaultValue: EditorParameterValue = .scalar(0)
    var display: EditorParameterDisplay = .compact
}

struct EditorParameterGroup: Identifiable, Equatable {
    let id: String
    let title: String
    var controls: [EditorParameterDescriptor]
    /// When set, caps how many controls render at once in the active group panel.
    var maxVisibleControls: Int = 3

    var needsChipPicker: Bool {
        controls.count > maxVisibleControls
    }
}

// MARK: - Spatial tier

struct EditorSpatialParameterDescriptor: Identifiable, Equatable {
    let id: String
    let title: String
    var placeholderMessage: String = "2D control placeholder"
}

// MARK: - Plan

struct EditorBottomChromePlan: Equatable {
    var density: EditorBottomChromeDensity = .standard
    var spatialParameters: [EditorSpatialParameterDescriptor] = []
    var parameterGroups: [EditorParameterGroup] = []
    var actions: [EditorChromeActionItem] = []
    var isDismissable: Bool = false
    var showsDock: Bool = true
    var showsOverflowChips: Bool = true
    var activeParameterGroupId: String?

    var activeParameterGroup: EditorParameterGroup? {
        guard let activeParameterGroupId else {
            return parameterGroups.first
        }
        return parameterGroups.first { $0.id == activeParameterGroupId } ?? parameterGroups.first
    }

    var visibleTiers: [EditorBottomChromeTier] {
        var tiers: [EditorBottomChromeTier] = []
        if !spatialParameters.isEmpty { tiers.append(.spatialParameters) }
        if !parameterGroups.isEmpty { tiers.append(.parameters) }
        if isDismissable || !actions.isEmpty { tiers.append(.actions) }
        if showsDock { tiers.append(.dock) }
        return tiers
    }

    var tierCountAboveDock: Int {
        visibleTiers.filter { $0 != .dock }.count
    }

    static let empty = EditorBottomChromePlan()
}

// MARK: - Visible control selection

enum EditorParameterGroupVisibility {
    static let defaultMaxVisibleControls = 3

    static func visibleControls(
        in group: EditorParameterGroup,
        maxVisible: Int = defaultMaxVisibleControls
    ) -> [EditorParameterDescriptor] {
        let cap = min(group.maxVisibleControls, maxVisible)
        return Array(group.controls.prefix(max(0, cap)))
    }
}
