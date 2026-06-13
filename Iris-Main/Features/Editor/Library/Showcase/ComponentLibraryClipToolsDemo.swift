import SwiftUI

private enum LibraryClipToolID: Int {
    case split = 0
    case color = 3
    case volume = 4
}

private enum LibraryClipColorProperty: String, CaseIterable, Identifiable {
    case temperature, tint, exposure, brightness, saturation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .temperature: "Temperature"
        case .tint: "Tint"
        case .exposure: "Exposure"
        case .brightness: "Brightness"
        case .saturation: "Saturation"
        }
    }

    var systemImage: String {
        switch self {
        case .temperature: "thermometer.medium"
        case .tint: "eyedropper.halffull"
        case .exposure: "plusminus.circle"
        case .brightness: "sun.max"
        case .saturation: "camera.filters"
        }
    }

    var range: ClosedRange<Float> {
        switch self {
        case .exposure:
            let bound = ClipColorFilter.exposureRange.upperBound / 2
            return -bound...bound
        case .brightness:
            let bound = ClipColorFilter.normalizedRange.upperBound / 2
            return -bound...bound
        default:
            return ClipColorFilter.normalizedRange
        }
    }

    func value(in filter: ClipColorFilter) -> Float {
        switch self {
        case .temperature: filter.temperature
        case .tint: filter.tint
        case .exposure: filter.exposure
        case .brightness: filter.brightness
        case .saturation: filter.saturation
        }
    }

    func set(_ value: Float, on filter: inout ClipColorFilter) {
        switch self {
        case .temperature: filter.temperature = value
        case .tint: filter.tint = value
        case .exposure: filter.exposure = value
        case .brightness: filter.brightness = value
        case .saturation: filter.saturation = value
        }
    }
}

struct ComponentLibraryClipToolsDemo: View {
    let context: EditorToolContext
    let actions: EditorToolActions

    @State private var activeColorProperty: LibraryClipColorProperty = .temperature

    private var expandedToolSelection: Binding<Int?> {
        Binding(
            get: { context.expandedToolId.wrappedValue },
            set: { context.expandedToolId.wrappedValue = $0 }
        )
    }

    private var isSliderExpanded: Bool {
        guard let id = context.expandedToolId.wrappedValue else { return false }
        return id == LibraryClipToolID.color.rawValue || id == LibraryClipToolID.volume.rawValue
    }

    var body: some View {
        EditorExpandableToolTrayComponent(
            expandedToolId: expandedToolSelection,
            showsLeadingWhenExpanded: !isSliderExpanded,
            leading: {
                EditorToolCloseButtonComponent(title: "Deselect clip", action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        context.expandedToolId.wrappedValue = nil
                        actions.onDeselectClip()
                    }
                })
            },
            collapsed: {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: .spacing(.sp1)) {
                        EditorToolButtonComponent(
                            systemImage: "trash",
                            title: "Delete",
                            role: .destructive,
                            action: actions.onDeleteClip
                        )
                        EditorToolButtonComponent(
                            systemImage: "scissors",
                            title: "Split",
                            action: actions.onSplitClip
                        )
                        EditorToolButtonComponent(
                            systemImage: "camera.filters",
                            title: "Color",
                            action: { toggleTool(LibraryClipToolID.color.rawValue) }
                        )
                        EditorToolButtonComponent(
                            systemImage: "speaker.wave.2",
                            title: "Volume",
                            action: { toggleTool(LibraryClipToolID.volume.rawValue) }
                        )
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
            },
            expanded: { toolId in
                if toolId == LibraryClipToolID.color.rawValue {
                    colorControls
                } else if toolId == LibraryClipToolID.volume.rawValue {
                    volumeControls
                }
            }
        )
    }

    private func toggleTool(_ id: Int) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            let current = context.expandedToolId.wrappedValue
            context.expandedToolId.wrappedValue = current == id ? nil : id
            if current != id, id == LibraryClipToolID.color.rawValue {
                activeColorProperty = .temperature
            }
        }
    }

    private var colorControls: some View {
        HStack(alignment: .top, spacing: .spacing(.sp2)) {
            EditorToolBackButtonComponent(accessibilityLabel: "Back to clip tools") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    context.expandedToolId.wrappedValue = nil
                }
            }
            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                EditorSegmentedPillControlComponent(
                    title: nil,
                    options: LibraryClipColorProperty.allCases.map {
                        EditorSegmentedPillOption(id: $0.id, title: $0.title)
                    },
                    selectionId: Binding(
                        get: { activeColorProperty.id },
                        set: { raw in
                            if let property = LibraryClipColorProperty(rawValue: raw) {
                                activeColorProperty = property
                            }
                        }
                    )
                )
                HStack(spacing: .spacing(.sp2)) {
                    EditorSliderControlComponent(
                        title: activeColorProperty.title,
                        value: activeColorBinding,
                        bounds: EditorParameterBounds(
                            lower: Double(activeColorProperty.range.lowerBound),
                            upper: Double(activeColorProperty.range.upperBound)
                        ),
                        display: .inlineValue,
                        valueFormatter: { String(format: "%.2f", $0) }
                    )
                    .frame(minWidth: 220)
                    .frame(maxWidth: .infinity)
                    EditorToolButtonComponent(
                        systemImage: "arrow.counterclockwise",
                        title: "Reset \(activeColorProperty.title)",
                        shape: .roundedIcon,
                        action: {
                            var filter = context.selectedClipColorFilter
                            activeColorProperty.set(0, on: &filter)
                            actions.onSetClipColorFilter(filter)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var volumeControls: some View {
        HStack(spacing: .spacing(.sp2)) {
            EditorToolBackButtonComponent(accessibilityLabel: "Back to clip tools") {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    context.expandedToolId.wrappedValue = nil
                }
            }
            EditorSliderControlComponent(
                title: "Volume",
                value: volumeBinding,
                bounds: EditorParameterBounds(lower: 0, upper: 2),
                display: .inlineValue,
                valueFormatter: { "\(Int(($0 * 100).rounded()))%" }
            )
            EditorToolButtonComponent(
                systemImage: "arrow.counterclockwise",
                title: "Reset volume",
                shape: .roundedIcon,
                action: actions.onResetClipVolume
            )
        }
    }

    private var volumeBinding: Binding<Double> {
        Binding(
            get: { Double(context.selectedClipVolume.gain) },
            set: { actions.onSetClipVolume(ClipVolume(gain: Float($0))) }
        )
    }

    private var activeColorBinding: Binding<Double> {
        Binding(
            get: { Double(activeColorProperty.value(in: context.selectedClipColorFilter)) },
            set: { newValue in
                var filter = context.selectedClipColorFilter
                activeColorProperty.set(Float(newValue), on: &filter)
                actions.onSetClipColorFilter(filter)
            }
        )
    }
}
