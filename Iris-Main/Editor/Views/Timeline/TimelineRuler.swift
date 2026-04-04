import SwiftUI

struct TimelineRuler: View {
    let pixelsPerSecond: CGFloat
    let durationUs: Int64
    @Binding var currentTime: Int64

    private var timeMarkers: [Int64] {
        let totalSeconds = max(0, Int(ceil(Double(durationUs) / 1_000_000.0)))
        return (0...max(0, totalSeconds)).map { Int64($0) * 1_000_000 }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: 0) {
                ForEach(Array(timeMarkers.enumerated()), id: \.element) { index, time in
                    TimeMarker(time: time, isLast: index == timeMarkers.count - 1, pixelsPerSecond: pixelsPerSecond)
                }
            }
        }
    }
}

private struct TimeMarker: View {
    let time: Int64
    let isLast: Bool
    let pixelsPerSecond: CGFloat

    private var majorTickSpacing: CGFloat { pixelsPerSecond }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .center, spacing: 0) {
                Rectangle()
                    .fill(Color.ds.border)
                    .frame(width: 1, height: 12)
                Text(TimeFormatter.formatTime(time))
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
                    .padding(.top, 1)
                    .fixedSize()
                Spacer(minLength: 0)
            }
            .frame(width: 0)

            if !isLast {
                let spacingWidth = majorTickSpacing / 5
                HStack(spacing: 0) {
                    Spacer().frame(width: spacingWidth)
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 0) {
                            Rectangle()
                                .fill(Color.ds.border)
                                .frame(width: 1, height: 4)
                            Spacer()
                        }
                        .frame(width: 0, height: 4)
                        Spacer().frame(width: spacingWidth)
                    }
                }
                .frame(width: majorTickSpacing)
            }
        }
    }
}
