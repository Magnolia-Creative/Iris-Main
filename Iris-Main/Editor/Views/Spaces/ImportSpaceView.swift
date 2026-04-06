import CoreTransferable
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

// MARK: - Canvas (preview + timeline only)

struct ImportSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID
    @State private var isTimelineDropTargeted = false
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
                showAddButton: false
            )
            .frame(height: timelineLayout.sectionHeight(for: state.orderedTracks))
            .matchedGeometryEffect(id: "timeline", in: namespace)
            .overlay {
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(
                        isTimelineDropTargeted ? Color.ds.accentFg : Color.clear,
                        style: StrokeStyle(lineWidth: 2, dash: [8, 6])
                    )
                    .padding(.horizontal, .sp3)
                    .animation(.easeOut(duration: 0.18), value: isTimelineDropTargeted)
            }
            .dropDestination(for: ImportedTimelineSegment.self) { items, _ in
                guard let item = items.first else { return false }
                controller.insertClipSegment(
                    mediaId: item.mediaId,
                    sourceRange: item.sourceRange,
                    at: controller.state.currentTimeAtCenter
                )
                return true
            } isTargeted: { isTargeted in
                isTimelineDropTargeted = isTargeted
            }
        }
    }
}

// MARK: - Panel (extends from nav bar)

@MainActor
struct ImportPanelContent: View {
    @ObservedObject var controller: TimelineController

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var filterTag: MediaFilterTag = .all
    @State private var isSemanticSearchActive = false
    @State private var selectedSemanticVideoId: String?
    @ObservedObject private var semanticVM = SemanticSearchViewModel.shared
    @FocusState private var isSearchFieldFocused: Bool

    enum MediaFilterTag: String, CaseIterable {
        case all = "All"
        case photos = "Photos"
        case videos = "Videos"
    }

    var body: some View {
        let state = controller.state

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
        .onChange(of: selectedPhotos) { _, items in
            importSelectedPhotos(items)
        }
        .task(id: searchableVideoSignature(for: state)) {
            semanticVM.queueImportedMediaSync(searchableVideos(from: state), autoBuildIndex: false)
        }
        .onChange(of: isSemanticSearchActive) { _, isActive in
            if isActive {
                Task { @MainActor in
                    await Task.yield()
                    isSearchFieldFocused = true
                }
            } else {
                isSearchFieldFocused = false
                selectedSemanticVideoId = nil
                semanticVM.clearSearch()
            }
        }
        .onChange(of: semanticVM.model.results) { _, results in
            guard let selectedSemanticVideoId else { return }
            if !results.contains(where: { $0.videoID == selectedSemanticVideoId }) {
                self.selectedSemanticVideoId = nil
            }
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
                PhotosPicker(selection: $selectedPhotos, maxSelectionCount: 20,
                             matching: .any(of: [.videos, .images])) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Color.ds.accentFg)
                }

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
        let allMedia = Array(state.mediaById.values)
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
                    .foregroundColor(Color.ds.textMuted)
                Text("Tap + to add photos and videos")
                    .typography(.bodySmall)
                    .foregroundColor(Color.ds.textMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                    ForEach(filtered) { media in
                        MediaThumbnailCell(media: media)
                            .onTapGesture {
                                controller.handleAddSelection(kind: .video, source: .photos)
                            }
                    }
                }
                .padding(.sp3)
            }
        }
    }

    @ViewBuilder
    private func semanticSearchContent(state: TimelineState) -> some View {
        if semanticVM.model.trimmedQuery.isEmpty {
            semanticLibraryGrid(state: state)
        } else if semanticVM.model.isBuildingIndex || semanticVM.model.isSearching, semanticVM.model.results.isEmpty {
            semanticCenteredState(
                icon: "sparkle.magnifyingglass",
                title: semanticVM.model.isBuildingIndex ? "Indexing imported clips..." : "Searching clips...",
                subtitle: "Results will appear here automatically."
            )
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
                        MediaThumbnailCell(media: media)
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
                        SemanticRangeThumbnailCell(result: segment, assetRefId: media.assetRefId)
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
        .frame(maxWidth: .infinity)
        .padding(.vertical, .spacing(.sp8))
        .padding(.horizontal, .sp3)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
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
        Array(state.mediaById.values)
            .filter { $0.kind == .video }
            .sorted { $0.createdAt < $1.createdAt }
    }

    private func searchableVideoSignature(for state: TimelineState) -> String {
        searchableVideos(from: state)
            .map(\.mediaId)
            .sorted()
            .joined(separator: "|")
    }

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty else { return }
        controller.importPickerItems(items, kind: .video)
        selectedPhotos = []
    }
}

private struct MediaThumbnailCell: View {
    let media: Media
    @State private var thumbnail: UIImage?

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
            .task {
                thumbnail = try? await ThumbnailService.shared.loadThumbnail(
                    for: media.assetRefId,
                    size: CGSize(width: 160, height: 160)
                )
            }
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
            .draggable(transferItem) {
                Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .padding(.sp3)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
            .task {
                let midpoint = max(result.startTimeSeconds, (result.startTimeSeconds + result.endTimeSeconds) / 2)
                thumbnail = try? await ThumbnailService.shared.loadVideoThumbnails(
                    for: assetRefId,
                    size: CGSize(width: 160, height: 160),
                    times: [midpoint]
                ).first
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

struct ImportedTimelineSegment: Codable, Transferable {
    let mediaId: String
    let startTimeUs: Int64
    let endTimeUs: Int64

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
