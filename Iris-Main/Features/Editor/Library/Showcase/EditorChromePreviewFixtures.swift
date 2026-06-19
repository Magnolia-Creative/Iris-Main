import SwiftUI

// MARK: - Preview scenario enums

enum EditorChromePreviewGroupScenario: String, CaseIterable, Identifiable {
    case none
    case oneGroup
    case twoGroups
    case fourPlusGroups
    case denseThreeControlGroup

    var id: String { rawValue }

    var displayTitle: String {
        switch self {
        case .none: return "None"
        case .oneGroup: return "One group"
        case .twoGroups: return "Two groups"
        case .fourPlusGroups: return "4+ groups"
        case .denseThreeControlGroup: return "Dense (3 controls)"
        }
    }
}

enum EditorChromePreviewActiveGroup: String, CaseIterable, Identifiable {
    case color
    case tone
    case audio
    case transform
    case motion

    var id: String { rawValue }

    var displayTitle: String {
        rawValue.capitalized
    }

    var groupId: String { "group-\(rawValue)" }
}

// MARK: - Fixtures

@MainActor
enum EditorChromePreviewFixtures {
    static let defaultActions: [EditorChromeActionItem] = [
        EditorChromeActionItem(id: "delete", title: "Delete", systemImage: "trash", role: .destructive),
        EditorChromeActionItem(id: "split", title: "Split", systemImage: "scissors")
    ]

    static func makePlan(
        showsDock: Bool,
        showsActions: Bool,
        showsParameterGroups: Bool,
        showsSpatialControls: Bool,
        showsOverflowChips: Bool,
        groupScenario: EditorChromePreviewGroupScenario,
        density: EditorBottomChromeDensity
    ) -> EditorBottomChromePlan {
        var plan = EditorBottomChromePlan(
            density: density,
            spatialParameters: showsSpatialControls ? spatialDescriptors : [],
            parameterGroups: showsParameterGroups ? parameterGroups(for: groupScenario) : [],
            actions: showsActions ? defaultActions : [],
            isDismissable: showsActions,
            showsDock: showsDock,
            showsOverflowChips: showsOverflowChips,
            activeParameterGroupId: parameterGroups(for: groupScenario).first?.id
        )
        return plan
    }

    static func parameterGroups(for scenario: EditorChromePreviewGroupScenario) -> [EditorParameterGroup] {
        switch scenario {
        case .none:
            return []
        case .oneGroup:
            return [colorGroup]
        case .twoGroups:
            return [colorGroup, audioGroup]
        case .fourPlusGroups:
            return [colorGroup, toneGroup, audioGroup, transformGroup, motionGroup]
        case .denseThreeControlGroup:
            return [denseColorGroup]
        }
    }

    static var colorGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: EditorChromePreviewActiveGroup.color.groupId,
            title: "Color",
            controls: [
                descriptor(id: "temperature", title: "Temperature", defaultScalar: 0, lower: -1, upper: 1),
                descriptor(id: "tint", title: "Tint", defaultScalar: 0, lower: -1, upper: 1)
            ]
        )
    }

    static var toneGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: EditorChromePreviewActiveGroup.tone.groupId,
            title: "Tone",
            controls: [
                descriptor(id: "exposure", title: "Exposure", defaultScalar: 0, lower: -1, upper: 1),
                descriptor(id: "saturation", title: "Saturation", defaultScalar: 0, lower: -1, upper: 1)
            ]
        )
    }

    static var audioGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: EditorChromePreviewActiveGroup.audio.groupId,
            title: "Audio",
            controls: [
                descriptor(id: "volumeGain", title: "Volume", defaultScalar: 1, lower: 0, upper: 2),
                descriptor(id: "ducking", title: "Ducking", defaultScalar: 0, lower: 0, upper: 1)
            ]
        )
    }

    static var transformGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: EditorChromePreviewActiveGroup.transform.groupId,
            title: "Transform",
            controls: [
                descriptor(id: "scale", title: "Scale", defaultScalar: 1, lower: 0.5, upper: 2),
                descriptor(id: "rotation", title: "Rotation", defaultScalar: 0, lower: -180, upper: 180)
            ]
        )
    }

    static var motionGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: EditorChromePreviewActiveGroup.motion.groupId,
            title: "Motion",
            controls: [
                descriptor(id: "velocityX", title: "Velocity X", defaultScalar: 0, lower: -1, upper: 1),
                descriptor(id: "velocityY", title: "Velocity Y", defaultScalar: 0, lower: -1, upper: 1)
            ]
        )
    }

    static var denseColorGroup: EditorParameterGroup {
        EditorParameterGroup(
            id: "group-dense-color",
            title: "Color",
            controls: [
                descriptor(id: "temperature", title: "Temperature", defaultScalar: 0, lower: -1, upper: 1),
                descriptor(id: "tint", title: "Tint", defaultScalar: 0, lower: -1, upper: 1),
                descriptor(id: "saturation", title: "Saturation", defaultScalar: 0, lower: -1, upper: 1)
            ],
            maxVisibleControls: 3
        )
    }

    static var spatialDescriptors: [EditorSpatialParameterDescriptor] {
        [
            EditorSpatialParameterDescriptor(
                id: "velocity-pad",
                title: "Velocity",
                placeholderMessage: "XY velocity pad placeholder"
            )
        ]
    }

    static func seedValues(for groups: [EditorParameterGroup]) -> [String: EditorParameterValue] {
        var values: [String: EditorParameterValue] = [:]
        for group in groups {
            for control in group.controls {
                values[control.id] = control.defaultValue
            }
        }
        return values
    }

    static func descriptor(
        id: String,
        title: String,
        defaultScalar: Double,
        lower: Double,
        upper: Double
    ) -> EditorParameterDescriptor {
        EditorParameterDescriptor(
            id: id,
            title: title,
            bounds: EditorParameterBounds(lower: lower, upper: upper),
            defaultValue: .scalar(defaultScalar)
        )
    }
}
