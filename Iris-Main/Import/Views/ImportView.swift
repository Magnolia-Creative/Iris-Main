import Photos
import SwiftUI

struct ImportView: View {
    let timelineId: String?
    @StateObject private var viewModel: ImportBrowserViewModel
    @StateObject private var agentViewModel = AgentViewModel()
    @State private var editorLaunchDestination: EditorLaunchDestination?
    @State private var showsAgentView = false
    @FocusState private var isPromptFocused: Bool
    @Namespace private var transitionNamespace

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: .spacing(.sp2)),
        count: 3
    )

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
                browserContent
            }
        }
        .navigationTitle(showsAgentView ? "AutoMake" : "Import")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editorLaunchDestination) { destination in
            EditorContainerView(
                timelineId: destination.timelineId,
                initialImportSeed: destination.seed
            )
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
        .onChange(of: agentViewModel.model.pendingEditorSeed) { _, seed in
            guard let seed else { return }
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
                await agentViewModel.closeIfNeeded()
            }
        }
    }

    private var browserContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: .spacing(.sp6)) {
                heroSection
                albumSection
                assetGridSection
                selectedClipSection
                promptSection
                modeSection
                footerSection
            }
            .padding(.horizontal, .sp4)
            .padding(.top, .sp4)
            .padding(.bottom, .sp8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Build your first cut as you browse")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("Iris starts local embeddings and agent prep as soon as a clip stays selected for a moment, then opens the live session once everything settles.")
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)

            statusPill
        }
    }

    private var statusPill: some View {
        Text(viewModel.model.statusMessage)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.accentFg)
            .padding(.horizontal, .sp3)
            .padding(.vertical, .sp2)
            .background(Color.ds.accentBg.opacity(0.18))
            .overlay(
                Capsule()
                    .stroke(Color.ds.accentFg.opacity(0.35), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var albumSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(title: "Folders", subtitle: "Switch between your video folders just like the system browser.")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: .spacing(.sp2)) {
                    ForEach(viewModel.model.albums) { album in
                        Button {
                            viewModel.selectAlbum(album.id)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(album.title)
                                    .typography(.bodySmall)
                                Text("\(album.count) clips")
                                    .font(.system(size: 11, weight: .medium))
                            }
                            .foregroundStyle(viewModel.model.selectedAlbumID == album.id ? Color.ds.accentFg : Color.ds.textMuted)
                            .padding(.horizontal, .sp3)
                            .padding(.vertical, .sp2)
                            .background(
                                Capsule()
                                    .fill(viewModel.model.selectedAlbumID == album.id ? Color.ds.accentBg.opacity(0.18) : Color.ds.surface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        viewModel.model.selectedAlbumID == album.id ? Color.ds.accentFg.opacity(0.35) : Color.ds.border,
                                        lineWidth: 1
                                    )
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var assetGridSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(
                title: "Library",
                subtitle: "Tap a clip to select it. If it stays selected for 2 seconds, Iris starts working."
            )

            if let loadErrorMessage = viewModel.model.loadErrorMessage {
                errorCard(loadErrorMessage)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(viewModel.model.visibleAssets) { asset in
                    Button {
                        viewModel.toggleSelection(for: asset.id)
                    } label: {
                        ImportAssetCell(asset: asset)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var selectedClipSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(
                title: "Clip Queue",
                subtitle: "Committed clips batch together for server processing over 1-second windows."
            )

            if viewModel.model.clips.isEmpty {
                emptyState("No clips selected yet.")
            } else {
                VStack(spacing: .spacing(.sp2)) {
                    ForEach(viewModel.model.clips) { clip in
                        ImportQueueRow(clip: clip) {
                            Task {
                                await viewModel.cancelClip(localKey: clip.localKey)
                            }
                        }
                    }
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(title: "Editing Prompt", subtitle: "This prompt is sent once the live session starts.")

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

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(title: "Processing Mode", subtitle: "Choose what Iris should do as clips become committed.")

            FlowLayout(spacing: .spacing(.sp2), lineSpacing: .spacing(.sp2)) {
                ForEach(ImportProcessingMode.allCases) { mode in
                    Button {
                        viewModel.updateProcessingMode(mode)
                    } label: {
                        Text(mode.title)
                            .typography(.bodySmall)
                            .foregroundStyle(viewModel.model.processingMode == mode ? Color.ds.accentFg : Color.ds.textMuted)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(
                                Capsule()
                                    .fill(viewModel.model.processingMode == mode ? Color.ds.accentBg.opacity(0.18) : Color.ds.surface)
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        viewModel.model.processingMode == mode ? Color.ds.accentFg.opacity(0.35) : Color.ds.border,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var footerSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            sectionHeader(title: "Readiness", subtitle: "Iris waits for every committed request to finish before opening the agent.")
            VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                readinessRow("Selected clips", value: "\(viewModel.model.selectedClipCount)")
                readinessRow("Committed clips", value: "\(viewModel.model.committedClipCount)")
                readinessRow("Remote session", value: viewModel.model.remoteSession?.sessionName ?? "Waiting")
                readinessRow("Websocket ready", value: (viewModel.model.ingestResponse?.readyForWebSocket ?? false) ? "Yes" : "No")
            }
        }
    }

    private var bottomCTA: some View {
        VStack(spacing: .spacing(.sp2)) {
            if !viewModel.model.processingMode.runsAgentPreprocessing {
                Text("Enable agent preprocessing to start the live editing session.")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            Button {
                isPromptFocused = false
                viewModel.requestAgentStart()
            } label: {
                HStack(spacing: .spacing(.sp2)) {
                    Text(buttonTitle)
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(AnimatedPrimaryButtonStyle(isEnabled: viewModel.model.canRequestAgentStart))
            .disabled(!viewModel.model.canRequestAgentStart)
        }
        .padding(.horizontal, .sp4)
        .padding(.top, .sp2)
        .padding(.bottom, .sp4)
        .background(.ultraThinMaterial.opacity(0.8))
    }

    private var buttonTitle: String {
        if viewModel.model.isAwaitingAgentStart {
            return "Finishing clip prep..."
        }
        return "Start editing"
    }

    private func sectionHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(title)
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
    }

    private func readinessRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
            Spacer()
            Text(value)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
        }
        .padding(.horizontal, .sp4)
        .padding(.vertical, .sp3)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func emptyState(_ message: String) -> some View {
        Text(message)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.textMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.sp4)
            .background(Color.ds.surface)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func errorCard(_ message: String) -> some View {
        Text(message)
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.danger)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.sp4)
            .background(Color.ds.surface)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.danger.opacity(0.5), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
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

private struct ImportAssetCell: View {
    let asset: ImportBrowserAsset

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ImportAssetThumbnailView(assetLocalIdentifier: asset.id)
                .frame(height: 148)
                .overlay(
                    LinearGradient(
                        colors: [Color.black.opacity(0), Color.black.opacity(0.65)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                HStack {
                    Spacer()
                    if asset.isCommitted {
                        Text("Live")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ds.accentFg)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.ds.accentBg.opacity(0.2))
                            .clipShape(Capsule())
                    } else if asset.isSelected {
                        Text("Queued")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.ds.text)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.black.opacity(0.28))
                            .clipShape(Capsule())
                    }
                }

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(asset.displayName)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.white)
                            .lineLimit(2)
                        Text(asset.durationText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.78))
                    }

                    Spacer()

                    Image(systemName: asset.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(asset.isSelected ? Color.ds.accentFg : Color.white.opacity(0.8))
                }
            }
            .padding(.sp3)
        }
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(asset.isSelected ? Color.ds.accentFg : Color.ds.border, lineWidth: asset.isSelected ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
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
                RoundedRectangle(cornerRadius: .spacing(.sp3))
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

private struct ImportQueueRow: View {
    let clip: ImportClipProcessingItem
    let onCancel: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: .spacing(.sp3)) {
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .fill(Color.ds.accentBg.opacity(0.18))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: clip.isCommitted ? "film.stack" : "hourglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Color.ds.accentFg)
                )

            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                Text(clip.displayName)
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(2)

                Text(clip.commitmentStatus)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)

                Text("Embeddings: \(clip.embeddingState.description)")
                    .typography(.bodySmall)
                    .foregroundStyle(statusColor(for: clip.embeddingState))

                Text("Agent prep: \(clip.uploadState.description)")
                    .typography(.bodySmall)
                    .foregroundStyle(statusColor(for: clip.uploadState))
            }

            Spacer()

            Button("Remove", action: onCancel)
                .buttonStyle(.plain)
                .typographyStyle(.bodySmall)
                .foregroundStyle(Color.ds.danger)
        }
        .padding(.sp4)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func statusColor(for state: ImportClipWorkState) -> Color {
        switch state {
        case .failed:
            return Color.ds.danger
        case .succeeded:
            return Color.ds.accentFg
        case .queued, .running:
            return Color.ds.text
        case .idle, .cancelled:
            return Color.ds.textMuted
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
                AnimatedPrimaryButtonBackground(opacity: isEnabled ? 1 : 0.35)
            }
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
    }
}

private struct AnimatedPrimaryButtonBackground: View {
    let opacity: Double
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
                .fill(Color.ds.accentBg.opacity(opacity))
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
