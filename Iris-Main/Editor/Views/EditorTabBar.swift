import SwiftUI

struct EditorTabBar: View {
    @Binding var activeSpace: EditorSpace
    @Namespace private var tabNamespace

    var body: some View {
        HStack(spacing: .spacing(.sp1)) {
            ForEach(EditorSpace.allCases) { space in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        activeSpace = space
                    }
                } label: {
                    VStack(spacing: .spacing(.sp1)) {
                        Image(systemName: space.iconName)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(activeSpace == space ? Color.ds.accentFg : Color.ds.textMuted)

                        Text(space.rawValue)
                            .typography(.bodySmall)
                            .foregroundColor(activeSpace == space ? Color.ds.accentFg : Color.ds.textMuted)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, .spacing(.sp2))
                    .background {
                        if activeSpace == space {
                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                .fill(Color.ds.accentBg.opacity(0.15))
                                .matchedGeometryEffect(id: "tabIndicator", in: tabNamespace)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, .spacing(.sp2))
        .padding(.vertical, .spacing(.sp2))
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
        .padding(.horizontal, .spacing(.sp3))
    }
}
