import SwiftUI
internal import Combine

struct EditorContainerView: View {
    let timelineId: String
    @StateObject private var controller: TimelineController
    @StateObject private var renderBridge = TimelineRenderBridge()
    @State private var playbackController: PlaybackController?
    @State private var activeSpace: EditorSpace = .edit
    @Namespace private var editorNamespace
    @Environment(\.dismiss) private var dismiss

    init(timelineId: String) {
        self.timelineId = timelineId
        self._controller = StateObject(wrappedValue: TimelineController(timelineId: timelineId))
    }

    /// Canvas fills for edit/export; panels fill for import/chat.
    private var canvasExpandsVertically: Bool {
        activeSpace == .edit || activeSpace == .export
    }

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            editorHeaderBar

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
            .frame(maxWidth: .infinity, maxHeight: canvasExpandsVertically ? .infinity : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpace)

            EditorTabBar(
                activeSpace: $activeSpace,
                isClipSelected: state.selectedClipId != nil,
                onSplitClip: { controller.splitSelectedClip() },
                onDeleteClip: { controller.deleteSelectedClip() }
            ) {
                switch activeSpace {
                case .importMedia:
                    ImportPanelContent(controller: controller)
                case .chat:
                    ChatPanelContent(controller: controller)
                case .export:
                    ExportPanelContent(controller: controller)
                case .edit:
                    EmptyView()
                }
            }
            .frame(maxHeight: canvasExpandsVertically ? nil : .infinity)
            .padding(.horizontal, activeSpace != .edit ? .spacing(.sp3) : 0)
            .padding(.bottom, .spacing(.sp2))
        }
        .background(Color.ds.bg)
        .navigationBarHidden(true)
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

    private var editorHeaderBar: some View {
        ZStack {
            Text(controller.state.projectTitle)
                .typography(.body)
                .foregroundColor(Color.ds.text)

            HStack {
                Button {
                    dismiss()
                } label: {
                    HStack(spacing: .spacing(.sp1)) {
                        Image(systemName: "arrow.left")
                            .font(.system(size: 12, weight: .regular))
                            .frame(width: 12, height: 12)
                        Text("Home")
                            .typography(.bodySmall)
                    }
                    .foregroundColor(Color.ds.textMuted)
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(.horizontal, .spacing(.sp5))
        .padding(.vertical, .spacing(.sp2))
    }
}
