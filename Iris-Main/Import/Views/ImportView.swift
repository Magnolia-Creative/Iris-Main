import Photos
import SwiftUI

struct ImportView: View {
    let timelineId: String?
    @StateObject private var viewModel: ImportBrowserViewModel
    @StateObject private var agentViewModel = AgentViewModel()
    @State private var editorLaunchDestination: EditorLaunchDestination?
    @State private var showsAgentView = false
    @State private var showsImportSheet = false
    @FocusState private var isPromptFocused: Bool
    @Namespace private var transitionNamespace
    private let ctaButtonHeight: CGFloat = 64
    private let ctaFadeExtension: CGFloat = .spacing(.sp4)

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: .spacing(.sp2)),
        count: 3
    )

    private var ctaContainerHeight: CGFloat {
        ctaButtonHeight + (ctaFadeExtension * 2)
    }

    private var ctaFadeStop: Double {
        Double(ctaFadeExtension / ctaContainerHeight)
    }

    init(timelineId: String? = nil) {
        self.timelineId = timelineId
        _viewModel = StateObject(wrappedValue: ImportBrowserViewModel(timelineId: timelineId))
    }

    var body: some View {
        ZStack {
            Color.ds.bg
                .ignoresSafeArea()

            if showsAgentView {
                AgentView(
                    viewModel: agentViewModel,
                    transitionNamespace: transitionNamespace,
                    secondaryContentOpacity: 1,
                    promptIsSource: false
                )
            } else {
                editingContent
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !showsAgentView {
                bottomCTA
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editorLaunchDestination) { destination in
            EditorContainerView(
                timelineId: destination.timelineId,
                initialImportSeed: destination.seed,
                agentSession: agentViewModel
            )
        }
        .sheet(isPresented: $showsImportSheet) {
            NavigationStack {
                ClipImportSheetView(viewModel: viewModel)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .task {
            await viewModel.loadLibraryIfNeeded()
        }
        .onChange(of: viewModel.model.isPreparingAgentTransition) { _, shouldPrepare in
            guard shouldPrepare,
                  let response = viewModel.model.ingestResponse else { return }

            agentViewModel.configure(
                promptText: viewModel.model.prompt.trimmedText,
                videos: viewModel.model.committedVideos,
                ingestResponse: response,
                ingestEndpoint: AppConfiguration.agentSessionEndpoint
            )

            withAnimation(.spring(response: 0.45, dampingFraction: 0.9)) {
                showsAgentView = true
            }
            viewModel.finishPreparingAgentTransition()
        }
        .onChange(of: agentViewModel.model.canLaunchEditorReview) { _, canLaunchEditorReview in
            guard canLaunchEditorReview, let seed = agentViewModel.model.pendingEditorSeed else { return }
            guard let resolvedTimelineID = resolveEditorTimelineID(preferredTimelineID: timelineId) else {
                return
            }

            editorLaunchDestination = EditorLaunchDestination(
                timelineId: resolvedTimelineID,
                seed: seed
            )
        }
        .onDisappear {
            Task {
                guard editorLaunchDestination == nil else { return }
                await agentViewModel.closeIfNeeded()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var editingContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: .spacing(.sp9)) {
                heroSection
                importSection
                promptSection
            }
            .padding(.horizontal, .sp4)
            .padding(.top, .sp3)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(height: 24)

            Text("Build your edit")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("Import multiple videos, add a prompt, then let Iris compress the audio and upload the batch for editing.")
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)
                .frame(maxWidth: 320, alignment: .leading)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Import videos")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if let loadErrorMessage = viewModel.model.loadErrorMessage {
                Text(loadErrorMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            } else {
                Text(importStatusMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(committedClipsWithURLs) { clip in
                    ImportedVideoTile(videoURL: clip.originalURL!)
                        .importVideoTileTransition(id: clip.localKey, in: transitionNamespace, isSource: true)
                }

                Button {
                    showsImportSheet = true
                } label: {
                    AddVideoTile()
                }
                .buttonStyle(.plain)
            }
        }
        .importVideosSectionTransition(in: transitionNamespace, isSource: true)
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Editing prompt")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            PromptCardContainer {
                ZStack(alignment: .topLeading) {
                    TextEditor(
                        text: Binding(
                            get: { viewModel.model.prompt.text },
                            set: { viewModel.updatePromptMessage($0) }
                        )
                    )
                    .typographyStyle(.body)
                    .foregroundStyle(Color.ds.text)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: ImportPromptCardMetrics.minHeight)
                    .tint(Color.ds.accentFg)
                    .focused($isPromptFocused)

                    if case .empty(let hint) = viewModel.model.prompt.status {
                        Text(hint)
                            .typography(.body)
                            .foregroundStyle(Color.ds.textMuted)
                            .padding(.top, 8)
                            .padding(.horizontal, 5)
                            .allowsHitTesting(false)
                    }
                }
            }
            .importPromptCardTransition(in: transitionNamespace, isSource: true)

            if case .invalid(let message) = viewModel.model.prompt.status {
                Text(message)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            }

            FlowLayout(spacing: .spacing(.sp2), lineSpacing: .spacing(.sp2)) {
                ForEach(viewModel.model.prompt.suggestions, id: \.self) { suggestion in
                    SuggestionChip(title: suggestion) {
                        viewModel.applyPromptSuggestion(suggestion)
                    }
                }
            }
        }
    }

    private var bottomCTA: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0), location: 0),
                    .init(color: Color.black.opacity(0.44), location: ctaFadeStop),
                    .init(color: Color.black.opacity(0.44), location: 1 - ctaFadeStop),
                    .init(color: Color.black.opacity(0), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: ctaContainerHeight)
            .padding(.horizontal, .sp4)
            .allowsHitTesting(false)

            Button(action: startEditing) {
                HStack(spacing: .spacing(.sp2)) {
                    Text(viewModel.model.isAwaitingAgentStart ? "Processing..." : "Start editing")
                    Image(systemName: viewModel.model.isAwaitingAgentStart ? "arrow.up.circle" : "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
            .buttonStyle(AnimatedPrimaryButtonStyle(isEnabled: viewModel.model.canRequestAgentStart))
            .disabled(!viewModel.model.canRequestAgentStart || viewModel.model.isAwaitingAgentStart)
            .padding(.horizontal, .sp4)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ctaContainerHeight)
    }

    private var committedClipsWithURLs: [ImportClipProcessingItem] {
        viewModel.model.clips.filter { $0.isSelected && $0.isCommitted && $0.originalURL != nil }
    }

    private var importStatusMessage: String {
        let committed = viewModel.model.committedClipCount
        if committed == 0 {
            return "Import videos, add a prompt, then start editing to compress the audio and upload it."
        }
        return "\(committed) video\(committed == 1 ? "" : "s") ready for compression and upload."
    }

    private func startEditing() {
        guard viewModel.model.canRequestAgentStart else { return }
        isPromptFocused = false
        viewModel.requestAgentStart()
    }

    private func resolveEditorTimelineID(preferredTimelineID: String?) -> String? {
        if let preferredTimelineID {
            return preferredTimelineID
        }

        let project = Project(name: "AI Assembly")
        do {
            try DatabaseManager.shared.create(project)
            let library = MediaLibrary(projectId: project.projectId)
            try DatabaseManager.shared.create(library)
            let timeline = try DatabaseManager.shared.createTimeline(forProjectId: project.projectId)
            return timeline.timelineId
        } catch {
            return nil
        }
    }
}

struct ClipImportSheetView: View {
    @ObservedObject var viewModel: ImportBrowserViewModel
    var addButtonTitle = "Add"
    var addButtonEnabled: Bool? = nil
    var onAdd: (() async -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var isSubmitting = false

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 2),
        count: 3
    )

    var body: some View {
        ZStack {
            Color.ds.bg
                .ignoresSafeArea()

            VStack(spacing: 0) {
                albumTabBar

                ScrollView(showsIndicators: false) {
                    LazyVGrid(columns: gridColumns, spacing: 2) {
                        ForEach(viewModel.model.visibleAssets) { asset in
                            Button {
                                viewModel.toggleSelection(for: asset.id)
                            } label: {
                                ImportAssetCell(
                                    asset: asset,
                                    selectionNumber: selectionNumber(for: asset.id)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .navigationTitle(currentAlbumTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(Color.ds.text)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(isSubmitting ? "Adding..." : addButtonTitle) {
                    submitSelection()
                }
                .foregroundStyle(Color.ds.accentFg)
                .fontWeight(.semibold)
                .disabled(canSubmit == false)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.model.selectedClipCount > 0 {
                selectionBar
            }
        }
        .task {
            await viewModel.loadLibraryIfNeeded()
        }
    }

    private var currentAlbumTitle: String {
        viewModel.model.albums.first(where: { $0.id == viewModel.model.selectedAlbumID })?.title ?? "Videos"
    }

    private var albumTabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(viewModel.model.albums) { album in
                    Button {
                        viewModel.selectAlbum(album.id)
                    } label: {
                        Text(album.title)
                            .font(.system(size: 15, weight: viewModel.model.selectedAlbumID == album.id ? .semibold : .regular))
                            .foregroundStyle(viewModel.model.selectedAlbumID == album.id ? Color.ds.text : Color.ds.textMuted)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .background(Color.ds.surface)
        .overlay(alignment: .bottom) {
            Divider().overlay(Color.ds.border)
        }
    }

    private var selectionBar: some View {
        HStack {
            Spacer()
            Text("\(viewModel.model.selectedClipCount) selected")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Color.ds.text)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Divider().overlay(Color.ds.border)
        }
    }

    private func selectionNumber(for assetID: String) -> Int? {
        let selectedClips = viewModel.model.clips.filter(\.isSelected)
        guard let index = selectedClips.firstIndex(where: { $0.assetLocalIdentifier == assetID }) else {
            return nil
        }
        return index + 1
    }

    private var canSubmit: Bool {
        let baseEnabled = addButtonEnabled ?? (viewModel.model.selectedClipCount > 0)
        return baseEnabled && !isSubmitting
    }

    private func submitSelection() {
        guard canSubmit else { return }

        guard let onAdd else {
            dismiss()
            return
        }

        isSubmitting = true
        Task {
            await onAdd()
            await MainActor.run {
                isSubmitting = false
                dismiss()
            }
        }
    }
}

private struct ImportAssetCell: View {
    let asset: ImportBrowserAsset
    let selectionNumber: Int?

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topTrailing) {
                ImportAssetThumbnailView(assetLocalIdentifier: asset.id)
                    .frame(width: geo.size.width, height: geo.size.width)
                    .clipped()

                if !asset.durationText.isEmpty {
                    Text(asset.durationText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(6)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }

                if let number = selectionNumber {
                    ZStack {
                        Circle()
                            .fill(Color.ds.accentBg)
                            .frame(width: 24, height: 24)
                        Text("\(number)")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.white)
                    }
                    .padding(5)
                } else {
                    Circle()
                        .strokeBorder(Color.white.opacity(0.7), lineWidth: 1.5)
                        .frame(width: 24, height: 24)
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

private struct ImportAssetThumbnailView: View {
    let assetLocalIdentifier: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Rectangle()
                    .fill(Color.ds.surface)
                    .overlay(
                        Image(systemName: "film")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(Color.ds.textMuted)
                    )
            }
        }
        .task(id: assetLocalIdentifier) {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetLocalIdentifier], options: nil)
            guard let asset = fetchResult.firstObject else { return }
            image = await MediaImportService.shared.requestThumbnail(
                for: asset,
                targetSize: CGSize(width: 420, height: 420)
            )
        }
    }
}

private struct EditorLaunchDestination: Identifiable, Hashable {
    let timelineId: String
    let seed: ImportedTimelineSeed

    var id: String {
        timelineId
    }

    static func == (lhs: EditorLaunchDestination, rhs: EditorLaunchDestination) -> Bool {
        lhs.timelineId == rhs.timelineId
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(timelineId)
    }
}

private struct AddVideoTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ds.accentFg)

            Text("Add video")
                .typography(.body)
                .foregroundStyle(Color.ds.accentFg)
        }
        .padding(.sp3)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 136)
        .background(Color.ds.surface.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.accentFg, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }
}

private struct SuggestionChip: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(
                    Capsule()
                        .stroke(Color.ds.border, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

private struct AnimatedPrimaryButtonStyle: ButtonStyle {
    let isEnabled: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typographyStyle(.action)
            .foregroundStyle(Color.ds.text)
            .frame(height: 64)
            .background {
                AnimatedPrimaryButtonBackground()
            }
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct AnimatedPrimaryButtonBackground: View {
    @State private var startedAt = Date.now
    private let cycleDuration = 2.8

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 60.0)) { context in
            let shape = RoundedRectangle(cornerRadius: .spacing(.sp4))
            let phase = BorderTrailPhase(
                cycleProgress: cycleProgress(at: context.date),
                maxLength: 0.19
            )

            shape
                .fill(Color.ds.accentBg)
                .overlay {
                    shape
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 1.25)
                }
                .overlay {
                    ButtonBorderTrail(phase: phase)
                }
        }
        .allowsHitTesting(false)
    }

    private func cycleProgress(at date: Date) -> Double {
        let loop = date.timeIntervalSince(startedAt) / cycleDuration
        return loop.truncatingRemainder(dividingBy: 1)
    }
}

private struct BorderTrailPhase {
    let head: CGFloat
    let tail: CGFloat
    let intensity: CGFloat
    let coreLineWidth: CGFloat
    let glowLineWidth: CGFloat
    let glowRadius: CGFloat

    init(cycleProgress: Double, maxLength: CGFloat) {
        let easedHead = 0.5 - (cos(cycleProgress * .pi) * 0.5)
        let energy = pow(max(0.0, sin(cycleProgress * .pi)), 1.15)
        let trailLength = maxLength * CGFloat(energy)

        head = CGFloat(easedHead)
        tail = head - trailLength
        intensity = CGFloat(energy)
        coreLineWidth = 2.25 + (1.35 * CGFloat(energy))
        glowLineWidth = 6.5 + (3.25 * CGFloat(energy))
        glowRadius = 2 + (4.5 * CGFloat(energy))
    }
}

private struct ButtonBorderTrail: View {
    let phase: BorderTrailPhase

    var body: some View {
        if phase.intensity > 0.0001 {
            ZStack {
                wrappedTrail(
                    lineWidth: phase.glowLineWidth,
                    opacity: Double(phase.intensity) * 0.42
                )
                .blur(radius: phase.glowRadius)

                wrappedTrail(
                    lineWidth: phase.coreLineWidth,
                    opacity: Double(phase.intensity) * 0.95
                )
            }
            .blendMode(.screen)
        }
    }

    @ViewBuilder
    private func wrappedTrail(lineWidth: CGFloat, opacity: Double) -> some View {
        let shape = TopLeadingRoundedRectangle(cornerRadius: .spacing(.sp4))
        let strokeStyle = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)

        if phase.tail >= 0 {
            shape
                .trim(from: phase.tail, to: phase.head)
                .stroke(Color.white.opacity(opacity), style: strokeStyle)
        } else {
            shape
                .trim(from: 0, to: phase.head)
                .stroke(Color.white.opacity(opacity), style: strokeStyle)

            shape
                .trim(from: 1 + phase.tail, to: 1)
                .stroke(Color.white.opacity(opacity * 0.7), style: strokeStyle)
        }
    }
}

private struct TopLeadingRoundedRectangle: Shape {
    let cornerRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let radius = min(cornerRadius, min(rect.width, rect.height) / 2)
        let minX = rect.minX
        let minY = rect.minY
        let maxX = rect.maxX
        let maxY = rect.maxY

        var path = Path()
        path.move(to: CGPoint(x: minX + radius, y: minY))
        path.addLine(to: CGPoint(x: maxX - radius, y: minY))
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: minY),
            tangent2End: CGPoint(x: maxX, y: minY + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: maxX, y: maxY - radius))
        path.addArc(
            tangent1End: CGPoint(x: maxX, y: maxY),
            tangent2End: CGPoint(x: maxX - radius, y: maxY),
            radius: radius
        )
        path.addLine(to: CGPoint(x: minX + radius, y: maxY))
        path.addArc(
            tangent1End: CGPoint(x: minX, y: maxY),
            tangent2End: CGPoint(x: minX, y: maxY - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: minX, y: minY + radius))
        path.addArc(
            tangent1End: CGPoint(x: minX, y: minY),
            tangent2End: CGPoint(x: minX + radius, y: minY),
            radius: radius
        )
        path.closeSubpath()

        return path
    }
}

private struct FlowLayout: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat

    init(spacing: CGFloat, lineSpacing: CGFloat) {
        self.spacing = spacing
        self.lineSpacing = lineSpacing
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .greatestFiniteMagnitude
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            lineHeight = max(lineHeight, size.height)
            x += size.width + spacing
        }

        return CGSize(width: maxWidth, height: y + lineHeight)
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var lineHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }

            subview.place(
                at: CGPoint(x: x, y: y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )

            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

struct ImportView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ImportView()
                .preferredColorScheme(.dark)
        }
    }
}
