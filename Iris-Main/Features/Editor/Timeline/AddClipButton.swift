import SwiftUI

struct AddClipButton: View {
    let onTap: () -> Void
    private let size: CGFloat = .spacing(.sp8)

    var body: some View {
        Button(action: onTap) {
            ZStack {
                RoundedRectangle(cornerRadius: .spacing(.sp2))
                    .fill(Color.ds.bg.opacity(0.75))
                    .frame(width: size, height: size)
                    .overlay(RoundedRectangle(cornerRadius: .spacing(.sp2)).stroke(Color.ds.accentFg, lineWidth: 2))
                Image(systemName: "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(Color.ds.accentFg)
            }
            .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        }
        .buttonStyle(.plain)
    }
}
