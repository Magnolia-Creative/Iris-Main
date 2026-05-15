import SwiftUI

struct TimelineCaptionsTrackRow: View {
    let track: Track
    let cues: [CaptionCue]
    let layout: TimelineLayout
    let pixelsPerSecond: CGFloat
    @Binding var selectedCaptionCueId: String?
    let onSelectCue: (String) -> Void

    private var trackHeight: CGFloat { layout.trackHeight(for: track.kind) }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.clear
                .frame(height: trackHeight)
                .contentShape(Rectangle())
                .onTapGesture { selectedCaptionCueId = nil }

            ForEach(cues, id: \.cueId) { cue in
                let startX = CGFloat(cue.timelineStartUs) / 1_000_000.0 * pixelsPerSecond
                let width = CGFloat(cue.timelineEndUs - cue.timelineStartUs) / 1_000_000.0 * pixelsPerSecond
                let isSelected = selectedCaptionCueId == cue.cueId
                RoundedRectangle(cornerRadius: .spacing(.sp1))
                    .fill(Color.ds.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing(.sp1))
                            .stroke(isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay(
                        Text(cue.text)
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.text)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                            .padding(.horizontal, 4)
                    )
                    .frame(width: max(width, 24), height: trackHeight * 0.92)
                    .offset(x: startX)
                    .onTapGesture {
                        selectedCaptionCueId = cue.cueId
                        onSelectCue(cue.cueId)
                    }
            }
        }
        .frame(height: trackHeight)
    }
}
