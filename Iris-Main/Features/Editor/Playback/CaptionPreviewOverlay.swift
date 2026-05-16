import SwiftUI

struct CaptionPreviewOverlay: View {
    let state: TimelineState
    let canvasSize: CGSize

    private var activeCaption: CaptionPreviewCue? {
        CaptionPreviewResolver.activeCue(
            at: state.currentTimeAtCenter,
            groups: state.captionGroups,
            cues: state.captionCues,
            clips: state.clips
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let activeCaption {
                CaptionPreviewText(cue: activeCaption, canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        .allowsHitTesting(false)
    }
}

struct CaptionPreviewCue: Equatable {
    let id: String
    let text: String
    let style: RenderCaptionStyle
    let position: CGPoint
}

enum CaptionPreviewResolver {
    static let defaultPosition = CGPoint(x: 0.5, y: 0.95)

    static func activeCue(
        at playheadUs: Int64,
        groups: [CaptionGroup],
        cues: [CaptionCue],
        clips: [Clip]
    ) -> CaptionPreviewCue? {
        let clipsById = Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) })
        let groupsById = Dictionary(uniqueKeysWithValues: groups.map { ($0.groupId, $0) })

        return cues
            .compactMap { cue -> (cue: CaptionCue, group: CaptionGroup, range: (start: Int64, end: Int64))? in
                guard let group = groupsById[cue.groupId],
                      let range = CaptionCueProjection.currentTimelineRange(for: cue, clips: clipsById),
                      playheadUs >= range.start,
                      playheadUs < range.end
                else {
                    return nil
                }
                return (cue, group, range)
            }
            .sorted { lhs, rhs in
                if lhs.range.start == rhs.range.start {
                    return lhs.cue.cueId < rhs.cue.cueId
                }
                return lhs.range.start < rhs.range.start
            }
            .first
            .map { match in
                CaptionPreviewCue(
                    id: match.cue.cueId,
                    text: match.cue.text,
                    style: match.group.style.renderCaptionStyle(
                        textColorHex: match.group.textColor,
                        hasBackground: match.group.hasBackground
                    ),
                    position: defaultPosition
                )
            }
    }
}

private struct CaptionPreviewText: View {
    let cue: CaptionPreviewCue
    let canvasSize: CGSize

    var body: some View {
        Text(cue.text)
            .font(font)
            .fontWeight(fontWeight)
            .multilineTextAlignment(.center)
            .foregroundStyle(color(cue.style.textColor))
            .lineLimit(3)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: max(1, canvasSize.width * 0.9))
            .background {
                if cue.style.backgroundColor.w > 0 {
                    RoundedRectangle(cornerRadius: cue.style.cornerRadius, style: .continuous)
                        .fill(color(cue.style.backgroundColor))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: canvasSize.width * 0.9, alignment: .center)
            .position(
                x: cue.position.x * canvasSize.width,
                y: cue.position.y * canvasSize.height
            )
            .offset(y: -captionVerticalOffset)
            .shadow(color: .black.opacity(0.35), radius: 3, x: 0, y: 1)
            .id(cue.id)
    }

    private var font: Font {
        let size = max(14, min(28, canvasSize.height * 0.085))
        let name = cue.style.fontName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return .custom(name, size: size)
        }
        return .system(size: size, weight: fontWeight)
    }

    private var fontWeight: Font.Weight {
        cue.style.fontWeight > 500 ? .semibold : .regular
    }

    private var captionVerticalOffset: CGFloat {
        max(18, canvasSize.height * 0.045)
    }

    private func color(_ value: SIMD4<Float>) -> Color {
        Color(
            red: Double(value.x),
            green: Double(value.y),
            blue: Double(value.z),
            opacity: Double(value.w)
        )
    }
}
