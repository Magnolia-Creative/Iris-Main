import PhotosUI
import SwiftUI
internal import Combine

struct EditorContainerView: View {
    let timelineId: String
    @StateObject private var controller: TimelineController
    @StateObject private var renderBridge = TimelineRenderBridge()
    @State private var playbackController: PlaybackController?
    @State private var activeSpace: EditorSpace = .edit
    @State private var selectedPhotos: [PhotosPickerItem] = []
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

            EditorCanvasView(
                controller: controller,
                playbackController: playbackController,
                renderBridge: renderBridge,
                activeSpace: activeSpace
            )
            .frame(maxWidth: .infinity, maxHeight: canvasExpandsVertically ? .infinity : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpace)

            EditorTabBar(
                activeSpace: $activeSpace,
                isClipSelected: state.selectedClipId != nil,
                onSplitClip: { controller.splitSelectedClip() },
                onDeleteClip: { controller.deleteSelectedClip() }
            ) {
                ZStack {
                    switch activeSpace {
                    case .importMedia:
                        ImportPanelContent(controller: controller)
                            .transition(.opacity)
                    case .chat:
                        ChatPanelContent(controller: controller)
                            .transition(.opacity)
                    case .export:
                        ExportPanelContent(controller: controller)
                            .transition(.opacity)
                    case .edit:
                        EmptyView()
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: activeSpace)
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
        .onChange(of: activeSpace) { oldSpace, newSpace in
            EditorDebugTrace.log(
                "EditorContainerView",
                "activeSpace changed from=\(oldSpace.rawValue) to=\(newSpace.rawValue)"
            )
            EditorDebugTrace.end(
                "space-transition-\(newSpace.rawValue)",
                scope: "EditorContainerView",
                message: "activeSpace committed to \(newSpace.rawValue)"
            )
        }
        .photosPicker(
            isPresented: controller.binding(\.showingMediaPicker),
            selection: $selectedPhotos,
            maxSelectionCount: 20,
            matching: photosFilter(for: state.pendingImport?.kind)
        )
        .fileImporter(
            isPresented: controller.binding(\.showingFilePicker),
            allowedContentTypes: state.filePickerTypes(),
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .onChange(of: selectedPhotos) { _, items in
            guard !items.isEmpty else { return }
            let kind = controller.state.pendingImport?.kind ?? .video
            controller.importPickerItems(items, kind: kind)
            selectedPhotos = []
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

    private func photosFilter(for kind: TrackKind?) -> PHPickerFilter {
        switch kind {
        case .audio: return .videos
        default: return .any(of: [.videos, .images])
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        Task { await controller.importFiles(urls) }
    }
}
