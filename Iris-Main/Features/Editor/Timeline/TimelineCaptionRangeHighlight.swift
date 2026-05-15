import SwiftUI

/// Darkens the timeline band between two times (µs), aligned with clip coordinates.
struct TimelineCaptionRangeHighlight: View {
    let rangeUs: ClosedRange<Int64>
    let pixelsPerSecond: CGFloat
    let height: CGFloat

    var body: some View {
        let x = CGFloat(rangeUs.lowerBound) / 1_000_000.0 * pixelsPerSecond
        let width = CGFloat(rangeUs.upperBound - rangeUs.lowerBound) / 1_000_000.0 * pixelsPerSecond
        Rectangle()
            .fill(Color.black.opacity(0.38))
            .frame(width: max(width, 2), height: height)
            .offset(x: x)
            .allowsHitTesting(false)
    }
}
