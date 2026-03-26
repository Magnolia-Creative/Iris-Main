import AVFoundation
import CoreTransferable
import PhotosUI
import SwiftUI

struct ImportView: View {
    @StateObject private var viewModel = ImportViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @FocusState private var isPromptFocused: Bool
    private let ctaButtonHeight: CGFloat = 64
    private let ctaFadeExtension: CGFloat = .spacing(.sp4)

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: .spacing(.sp2)),
        count: 3
    )

    private var importedVideoCount: Int {
        viewModel.model.importedVideoCount
    }

    private var ctaContainerHeight: CGFloat {
        ctaButtonHeight + (ctaFadeExtension * 2)
    }

    private var ctaFadeStop: Double {
        Double(ctaFadeExtension / ctaContainerHeight)
    }

    var body: some View {
        ZStack {
            Color.ds.bg
                .ignoresSafeArea()

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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomCTA
        }
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItems) { _, newValue in
            Task {
                await importSelection(from: newValue)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .frame(height: 24)

            Text("Build your edit")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("Import multiple videos, then give Iris a prompt before you start editing.")
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

            if let importErrorMessage = viewModel.model.importErrorMessage {
                Text(importErrorMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            } else if viewModel.model.isImportingVideos {
                ProgressView("Importing videos...")
                    .tint(Color.ds.accentFg)
                    .typographyStyle(.bodySmall)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(viewModel.model.videos) { video in
                    ImportedVideoTile(videoURL: video.originalURL)
                }

                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    AddVideoTile()
                }
            }
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
            Text("Editing prompt")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

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
                    .frame(minHeight: 140)
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
            .padding(.sp3)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ds.surface)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))

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
                    Text("Start editing")
                    Image(systemName: "sparkles")
                        .font(.system(size: 16, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .contentShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
            .buttonStyle(AnimatedPrimaryButtonStyle(isEnabled: viewModel.model.canStartEditing))
            .padding(.horizontal, .sp4)
            .zIndex(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ctaContainerHeight)
    }

    private func importSelection(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            await MainActor.run {
                viewModel.importSelection(from: [])
            }
            return
        }

        await MainActor.run {
            viewModel.beginVideoImport()
        }

        do {
            var importedVideos: [ImportedVideo] = []

            for item in items.prefix(20) {
                let transferable = try await item.loadTransferable(type: VideoPickerTransferable.self)
                guard let transferable else { continue }

                importedVideos.append(
                    ImportedVideo(
                        localURL: transferable.localURL,
                        displayName: transferable.originalFilename
                    )
                )
            }

            await MainActor.run {
                viewModel.importSelection(from: importedVideos)
            }
        } catch {
            await MainActor.run {
                viewModel.completeVideoImport(with: error)
            }
        }
    }

    private func startEditing() {
        print("Start editing button pressed")

        guard viewModel.model.canStartEditing else { return }
        isPromptFocused = false
    }
}

private struct QueueBadge: View {
    let count: Int

    var body: some View {
        Text("\(count) queued")
            .typography(.bodySmall)
            .foregroundStyle(Color.ds.accentFg)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.ds.surface)
            .clipShape(Capsule())
    }
}

private struct ImportedVideoTile: View {
    let videoURL: URL
    @State private var thumbnail: CGImage?

    var body: some View {
        ZStack {
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1, orientation: .up)
                        .resizable()
                        .scaledToFill()
                } else {
                    RoundedRectangle(cornerRadius: .spacing(.sp3))
                        .fill(Color.ds.surface.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                .stroke(Color.ds.border, lineWidth: 1.5)
                        )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1.5)
            )
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .frame(height: 136)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .task(id: videoURL) {
            thumbnail = await Self.generateThumbnail(for: videoURL)
        }
    }

    private static func generateThumbnail(for videoURL: URL) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 600, height: 600)

            return try? generator.copyCGImage(at: CMTime(seconds: 0.1, preferredTimescale: 600), actualTime: nil)
        }.value
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

private struct VideoPickerTransferable: Transferable {
    let localURL: URL
    let originalFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .mpeg4Movie, importing: importReceivedVideo)
        FileRepresentation(importedContentType: .movie, importing: importReceivedVideo)
    }

    private static func importReceivedVideo(_ received: ReceivedTransferredFile) throws -> Self {
        let fileManager = FileManager.default
        let sourceURL = received.file
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return Self(
            localURL: destinationURL,
            originalFilename: sourceURL.lastPathComponent
        )
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
