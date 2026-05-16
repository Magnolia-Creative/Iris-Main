import PhotosUI
import SwiftUI
internal import Combine

struct EditorContainerView: View {
    let timelineId: String
    let initialImportSeed: ImportedTimelineSeed?
    @StateObject private var controller: TimelineController
    @StateObject private var captionsFlow = CaptionsFlowController()
    @StateObject private var editorPromptBarViewModel: EditorPromptBarViewModel
    @StateObject private var renderBridge = TimelineRenderBridge()
    @ObservedObject private var agentSessionViewModel: AgentViewModel
    @State private var playbackController: PlaybackController?
    @State private var activeSpace: EditorSpace = .edit
    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var editorImportRequest: EditorImportRequest?
    @Namespace private var bottomChromeNamespace
    @Environment(\.dismiss) private var dismiss
    private let hasAgentSession: Bool

    init(
        timelineId: String,
        initialImportSeed: ImportedTimelineSeed? = nil,
        agentSession: AgentViewModel? = nil
    ) {
        self.timelineId = timelineId
        self.initialImportSeed = initialImportSeed
        let timelineController = TimelineController(timelineId: timelineId)
        self._controller = StateObject(wrappedValue: timelineController)
        self._editorPromptBarViewModel = StateObject(
            wrappedValue: EditorPromptBarViewModel(
                contextProvider: {
                    timelineController.state.makeIntentCompilerContext()
                },
                needsIntentTranscriptDatabaseWait: { prompt in
                    timelineController.needsIntentTranscriptDatabaseWait(for: prompt)
                },
                waitForTranscriptReadinessIfNeeded: { prompt in
                    try await timelineController.waitForIntentTranscriptReadinessIfNeeded(prompt: prompt)
                },
                applyActions: { actions in
                    timelineController.applyActions(actions)
                },
                attemptStartPromptActionReview: { actions, prompt in
                    timelineController.startPromptActionReview(actions: actions, prompt: prompt)
                }
            )
        )
        self._agentSessionViewModel = ObservedObject(wrappedValue: agentSession ?? AgentViewModel())
        self.hasAgentSession = agentSession != nil
    }

    /// Canvas fills for edit/export; panels fill for import.
    private var canvasExpandsVertically: Bool {
        isAgentCutReviewActive || isPromptActionReviewActive || activeSpace == .edit || activeSpace == .export
    }

    private var isAgentCutReviewActive: Bool {
        hasAgentSession
            && agentSessionViewModel.model.canLaunchEditorReview
            && controller.cutReview != nil
    }

    private var isPromptActionReviewActive: Bool {
        controller.promptActionReview != nil
    }

    private var reviewFocusedClipIds: Set<String> {
        if isAgentCutReviewActive {
            return controller.cutReview?.focusedClipIds ?? []
        }
        if isPromptActionReviewActive {
            return controller.promptActionPreview?.focusClipIds ?? []
        }
        return []
    }

    private var isTimelineReviewInteractionDisabled: Bool {
        isAgentCutReviewActive || isPromptActionReviewActive
    }

    private var selectedClipColorFilter: ClipColorFilter {
        guard let clipId = controller.state.selectedClipId else { return .neutral }
        return controller.clipColorFilter(for: clipId)
    }

    private var selectedClipVolume: ClipVolume {
        guard let clipId = controller.state.selectedClipId else { return .neutral }
        return controller.clipVolume(for: clipId)
    }

    @ViewBuilder
    private var editorTabBarChrome: some View {
        EditorGlassEffectContainer(spacing: 20) {
            ZStack(alignment: .bottom) {
                EditorTabBar(
                    activeSpace: $activeSpace,
                    isClipSelected: controller.state.selectedClipId != nil,
                    promptBarIsTakingOver: editorPromptBarViewModel.isTakingOver,
                    selectedClipColorFilter: selectedClipColorFilter,
                    onSplitClip: {
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.applyActions([
                            Action.splitClip(
                                timelineId: controller.state.timelineId,
                                clipId: clipId,
                                atTimeUs: controller.state.currentTimeAtCenter
                            )
                        ])
                    },
                    onDeleteClip: {
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.applyActions([
                            Action.removeClip(timelineId: controller.state.timelineId, clipId: clipId)
                        ])
                    },
                    onSetClipColorFilter: { filter in
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.setClipColorFilter(clipId: clipId, filter: filter)
                    },
                    onResetClipColorFilter: {
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.resetClipColorFilter(clipId: clipId)
                    },
                    selectedClipVolume: selectedClipVolume,
                    onSetClipVolume: { volume in
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.setClipVolume(clipId: clipId, volume: volume)
                    },
                    onResetClipVolume: {
                        guard let clipId = controller.state.selectedClipId else { return }
                        controller.resetClipVolume(clipId: clipId)
                    },
                    onDeselectClip: {
                        controller.clearSelection()
                    },
                    isPromptActionReviewActive: isPromptActionReviewActive,
                    promptActionReviewReplacement: promptActionReviewReplacement(),
                    promptReviewReplacementSlotIdentity: promptReviewReplacementSlotIdentity,
                    bottomReservedSpace: EditorBottomNavBar.totalHeight,
                    chromeMaxWidth: activeSpace == .edit
                        ? EditorBottomNavBar.containerWidth + .spacing(.sp4) * 2
                        : nil,
                    promptBar: { isClipSelected, micNamespace in
                        EditorPromptBarView(
                            viewModel: editorPromptBarViewModel,
                            isClipSelected: isClipSelected,
                            micNamespace: micNamespace
                        )
                    },
                    captionsEditContent: captionsFlow.isCaptionsChromeActive
                        ? AnyView(CaptionsChromeView(flow: captionsFlow, controller: controller))
                        : nil,
                    isCaptionsChromeActive: captionsFlow.isCaptionsChromeActive,
                    isCaptionsToolExpanded: captionsFlow.expandedStyleTool != nil
                ) {
                    ZStack {
                        switch activeSpace {
                        case .importMedia:
                            ImportPanelContent(
                                controller: controller,
                                onOpenVideoImport: {
                                    presentEditorImport(.library)
                                }
                            )
                            .transition(.opacity)
                        case .export:
                            ExportPanelContent(controller: controller)
                                .transition(.opacity)
                        case .edit:
                            EmptyView()
                        }
                    }
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: activeSpace)
                }
                .frame(maxHeight: canvasExpandsVertically ? nil : .infinity)
                .padding(.horizontal, activeSpace == .edit ? .spacing(.sp4) : .spacing(.sp3))

                EditorBottomNavBar(activeSpace: $activeSpace)
            }
        }
        .matchedGeometryEffect(id: "editor-bottom-shell", in: bottomChromeNamespace)
        .transition(.opacity)
        .padding(.bottom, .spacing(.sp2))
    }

    var body: some View {
        VStack(spacing: 0) {
            activeHeaderBar

            EditorCanvasView(
                controller: controller,
                playbackController: playbackController,
                renderBridge: renderBridge,
                activeSpace: activeSpace,
                captionsFlow: captionsFlow,
                onAddSelection: handleEditorAddSelection(kind:source:),
                reviewFocusedClipIds: reviewFocusedClipIds,
                isReviewInteractionDisabled: isTimelineReviewInteractionDisabled,
                promptActionPreview: controller.promptActionPreview
            )
            .frame(maxWidth: .infinity, maxHeight: canvasExpandsVertically ? .infinity : nil)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: activeSpace)

            ZStack(alignment: .bottom) {
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
                    .matchedGeometryEffect(id: "editor-bottom-shell", in: bottomChromeNamespace)
                    .transition(.opacity)
                    .padding(.horizontal, .spacing(.sp3))
                    .padding(.bottom, .spacing(.sp3))
                } else {
                    editorTabBarChrome
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: isAgentCutReviewActive)
        }
        .background(Color.ds.bg)
        .navigationBarHidden(true)
        .sheet(item: $editorImportRequest) { request in
            NavigationStack {
                EditorClipImportSheet(timelineId: timelineId) { media in
                    applyImportedMedia(media, for: request.destination)
                }
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .onAppear {
            captionsFlow.attach(controller)
        }
        .alert(
            "Captions",
            isPresented: Binding(
                get: { captionsFlow.captionsAlert != nil },
                set: { if !$0 { captionsFlow.captionsAlert = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                captionsFlow.captionsAlert = nil
            }
        } message: {
            Text(captionsFlow.captionsAlert ?? "")
        }
        .task {
            await MainActor.run {
                SemanticSearchViewModel.shared.prewarmEmbeddingServicesIfNeeded()
            }
        }
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
        .onReceive(NotificationCenter.default.publisher(for: .irisMediaTranscriptDidPersist)) { notification in
            guard let mediaId = notification.userInfo?["mediaId"] as? String else { return }
            Task { @MainActor in
                controller.refreshMediaFromDatabaseIfOnTimeline(mediaId: mediaId)
            }
        }
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                controller.clearSelection()
                captionsFlow.cancelStyleEditing()
            }
        }
        .onDisappear {
            editorPromptBarViewModel.tearDown()
            controller.finishPromptActionReview()
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
            if oldSpace == .edit, newSpace != .edit {
                editorPromptBarViewModel.tearDown()
                controller.finishPromptActionReview()
            }
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
            matching: photosFilter(for: controller.state.pendingImport?.kind)
        )
        .fileImporter(
            isPresented: controller.binding(\.showingFilePicker),
            allowedContentTypes: controller.state.filePickerTypes(),
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

    /// Token for animating the leading tab bar slot between color substeps and sequence review.
    private var promptReviewReplacementSlotIdentity: String {
        guard let session = controller.promptActionReview else { return "none" }
        if let color = session.promptColorReview,
           color.fieldIndex < color.orderedFieldKeys.count {
            let key = color.orderedFieldKeys[color.fieldIndex]
            return "color:\(session.currentIndex):\(color.fieldIndex):\(key)"
        }
        if session.currentAction?.isPromptSequenceReviewable == true {
            return "seq:\(session.currentIndex)"
        }
        return "review:\(session.currentIndex)"
    }

    private func promptActionReviewReplacement() -> AnyView? {
        guard let session = controller.promptActionReview else { return nil }

        if let colorState = session.promptColorReview,
           case let .updateClipColorFilter(clipId, _) = session.currentAction?.payload,
           colorState.fieldIndex < colorState.orderedFieldKeys.count {
            let key = colorState.orderedFieldKeys[colorState.fieldIndex]
            guard let field = ClipColorFilterPromptField(patchKey: key) else {
                return AnyView(
                    TimelinePromptActionReviewPromptSlot(
                        session: session,
                        preview: controller.promptActionPreview,
                        message: controller.promptActionReviewMessage,
                        onApprove: { controller.approveCurrentPromptAction() },
                        onReject: { controller.rejectCurrentPromptAction() },
                        onReprompt: {
                            let original = controller.discardPromptActionReviewReturningPrompt() ?? ""
                            let draft = original.isEmpty ? "" : "\(original)\n"
                            editorPromptBarViewModel.openRepromptDraft(draft)
                        }
                    )
                )
            }

            let binding = Binding<Float>(
                get: { field.floatValue(in: controller.clipColorFilter(for: clipId)) },
                set: { newValue in
                    var filter = controller.clipColorFilter(for: clipId)
                    field.set(newValue, on: &filter)
                    controller.setClipColorFilter(clipId: clipId, filter: filter)
                }
            )

            return AnyView(
                TimelinePromptColorReviewSlot(
                    propertyTitle: field.displayTitle,
                    sliderRange: field.sliderRange,
                    sliderValue: binding,
                    onReset: { controller.resetCurrentPromptColorReviewField() },
                    onConfirm: { controller.confirmCurrentPromptColorSubstep() }
                )
            )
        }

        return AnyView(
            TimelinePromptActionReviewPromptSlot(
                session: session,
                preview: controller.promptActionPreview,
                message: controller.promptActionReviewMessage,
                onApprove: { controller.approveCurrentPromptAction() },
                onReject: { controller.rejectCurrentPromptAction() },
                onReprompt: {
                    let original = controller.discardPromptActionReviewReturningPrompt() ?? ""
                    let draft = original.isEmpty ? "" : "\(original)\n"
                    editorPromptBarViewModel.openRepromptDraft(draft)
                }
            )
        )
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
        return ZStack {
            Text("Review Changes")
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

                if let cutReview = controller.cutReview {
                    Text("Cut \(cutReview.currentIndex + 1)/\(cutReview.items.count)")
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
        case .captions: return .any(of: [.videos, .images])
        default: return .any(of: [.videos, .images])
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, !urls.isEmpty else { return }
        Task { await controller.importFiles(urls) }
    }

    private func handleEditorAddSelection(kind: TrackKind, source: ImportSource) {
        if kind == .overlay && source == .caption {
            captionsFlow.startAutoCaptionsForWholeTimeline()
            return
        }
        guard kind == .video, source == .photos else {
            controller.handleAddSelection(kind: kind, source: source)
            return
        }

        presentEditorImport(.timeline(kind: kind))
    }

    private func presentEditorImport(_ destination: EditorImportRequest.Destination) {
        editorImportRequest = EditorImportRequest(destination: destination)
    }

    @MainActor
    private func applyImportedMedia(_ media: [Media], for destination: EditorImportRequest.Destination) {
        guard !media.isEmpty else { return }

        switch destination {
        case .library:
            for item in media {
                controller.updateMedia(item)
            }
        case .timeline(let kind):
            controller.ingestMedia(media, kind: kind)
        }

        controller.generateThumbnailStrips(for: media)
        controller.syncSemanticIndexForImportedMedia()
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

private struct EditorImportRequest: Identifiable {
    enum Destination {
        case library
        case timeline(kind: TrackKind)
    }

    let id = UUID()
    let destination: Destination
}

private struct EditorClipImportSheet: View {
    let timelineId: String
    let onAdd: @MainActor ([Media]) -> Void
    @StateObject private var viewModel: ImportBrowserViewModel

    init(timelineId: String, onAdd: @escaping @MainActor ([Media]) -> Void) {
        self.timelineId = timelineId
        self.onAdd = onAdd
        _viewModel = StateObject(wrappedValue: ImportBrowserViewModel(timelineId: timelineId))
    }

    var body: some View {
        ClipImportSheetView(
            viewModel: viewModel,
            onAdd: {
                let media = await viewModel.finalizeSelectedMediaImports()
                await MainActor.run {
                    onAdd(media)
                }
            }
        )
        .task {
            viewModel.updateProcessingMode(.embeddingsAndAgentPreprocessing)
        }
    }
}
