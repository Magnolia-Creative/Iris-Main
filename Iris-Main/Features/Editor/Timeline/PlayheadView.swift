import SwiftUI

struct PlayheadView: View {
    var tint: Color = Color.ds.text

    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let timelineHeight = geometry.size.height

            Rectangle()
                .fill(tint)
                .frame(width: 1)
                .frame(height: timelineHeight)
                .position(x: centerX, y: timelineHeight / 2)
        }
    }
}
