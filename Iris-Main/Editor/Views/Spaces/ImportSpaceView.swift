import CoreTransferable
import AVKit
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

// MARK: - Canvas (preview + timeline only)

struct ImportSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID
    private let timelineLayout = TimelineLayout.compressed

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            PreviewSection(
                controller: playbackController ?? PlaybackController(
                    statePublisher: controller.$state.eraseToAnyPublisher(),
                    actions: controller
                ),
                renderBridge: renderBridge
            )
            .frame(height: 140)
            .matchedGeometryEffect(id: "preview", in: namespace)
            .padding(.horizontal, .sp3)

            TimelineSectionView(
                tracks: state.orderedTracks,
                clipsByTrackId: state.clipsByTrackId,
                mediaById: state.mediaById,
                layout: timelineLayout,
                pixelsPerSecond: state.pixelsPerSecond,
                timelineDurationUs: state.calculatedTimelineDurationUs,
                scrollableDurationUs: state.scrollableDurationUs,
                currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
                scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
                selectedClipId: controller.binding(\.selectedClipId),
                onAddSelection: { _, _ in },
                onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
                onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:),
                onDropImportedSegmentAtTime: { item, timeUs in
                    controller.insertClipSegment(
                        mediaId: item.mediaId,
                        sourceRange: item.sourceRange,
                        at: timeUs
                    )
                },
                showAddButton: false
            )
            .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
            .matchedGeometryEffect(id: "timeline", in: namespace)
        }
    }
}

// MARK: - Panel (extends from nav bar)

@MainActor
struct ImportPanelContent: View {
    @ObservedObject var controller: TimelineController
    let onOpenVideoImport: () -> Void

    @State private var filterTag: MediaFilterTag = .all
    @State private var isSemanticSearchActive = false
    @State private var selectedSemanticVideoId: String?
    @State private var previewItem: ImportClipPreviewItem?
    @ObservedObject private var semanticVM = SemanticSearchViewModel.shared
    @FocusState private var isSearchFieldFocused: Bool
    @Namespace private var previewNamespace

    enum MediaFilterTag: String, CaseIterable {
        case all = "All"
        case photos = "Photos"
        case videos = "Videos"
    }

    var body: some View {
        let state = controller.state

        ZStack {
            VStack(spacing: 0) {
                topBar

                Divider().overlay(Color.ds.border.opacity(0.4))

                Group {
                    if isSemanticSearchActive {
                        semanticSearchContent(state: state)
                    } else {
                        mediaGrid(state: state)
                    }
                }
            }
            .zIndex(0)

            if let previewItem {
                Color.black.opacity(0.22)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture {
                        dismissPreview()
                    }
                    .transition(.opacity)
                    .zIndex(1)

                ImportClipPreviewOverlay(
                    item: previewItem,
                    namespace: previewNamespace,
                    onClose: dismissPreview
                )
                .padding(.horizontal, .sp4)
                .zIndex(2)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.88), value: previewItem?.heroID)
        .task(id: searchableVideoSignature(for: state)) {
            EditorDebugTrace.log(
                "ImportPanelContent",
                "queue semantic sync videoCount=\(searchableVideos(from: state).count)"
            )
            semanticVM.queueImportedMediaSync(searchableVideos(from: state), autoBuildIndex: false)
        }
        .onChange(of: isSemanticSearchActive) { _, isActive in
            EditorDebugTrace.log(
                "ImportPanelContent",
                "semantic search toggled active=\(isActive) selectedVideo=\(selectedSemanticVideoId ?? "nil")"
            )
            if isActive {
                Task { @MainActor in
                    await Task.yield()
                    isSearchFieldFocused = true
                    EditorDebugTrace.log("ImportPanelContent", "search field focus requested")
                }
            } else {
                isSearchFieldFocused = false
                selectedSemanticVideoId = nil
                semanticVM.clearSearch()
            }
        }
        .onChange(of: semanticVM.model.results) { _, results in
            EditorDebugTrace.log(
                "ImportPanelContent",
                "semantic results updated count=\(results.count) isSearching=\(semanticVM.model.isSearching)"
            )
            guard let selectedSemanticVideoId else { return }
            if !results.contains(where: { $0.videoID == selectedSemanticVideoId }) {
                self.selectedSemanticVideoId = nil
            }
        }
        .onAppear {
            EditorDebugTrace.log(
                "ImportPanelContent",
                "appeared mediaCount=\(state.mediaById.count) videoCount=\(searchableVideos(from: state).count)"
            )
            EditorDebugTrace.end(
                "space-content-importMedia",
                scope: "ImportPanelContent",
                message: "import panel appeared"
            )
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if isSemanticSearchActive {
            HStack(spacing: .spacing(.sp2)) {
                if selectedSemanticVideoId != nil {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                            selectedSemanticVideoId = nil
                        }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.ds.textMuted)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                }

                HStack(spacing: .spacing(.sp2)) {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.ds.accentFg)

                    TextField(
                        "Search imported clips",
                        text: Binding(
                            get: { semanticVM.model.queryText },
                            set: {
                                semanticVM.updateQuery($0)
                                selectedSemanticVideoId = nil
                                semanticVM.queueLiveSearch()
                            }
                        )
                    )
                    .textFieldStyle(.plain)
                    .typographyStyle(.body)
                    .foregroundStyle(Color.ds.text)
                    .focused($isSearchFieldFocused)
                    .submitLabel(.search)

                    if !semanticVM.model.queryText.isEmpty {
                        Button {
                            semanticVM.clearSearch()
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 16))
                                .foregroundColor(Color.ds.textMuted)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, .sp3)
                .padding(.vertical, .sp2)
                .background(Color.ds.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp2))
                        .stroke(Color.ds.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        isSemanticSearchActive = false
                    }
                } label: {
                    Text("Cancel")
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, .sp2)
            .padding(.bottom, .sp2)
        } else {
            HStack {
                Button(action: onOpenVideoImport) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.ds.accentFg)
                }
                .buttonStyle(.plain)

                Spacer()

                HStack(spacing: .spacing(.sp2)) {
                    ForEach(MediaFilterTag.allCases, id: \.self) { tag in
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { filterTag = tag }
                        } label: {
                            Text(tag.rawValue)
                                .typography(.bodySmall)
                                .foregroundColor(filterTag == tag ? .white : Color.ds.textMuted)
                                .padding(.horizontal, .sp3)
                                .padding(.vertical, .sp1)
                                .background(filterTag == tag ? Color.ds.accentBg : Color.clear)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                Button {
                    EditorDebugTrace.log("ImportPanelContent", "semantic search button tapped")
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                        isSemanticSearchActive = true
                    }
                } label: {
                    Image(systemName: "sparkle.magnifyingglass")
                        .font(.system(size: 20))
                        .foregroundColor(Color.ds.accentFg)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, .sp2)
            .padding(.bottom, .sp2)
        }
    }

    @ViewBuilder
    private func mediaGrid(state: TimelineState) -> some View {
        let allMedia = Media.deduplicatedForImportPresentation(Array(state.mediaById.values))
        let filtered: [Media] = {
            switch filterTag {
            case .all: return allMedia
            case .photos: return allMedia.filter { $0.kind == .photo }
            case .videos: return allMedia.filter { $0.kind == .video }
            }
        }()

        if filtered.isEmpty {
            VStack(spacing: .spacing(.sp3)) {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 32))
                    .foregroundColor(Color.ds.textMuted)
                Text("No media imported yet")
                    .typography(.body)
                    .foregroundColor(Color.ds.text)
                Text("Tap + to add videos")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                let filteredCount = filtered.count
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                    ForEach(filtered) { media in
                        MediaThumbnailCell(
                            media: media,
                            dragItem: ImportedTimelineSegment(media: media),
                            previewHeroID: previewHeroID(for: media),
                            previewNamespace: previewNamespace,
                            isPreviewSourceHidden: previewItem?.heroID == previewHeroID(for: media)
                        )
                        .onTapGesture {
                            presentPreview(media: media)
                        }
                    }
                }
                .padding(.sp3)
                .onAppear {
                    EditorDebugTrace.log(
                        "ImportPanelContent",
                        "media grid appeared filter=\(filterTag.rawValue) count=\(filteredCount)"
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func semanticSearchContent(state: TimelineState) -> some View {
        if semanticVM.model.trimmedQuery.isEmpty {
            semanticLibraryGrid(state: state)
        } else if semanticVM.model.isBuildingIndex || semanticVM.model.isSearching, semanticVM.model.results.isEmpty {
            semanticLoadingGrid()
        } else if let searchError = semanticVM.model.searchErrorMessage {
            semanticCenteredState(
                icon: "exclamationmark.triangle",
                title: "Search failed",
                subtitle: searchError
            )
        } else if semanticGroups.isEmpty {
            semanticCenteredState(
                icon: "tray",
                title: "No matches found",
                subtitle: "Try a broader description or import more video."
            )
        } else if let selectedGroup {
            semanticRangeGrid(for: selectedGroup, state: state)
        } else {
            semanticResultGrid(state: state)
        }
    }

    private func semanticLoadingGrid() -> some View {
        let placeholderCount = 12
        let placeholderColumnCount = 3
        let rowCount = Int(ceil(Double(placeholderCount) / Double(placeholderColumnCount)))

        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                ForEach(0..<12, id: \.self) { index in
                    SemanticLoadingThumbnailCell(
                        position: index / placeholderColumnCount,
                        totalCount: rowCount
                    )
                }
            }
            .padding(.sp3)
        }
    }

    private func semanticLibraryGrid(state: TimelineState) -> some View {
        let videos = searchableVideos(from: state)
        if videos.isEmpty {
            return AnyView(
                semanticCenteredState(
                    icon: "video.slash",
                    title: "No searchable clips yet",
                    subtitle: "Import at least one video to search it semantically."
                )
            )
        }

        return AnyView(
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                    ForEach(videos) { media in
                        MediaThumbnailCell(
                            media: media,
                            dragItem: ImportedTimelineSegment(media: media),
                            previewHeroID: previewHeroID(for: media),
                            previewNamespace: previewNamespace,
                            isPreviewSourceHidden: previewItem?.heroID == previewHeroID(for: media)
                        )
                        .onTapGesture {
                            presentPreview(media: media)
                        }
                    }
                }
                .padding(.sp3)
            }
        )
    }

    private func semanticResultGrid(state: TimelineState) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                ForEach(semanticGroups) { group in
                    if let media = state.mediaById[group.id] {
                        SemanticVideoResultCell(media: media, matchCount: group.segments.count)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                    selectedSemanticVideoId = group.id
                                }
                            }
                    }
                }
            }
            .padding(.sp3)
        }
    }

    private func semanticRangeGrid(for group: SemanticResultGroup, state: TimelineState) -> some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                ForEach(group.segments) { segment in
                    if let media = state.mediaById[group.id] {
                        let heroID = previewHeroID(for: media, range: segment)
                        SemanticRangeThumbnailCell(
                            result: segment,
                            assetRefId: media.assetRefId,
                            previewHeroID: heroID,
                            previewNamespace: previewNamespace,
                            isPreviewSourceHidden: previewItem?.heroID == heroID
                        )
                        .onTapGesture {
                            presentPreview(media: media, range: segment)
                        }
                    }
                }
            }
            .padding(.sp3)
        }
    }

    private func semanticCenteredState(icon: String, title: String, subtitle: String) -> some View {
        VStack(spacing: .spacing(.sp2)) {
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)

            Text(title)
                .typography(.body)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, .spacing(.sp8))
        .padding(.horizontal, .sp3)
    }

    private var semanticGroups: [SemanticResultGroup] {
        var grouped: [String: [SemanticMatchRange]] = [:]
        var orderedIds: [String] = []

        for result in semanticVM.model.results {
            if grouped[result.videoID] == nil {
                orderedIds.append(result.videoID)
            }
            grouped[result.videoID, default: []].append(result)
        }

        return orderedIds.compactMap { id in
            guard let results = grouped[id] else { return nil }
            return SemanticResultGroup(
                id: id,
                segments: results.sorted { $0.confidence > $1.confidence }
            )
        }
    }

    private var selectedGroup: SemanticResultGroup? {
        guard let selectedSemanticVideoId else { return nil }
        return semanticGroups.first(where: { $0.id == selectedSemanticVideoId })
    }

    private func searchableVideos(from state: TimelineState) -> [Media] {
        Media.deduplicatedForImportPresentation(Array(state.mediaById.values))
            .filter { $0.kind == .video }
    }

    private func searchableVideoSignature(for state: TimelineState) -> String {
        searchableVideos(from: state)
            .map(\.mediaId)
            .sorted()
            .joined(separator: "|")
    }

    private func presentPreview(media: Media, range: SemanticMatchRange? = nil) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.88)) {
            previewItem = ImportClipPreviewItem(
                media: media,
                range: range,
                heroID: previewHeroID(for: media, range: range)
            )
        }
    }

    private func dismissPreview() {
        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
            previewItem = nil
        }
    }

    private func previewHeroID(for media: Media, range: SemanticMatchRange? = nil) -> String {
        if let range {
            let start = Int((range.startTimeSeconds * 1_000).rounded())
            let end = Int((range.endTimeSeconds * 1_000).rounded())
            return "preview-\(media.mediaId)-\(start)-\(end)"
        }
        return "preview-\(media.mediaId)"
    }
}

private struct MediaThumbnailCell: View {
    let media: Media
    let dragItem: ImportedTimelineSegment?
    let previewHeroID: String?
    let previewNamespace: Namespace.ID?
    let isPreviewSourceHidden: Bool
    @State private var thumbnail: UIImage?

    init(
        media: Media,
        dragItem: ImportedTimelineSegment? = nil,
        previewHeroID: String? = nil,
        previewNamespace: Namespace.ID? = nil,
        isPreviewSourceHidden: Bool = false
    ) {
        self.media = media
        self.dragItem = dragItem
        self.previewHeroID = previewHeroID
        self.previewNamespace = previewNamespace
        self.isPreviewSourceHidden = isPreviewSourceHidden
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.ds.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: media.kind == .video ? "video.fill" : "photo.fill")
                        .foregroundColor(Color.ds.textMuted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .matchedPreviewIfPresent(previewHeroID, in: previewNamespace)
            .opacity(isPreviewSourceHidden ? 0.001 : 1)
            .draggableIfPresent(dragItem) {
                HStack(spacing: .spacing(.sp2)) {
                    Image(systemName: media.kind == .video ? "video.fill" : "photo.fill")
                        .foregroundStyle(Color.ds.accentFg)
                    Text(media.kind == .video ? "Video clip" : "Photo clip")
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.text)
                }
                .padding(.sp3)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
            .task {
                let loadStart = EditorDebugTrace.mark()
                thumbnail = try? await ThumbnailService.shared.loadThumbnail(
                    for: media.assetRefId,
                    size: CGSize(width: 160, height: 160)
                )
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - loadStart) * 1000
                if elapsedMs > 150 {
                    EditorDebugTrace.log(
                        "MediaThumbnailCell",
                        "slow thumbnail mediaId=\(media.mediaId) kind=\(media.kind.rawValue) elapsed=\(String(format: "%.1fms", elapsedMs))"
                    )
                }
            }
    }
}

private struct ImportClipPreviewItem: Identifiable {
    let id = UUID()
    let media: Media
    let heroID: String
    let title: String
    let subtitle: String?
    let clipRangeSeconds: ClosedRange<Double>?

    init(media: Media, range: SemanticMatchRange? = nil, heroID: String) {
        self.media = media
        self.heroID = heroID
        self.title = "Clip Preview"
        if let range {
            self.subtitle = "\(Self.formatTime(range.startTimeSeconds)) - \(Self.formatTime(range.endTimeSeconds))"
            self.clipRangeSeconds = range.startTimeSeconds...range.endTimeSeconds
        } else {
            if let duration = media.spec.duration, duration > 0 {
                self.subtitle = "Duration \(Self.formatTime(duration))"
            } else {
                self.subtitle = nil
            }
            self.clipRangeSeconds = nil
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

private struct SemanticResultGroup: Identifiable {
    let id: String
    let segments: [SemanticMatchRange]
}

private struct SemanticVideoResultCell: View {
    let media: Media
    let matchCount: Int

    var body: some View {
        MediaThumbnailCell(media: media)
            .overlay(alignment: .topTrailing) {
                if matchCount > 1 {
                    Text("\(matchCount)")
                        .typography(.bodySmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, .sp2)
                        .padding(.vertical, 3)
                        .background(Color.ds.accentBg)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
    }
}

private struct SemanticRangeThumbnailCell: View {
    let result: SemanticMatchRange
    let assetRefId: String
    let previewHeroID: String?
    let previewNamespace: Namespace.ID?
    let isPreviewSourceHidden: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        let transferItem = ImportedTimelineSegment(
            mediaId: result.videoID,
            startTimeUs: timeToMicroseconds(result.startTimeSeconds),
            endTimeUs: timeToMicroseconds(result.endTimeSeconds)
        )

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.ds.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: "video.fill")
                        .foregroundColor(Color.ds.textMuted)
                }
            }
            .overlay(alignment: .bottomLeading) {
                Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                    .typography(.bodySmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, .sp2)
                    .padding(.vertical, 3)
                    .background(Color.black.opacity(0.72))
                    .clipShape(Capsule())
                    .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .matchedPreviewIfPresent(previewHeroID, in: previewNamespace)
            .opacity(isPreviewSourceHidden ? 0.001 : 1)
            .draggable(transferItem) {
                Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .padding(.sp3)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
            .task {
                let loadStart = EditorDebugTrace.mark()
                let midpoint = max(result.startTimeSeconds, (result.startTimeSeconds + result.endTimeSeconds) / 2)
                thumbnail = try? await ThumbnailService.shared.loadVideoThumbnails(
                    for: assetRefId,
                    size: CGSize(width: 160, height: 160),
                    times: [midpoint]
                ).first
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - loadStart) * 1000
                if elapsedMs > 150 {
                    EditorDebugTrace.log(
                        "SemanticRangeThumbnailCell",
                        "slow range thumbnail mediaId=\(result.videoID) elapsed=\(String(format: "%.1fms", elapsedMs))"
                    )
                }
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func timeToMicroseconds(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }
}

private struct SemanticLoadingThumbnailCell: View {
    let position: Int
    let totalCount: Int

    var body: some View {
        TimelineView(.animation) { context in
            let opacity = pulseOpacity(at: context.date)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.ds.surface)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(opacity))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.ds.border.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func pulseOpacity(at date: Date) -> Double {
        let normalizedPosition = totalCount > 1 ? Double(position) / Double(totalCount - 1) : 0
        let phaseOffset = -Double.pi / 2 + (normalizedPosition * Double.pi)
        let wave = (sin((date.timeIntervalSinceReferenceDate * 2 * Double.pi / 1.1) + phaseOffset) + 1) / 2
        return 0.03 + (wave * 0.07)
    }
}

private struct ImportClipPreviewOverlay: View {
    let item: ImportClipPreviewItem
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: .spacing(.sp3)) {
            HStack {
                VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                    Text(item.title)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ds.textMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.ds.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Group {
                if let loadError {
                    previewUnavailableState(title: "Preview unavailable", subtitle: loadError)
                } else if item.media.kind == .photo {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                            .matchedGeometryEffect(id: item.heroID, in: namespace)
                    } else {
                        ProgressView()
                            .tint(Color.ds.accentFg)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else if let videoURL {
                    ClipRangePlayerView(
                        url: videoURL,
                        clipRangeSeconds: item.clipRangeSeconds,
                        durationHint: item.media.spec.duration
                    )
                    .matchedGeometryEffect(id: item.heroID, in: namespace)
                } else {
                    ProgressView()
                        .tint(Color.ds.accentFg)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .padding(.sp3)
        .frame(maxWidth: 360)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .task {
            await loadPreview()
        }
    }

    @ViewBuilder
    private func previewUnavailableState(title: String, subtitle: String) -> some View {
        VStack(spacing: .spacing(.sp2)) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)

            Text(title)
                .typography(.body)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, .sp3)
    }

    private func loadPreview() async {
        loadError = nil
        image = nil
        videoURL = nil

        do {
            switch item.media.kind {
            case .photo:
                image = try await ThumbnailService.shared.loadThumbnail(
                    for: item.media.assetRefId,
                    size: CGSize(width: 1_200, height: 1_200)
                )
                if image == nil {
                    loadError = "Couldn't load that photo."
                }
            case .video:
                videoURL = try await ThumbnailService.shared.loadVideoURL(for: item.media.assetRefId)
                if videoURL == nil {
                    loadError = "Couldn't load that video."
                }
            case .audio:
                loadError = "Audio preview isn't available here yet."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct ClipRangePlayerView: View {
    let url: URL
    let clipRangeSeconds: ClosedRange<Double>?
    let durationHint: Double?

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            VideoPlayer(player: player)
                .frame(height: 220)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))

            HStack(spacing: .spacing(.sp2)) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ds.text)
                        .frame(width: 32, height: 32)
                        .background(Color.ds.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { progress },
                        set: { progress = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: handleScrubbingChanged(_:)
                )
                .tint(Color.ds.accentFg)

                Text(formattedElapsedTime)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .monospacedDigit()
            }
        }
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func configurePlayer() {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .none

        let startTime = CMTime(seconds: rangeStartSeconds, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { currentTime in
            let seconds = currentTime.seconds
            guard seconds.isFinite else { return }

            if seconds >= rangeEndSeconds {
                let startTime = CMTime(seconds: rangeStartSeconds, preferredTimescale: 600)
                player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                if isPlaying {
                    player.play()
                } else {
                    player.pause()
                }
            }

            guard !isScrubbing else { return }
            let relative = max(0, min(previewDurationSeconds, seconds - rangeStartSeconds))
            progress = previewDurationSeconds > 0 ? relative / previewDurationSeconds : 0
        }

        player.play()
        isPlaying = true
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func handleScrubbingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing

        if isEditing {
            player.pause()
            return
        }

        let seekSeconds = rangeStartSeconds + (progress * previewDurationSeconds)
        let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying {
            player.play()
        }
    }

    private var rangeStartSeconds: Double {
        clipRangeSeconds?.lowerBound ?? 0
    }

    private var rangeEndSeconds: Double {
        if let clipRangeSeconds {
            return clipRangeSeconds.upperBound
        }
        return max(durationHint ?? 0, 0.1)
    }

    private var previewDurationSeconds: Double {
        max(rangeEndSeconds - rangeStartSeconds, 0.1)
    }

    private var formattedElapsedTime: String {
        let elapsed = progress * previewDurationSeconds
        return "\(formatTime(elapsed)) / \(formatTime(previewDurationSeconds))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func tearDownPlayer() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }
}

struct ImportedTimelineSegment: Codable, Transferable {
    static let fallbackDurationUs: Int64 = 2_000_000

    let mediaId: String
    let startTimeUs: Int64
    let endTimeUs: Int64

    init(mediaId: String, startTimeUs: Int64, endTimeUs: Int64) {
        self.mediaId = mediaId
        self.startTimeUs = startTimeUs
        self.endTimeUs = endTimeUs
    }

    init(media: Media, fallbackDurationUs: Int64 = ImportedTimelineSegment.fallbackDurationUs) {
        let resolvedDurationUs: Int64
        if let seconds = media.spec.duration, seconds > 0 {
            resolvedDurationUs = max(1, Int64((seconds * 1_000_000).rounded()))
        } else {
            resolvedDurationUs = fallbackDurationUs
        }

        self.mediaId = media.mediaId
        self.startTimeUs = 0
        self.endTimeUs = resolvedDurationUs
    }

    var sourceRange: TimeRange {
        TimeRange(start: startTimeUs, end: endTimeUs)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .importedTimelineSegment)
    }
}

private extension UTType {
    static let importedTimelineSegment = UTType(exportedAs: "com.iris.editor.imported-timeline-segment")
}

private extension View {
    @ViewBuilder
    func draggableIfPresent<Preview: View>(
        _ item: ImportedTimelineSegment?,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        if let item {
            draggable(item, preview: preview)
        } else {
            self
        }
    }

    @ViewBuilder
    func matchedPreviewIfPresent(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
