import PhotosUI
import SwiftUI
internal import Combine

struct EditorContainerView: View {
    let timelineId: String
    let initialImportSeed: ImportedTimelineSeed?
    @StateObject private var controller: TimelineController
    @StateObject private var renderBridge = TimelineRenderBridge()
    @ObservedObject private var agentSessionViewModel: AgentViewModel
    @State private var playbackController: PlaybackController?
    @State private var activeSpace: EditorSpace = .edit
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @Environment(\.dismiss) private var dismiss
    private let hasAgentSession: Bool

    init(
        timelineId: String,
        initialImportSeed: ImportedTimelineSeed? = nil,
        agentSession: AgentViewModel? = nil
    ) {
        self.timelineId = timelineId
        self.initialImportSeed = initialImportSeed
        self._controller = StateObject(wrappedValue: TimelineController(timelineId: timelineId))
        self._agentSessionViewModel = ObservedObject(wrappedValue: agentSession ?? AgentViewModel())
        self.hasAgentSession = agentSession != nil
    }

    /// Canvas fills for edit/export; panels fill for import/chat.
    private var canvasExpandsVertically: Bool {
        isAgentCutReviewActive || activeSpace == .edit || activeSpace == .export
    }

    private var isAgentCutReviewActive: Bool {
        hasAgentSession
            && agentSessionViewModel.model.canLaunchEditorReview
            && controller.cutReview != nil
    }

    private var reviewFocusedClipIds: Set<String> {
        guard isAgentCutReviewActive else { return [] }
        return controller.cutReview?.focusedClipIds ?? []
    }

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            activeHeaderBar

            EditorCanvasView(
                controller: controller,
                playbackController: playbackController,
                renderBridge: renderBridge,
                activeSpace: activeSpace,
                reviewFocusedClipIds: reviewFocusedClipIds,
                isReviewInteractionDisabled: isAgentCutReviewActive
            )
            .frame(maxWidth: .infinity, maxHeight: canvasExpandsVertically ? .infinity : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpace)

            if isAgentCutReviewActive, let cutReview = controller.cutReview {
                TimelineCutReviewBar(
                    review: cutReview,
                    isSending: agentSessionViewModel.model.isSendingFeedback,
                    onApprove: { controller.approveCurrentCutReview() },
                    onApproveAll: {
                        controller.finishCutReview()
                        Task {
                            await agentSessionViewModel.approveTimeline()
                        }
                    },
                    onCancelCut: cutReview.currentItem?.canCancel == true
                        ? { controller.cancelCurrentCutReview() }
                        : nil,
                    onShowRepromptComposer: { controller.showCutReviewRepromptComposer() },
                    onHideRepromptComposer: { controller.hideCutReviewRepromptComposer() },
                    onRepromptTextChange: controller.updateCutReviewRepromptDraft(_:),
                    onSubmitReprompt: submitCutReviewReprompt
                )
                .padding(.horizontal, .spacing(.sp3))
                .padding(.bottom, .spacing(.sp3))
            } else {
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
        }
        .background(Color.ds.bg)
        .navigationBarHidden(true)
        .task {
            await controller.loadTimelineData()
            if let initialImportSeed {
                await controller.applyInitialImportSeedIfNeeded(initialImportSeed)
            }
            if hasAgentSession && agentSessionViewModel.model.canLaunchEditorReview {
                activeSpace = .edit
                controller.startCutReview()
            }
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
        .onDisappear {
            guard hasAgentSession else { return }
            Task {
                await agentSessionViewModel.closeIfNeeded()
            }
        }
        .onChange(of: agentSessionViewModel.model.pendingEditorSeed) { _, seed in
            guard hasAgentSession, let seed else { return }
            Task {
                await controller.applyAgentImportSeed(seed)
            }
        }
        .onChange(of: agentSessionViewModel.model.canLaunchEditorReview) { _, canLaunchEditorReview in
            guard hasAgentSession else { return }
            if canLaunchEditorReview {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    activeSpace = .edit
                }
                controller.startCutReview()
            } else {
                controller.finishCutReview()
            }
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

    @ViewBuilder
    private var activeHeaderBar: some View {
        if isAgentCutReviewActive {
            cutReviewHeaderBar
        } else {
            editorHeaderBar
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

    private var cutReviewHeaderBar: some View {
        let currentItem = controller.cutReview?.currentItem

        return ZStack {
            VStack(spacing: 2) {
                Text("Review Agent Timeline")
                    .typography(.body)
                    .foregroundColor(Color.ds.text)

                Text(controller.cutReview?.progressLabel ?? "Review")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }

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

                if let currentItem {
                    Text(
                        "\(TimeFormatter.formatTime(currentItem.startTimeUs)) - \(TimeFormatter.formatTime(currentItem.endTimeUs))"
                    )
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
                }
            }
        }
        .padding(.horizontal, .spacing(.sp5))
        .padding(.top, .spacing(.sp2))
        .padding(.bottom, .spacing(.sp1))
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

    private func submitCutReviewReprompt() {
        guard hasAgentSession else { return }
        guard let review = controller.cutReview else { return }
        let prompt = review.repromptDraft.trimmedForTransport
        guard !prompt.isEmpty else { return }

        controller.hideCutReviewRepromptComposer()
        agentSessionViewModel.updateFeedbackDraft(prompt)
        Task {
            await agentSessionViewModel.submitFeedback()
        }
    }
}
