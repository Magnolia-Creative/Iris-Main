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
        .padding(.vertical, .spacing(.sp2))
    }
}

private struct CaptionStyleEditorView: View {
    @ObservedObject var flow: CaptionsFlowController
    @ObservedObject var controller: TimelineController
    let groupId: String

    @State private var style: CaptionStyle = .modern
    @State private var hasBackground: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Caption style")
                .typography(.heading)
                .foregroundColor(Color.ds.text)
            HStack(spacing: .spacing(.sp2)) {
                ForEach(CaptionStyle.allCases, id: \.self) { s in
                    Button(s.rawValue.capitalized) {
                        style = s
                        flow.updateEditingGroup(style: s, hasBackground: hasBackground)
                    }
                    .buttonStyle(.bordered)
                }
            }
            Toggle("Background for readability", isOn: $hasBackground)
                .onChange(of: hasBackground) { _, v in
                    flow.updateEditingGroup(style: style, hasBackground: v)
                }
            Button("Done") { flow.finishStyleEditing() }
                .buttonStyle(.borderedProminent)
        }
        .onAppear {
            syncFromState()
        }
        .onChange(of: flow.phase) { _, _ in
            syncFromState()
        }
    }

    private func syncFromState() {
        guard let g = controller.state.captionGroups.first(where: { $0.groupId == groupId }) else { return }
        style = g.style
        hasBackground = g.hasBackground
    }
}
