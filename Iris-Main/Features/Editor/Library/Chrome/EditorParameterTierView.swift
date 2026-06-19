import SwiftUI

struct EditorParameterGroupPicker: View {
    let groups: [EditorParameterGroup]
    @Binding var activeGroupId: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(groups) { group in
                    Button {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            activeGroupId = group.id
                        }
                    } label: {
                        Text(group.title)
                    }
                    .buttonStyle(.irisChipPicker(isSelected: activeGroupId == group.id))
                    .accessibilityAddTraits(activeGroupId == group.id ? .isSelected : [])
                }
            }
        }
    }
}

struct EditorParameterGroupPanel: View {
    let group: EditorParameterGroup
    let density: EditorBottomChromeDensity
    @Binding var values: [String: EditorParameterValue]
    var onScalarChange: ((String, Double) -> Void)?

    private var visibleControls: [EditorParameterDescriptor] {
        EditorParameterGroupVisibility.visibleControls(in: group)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: density.parameterControlSpacing) {
            ForEach(visibleControls) { control in
                EditorParameterControlRenderer(
                    descriptor: control,
                    value: binding(for: control),
                    onScalarChange: { newValue in
                        onScalarChange?(control.id, newValue)
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func binding(for control: EditorParameterDescriptor) -> Binding<EditorParameterValue> {
        Binding(
            get: { values[control.id] ?? control.defaultValue },
            set: { values[control.id] = $0 }
        )
    }
}

struct EditorParameterTierView: View {
    let groups: [EditorParameterGroup]
    let density: EditorBottomChromeDensity
    var showsOverflowChips: Bool = true
    @Binding var activeGroupId: String
    @Binding var values: [String: EditorParameterValue]
    var onScalarChange: ((String, Double) -> Void)?

    private var activeGroup: EditorParameterGroup? {
        groups.first { $0.id == activeGroupId } ?? groups.first
    }

    var body: some View {
        if groups.isEmpty {
            EmptyView()
        } else {
            VStack(alignment: .leading, spacing: density.tierVerticalSpacing) {
                if showsOverflowChips, groups.count > 1 {
                    EditorParameterGroupPicker(
                        groups: groups,
                        activeGroupId: $activeGroupId
                    )
                }

                if let activeGroup {
                    EditorParameterGroupPanel(
                        group: activeGroup,
                        density: density,
                        values: $values,
                        onScalarChange: onScalarChange
                    )
                }
            }
        }
    }
}
