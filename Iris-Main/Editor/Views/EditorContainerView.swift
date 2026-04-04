import SwiftUI
internal import Combine

struct EditorContainerView: View {
    let timelineId: String
    @StateObject private var controller: TimelineController
    @StateObject private var renderBridge = TimelineRenderBridge()
    @State private var playbackController: PlaybackController?
    @State private var activeSpace: EditorSpace = .edit
    @Namespace private var editorNamespace

    init(timelineId: String) {
        self.timelineId = timelineId
        self._controller = StateObject(wrappedValue: TimelineController(timelineId: timelineId))
    }

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            Group {
                switch activeSpace {
                case .importMedia:
                    ImportSpaceView(
                        controller: controller,
                        playbackController: playbackController,
                        renderBridge: renderBridge,
                        namespace: editorNamespace
                    )
                case .edit:
                    EditSpaceView(
                        controller: controller,
                        playbackController: playbackController,
                        renderBridge: renderBridge,
                        namespace: editorNamespace
                    )
                case .chat:
                    ChatSpaceView(
                        controller: controller,
                        playbackController: playbackController,
                        renderBridge: renderBridge,
                        namespace: editorNamespace
                    )
                case .export:
                    ExportSpaceView(
                        controller: controller,
                        playbackController: playbackController,
                        renderBridge: renderBridge,
                        namespace: editorNamespace
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpace)

            EditorTabBar(activeSpace: $activeSpace)
                .padding(.bottom, .spacing(.sp2))
        }
        .background(Color.ds.bg)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                BackButton()
            }
            ToolbarItem(placement: .principal) {
                Text(state.projectTitle)
                    .typography(.body)
                    .foregroundColor(Color.ds.text)
            }
        }
        .task {
            await controller.loadTimelineData()
            let pc = PlaybackController(
                statePublisher: controller.$state.eraseToAnyPublisher(),
                actions: controller
            )
            playbackController = pc
            renderBridge.bind(to: controller)
        }
        .onTapGesture {
            controller.clearSelection()
        }
    }
}

private struct BackButton: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Button { dismiss() } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Color.ds.text)
        }
    }
}
