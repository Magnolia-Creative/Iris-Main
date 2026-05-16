import SwiftUI

struct PlaybackAspectSettingsPanel: View {
    @ObservedObject var timeline: TimelineController
    @Binding var isPresented: Bool

    @Namespace private var orientationNamespace
    @State private var orientation: Orientation

    private enum Orientation: String, CaseIterable, Identifiable {
        case horizontal = "Horizontal"
        case vertical = "Vertical"

        var id: String { rawValue }
    }

    private let tileFrameMaxSide: CGFloat = 72

    init(timeline: TimelineController, isPresented: Binding<Bool>) {
        self.timeline = timeline
        self._isPresented = isPresented
        let aspect = timeline.state.manualOutputAspect ?? timeline.state.derivedOutputAspect
        self._orientation = State(initialValue: (aspect?.height ?? 0) > (aspect?.width ?? 0) ? .vertical : .horizontal)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            header
            orientationToggle
            presetGrid
            doneButton
        }
        .padding(.sp5)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.ds.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.24), radius: 28, x: 0, y: 18)
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: orientation)
        .animation(.easeInOut(duration: 0.18), value: timeline.state.manualOutputAspect)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text("Canvas aspect")
                .typography(.heading)
                .foregroundColor(Color.ds.text)

            Text(description)
                .typography(.bodySmall)
                .foregroundColor(Color.ds.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var orientationToggle: some View {
        HStack(spacing: .spacing(.sp1)) {
            ForEach(Orientation.allCases) { item in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        orientation = item
                    }
                } label: {
                    Text(item.rawValue)
                        .typography(.bodySmall)
                        .foregroundColor(orientation == item ? Color.ds.text : Color.ds.textMuted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, .spacing(.sp2))
                        .background {
                            if orientation == item {
                                Capsule()
                                    .fill(Color.ds.surface)
                                    .matchedGeometryEffect(id: "selected-orientation", in: orientationNamespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.spacing(.sp1))
        .background(Capsule().fill(Color.ds.surface.opacity(0.55)))
    }

    private var presetGrid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: .spacing(.sp3)), count: 3),
            spacing: .spacing(.sp4)
        ) {
            AspectTile(
                label: "Auto",
                aspect: autoTileAspect,
                isSelected: timeline.state.manualOutputAspect == nil,
                maxSide: tileFrameMaxSide,
                iconName: "wand.and.stars"
            ) {
                try? timeline.setManualPlaybackOutputAspect(nil)
            }

            ForEach(presets) { preset in
                AspectTile(
                    label: preset.label,
                    aspect: preset.outputAspect,
                    isSelected: timeline.state.manualOutputAspect == preset.outputAspect,
                    maxSide: tileFrameMaxSide
                ) {
                    try? timeline.setManualPlaybackOutputAspect(preset.outputAspect)
                }
            }
        }
    }

    private var doneButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isPresented = false
            }
        } label: {
            Text("Done")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.primary)
    }

    private var presets: [PlaybackAspectPreset] {
        switch orientation {
        case .horizontal:
            return PlaybackAspectPreset.horizontalPresets
        case .vertical:
            return PlaybackAspectPreset.verticalPresets
        }
    }

    private var autoTileAspect: OutputAspectRatio {
        timeline.state.derivedOutputAspect ?? OutputAspectRatio(width: 1, height: 1)
    }

    private var description: String {
        if let manual = timeline.state.manualOutputAspect {
            return "Fixed at \(manual.width):\(manual.height) (saved with project)."
        }
        if let size = timeline.state.derivedOutputPixelSize {
            return "Following first clip (\(Int(size.width))×\(Int(size.height)))."
        }
        return "Add a clip to pick up its aspect, or choose a preset below."
    }
}

private struct AspectTile: View {
    let label: String
    let aspect: OutputAspectRatio
    let isSelected: Bool
    let maxSide: CGFloat
    var iconName: String?
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: .spacing(.sp2)) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(isSelected ? Color.ds.accentBg.opacity(0.18) : Color.ds.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 1.5 : 1)
                        )
                        .frame(width: fittedSize.width, height: fittedSize.height)

                    if let iconName {
                        Image(systemName: iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(isSelected ? Color.ds.accentFg : Color.ds.textMuted)
                    }
                }
                .frame(width: maxSide, height: maxSide)

                Text(label)
                    .typography(.bodySmall)
                    .foregroundColor(isSelected ? Color.ds.accentFg : Color.ds.text)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var fittedSize: CGSize {
        let ratio = max(0.1, aspect.aspectCGFloat)
        if ratio >= 1 {
            return CGSize(width: maxSide, height: maxSide / ratio)
        }
        return CGSize(width: maxSide * ratio, height: maxSide)
    }
}
