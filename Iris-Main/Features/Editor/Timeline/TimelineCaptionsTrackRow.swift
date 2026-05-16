import SwiftUI

struct TimelineCaptionsTrackRow: View {
    let track: Track
    let cues: [CaptionCue]
    let clipsById: [String: Clip]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    @Binding var selectedCaptionCueId: String?
    let onSelectCue: (String) -> Void

    private var trackHeight: CGFloat { layout.trackHeight(for: track.kind) }
    private var displayCues: [DisplayCue] {
        cues.compactMap { cue in
            guard let range = CaptionCueProjection.currentTimelineRange(for: cue, clips: clipsById) else { return nil }
            return DisplayCue(cue: cue, timelineStartUs: range.start, timelineEndUs: range.end)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .onTapGesture { selectedCaptionCueId = nil }

            ForEach(displayCues) { displayCue in
                let startX = CGFloat(displayCue.timelineStartUs) / 1_000_000.0 * pixelsPerSecond
                let width = CGFloat(displayCue.timelineEndUs - displayCue.timelineStartUs) / 1_000_000.0 * pixelsPerSecond
                let isSelected = selectedCaptionCueId == displayCue.cue.cueId
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .fill(Color.ds.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing(.sp1))
                            .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        Text(displayCue.cue.text)
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
                    )
                    .frame(width: max(width, 24), height: trackHeight * 0.92)
                    .offset(x: startX)
                    .onTapGesture {
                        selectedCaptionCueId = displayCue.cue.cueId
                        onSelectCue(displayCue.cue.cueId)
                    }
            }
        }
        .frame(height: trackHeight)
    }
}

private struct DisplayCue: Identifiable {
    let cue: CaptionCue
    let timelineStartUs: Int64
    let timelineEndUs: Int64

    var id: String { cue.cueId }
}
