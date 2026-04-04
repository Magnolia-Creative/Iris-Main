import SwiftUI

struct PlayheadView: View {
    var body: some View {
        GeometryReader { geometry in
            let centerX = geometry.size.width / 2
            let timelineHeight = geometry.size.height

            Rectangle()
                .fill(Color.ds.text)
                .frame(width: 1)
                .frame(height: timelineHeight)
                .position(x: centerX, y: timelineHeight / 2)
        }
    }
}
