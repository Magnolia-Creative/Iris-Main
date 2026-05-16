import SwiftUI

struct CaptionsChromeView: View {
    @ObservedObject var flow: CaptionsFlowController
    @ObservedObject var controller: TimelineController

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            if let message = flow.validationMessage, !message.isEmpty {
                Text(message)
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.danger)
            }

            switch flow.phase {
            case .idle:
                EmptyView()
            case .processing:
                ProgressView()
                Text("Generating captions…")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            case .editingStyle(let groupId):
                CaptionStyleEditorView(flow: flow, controller: controller, groupId: groupId)
            }
        }
    }
}

private struct CaptionStyleEditorView: View {
    @ObservedObject var flow: CaptionsFlowController
    @ObservedObject var controller: TimelineController
    let groupId: String

    @Environment(\.colorScheme) private var colorScheme

    @State private var style: CaptionStyle = .modern
    @State private var hasBackground: Bool = false
    @State private var carouselPage: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Caption style")
                .typography(.heading)
                .foregroundColor(Color.ds.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            TabView(selection: $carouselPage) {
                stylePage
                    .tag(0)
                backgroundPage
                    .tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 72)

            HStack(alignment: .center, spacing: .spacing(.sp3)) {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { index in
                        Capsule()
                            .fill(carouselPage == index ? Color.ds.accentFg : Color.ds.textMuted.opacity(0.35))
                            .frame(width: carouselPage == index ? 14 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.2), value: carouselPage)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text("Caption settings page \(carouselPage + 1) of 2"))

                Spacer(minLength: 0)

                Button {
                    flow.finishStyleEditing()
                } label: {
                    Text("Done")
                        .typography(.action)
                        .foregroundColor(.white)
                        .padding(.horizontal, .spacing(.sp4))
                        .padding(.vertical, .spacing(.sp2))
                        .background(Color.ds.accentBg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Done"))
            }
        }
        .onAppear {
            syncFromState()
        }
        .onChange(of: flow.phase) { _, _ in
            syncFromState()
        }
    }

    private var stylePage: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: .spacing(.sp2)) {
                ForEach(CaptionStyle.allCases, id: \.self) { option in
                    styleOptionPill(option)
                }
            }
            .frame(maxHeight: .infinity, alignment: .center)
            .padding(.vertical, 2)
        }
    }

    private func styleOptionPill(_ option: CaptionStyle) -> some View {
        let selected = style == option
        return Button {
            style = option
            flow.updateEditingGroup(style: option, hasBackground: hasBackground)
        } label: {
            Text(option.rawValue.capitalized)
                .typography(.bodySmall)
                .foregroundColor(selected ? Color.ds.accentFg : Color.ds.text)
                .padding(.horizontal, .spacing(.sp3))
                .padding(.vertical, .spacing(.sp2))
                .editorRegularGlassEffect(
                    tint: Color.white.opacity(colorScheme == .dark ? 0.06 : 0.14),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(selected ? Color.ds.accentFg : Color.ds.border, lineWidth: selected ? 2 : 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var backgroundPage: some View {
        HStack(alignment: .center, spacing: .spacing(.sp2)) {
            Text("Background for readability")
                .typography(.bodySmall)
                .foregroundColor(Color.ds.text)
                .multilineTextAlignment(.leading)
            Spacer(minLength: .spacing(.sp2))
            Toggle("", isOn: $hasBackground)
                .labelsHidden()
                .tint(Color.ds.accentFg)
                .onChange(of: hasBackground) { _, newValue in
                    flow.updateEditingGroup(style: style, hasBackground: newValue)
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, .spacing(.sp1))
    }

    private func syncFromState() {
        guard let g = controller.state.captionGroups.first(where: { $0.groupId == groupId }) else { return }
        style = g.style
        hasBackground = g.hasBackground
    }
}
