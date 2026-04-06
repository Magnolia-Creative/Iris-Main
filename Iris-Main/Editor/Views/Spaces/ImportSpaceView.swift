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

struct ImportPanelContent: View {
    @ObservedObject var controller: TimelineController

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var filterTag: MediaFilterTag = .all
    @State private var isSemanticSearchActive = false
    @State private var expandedSemanticGroups: Set<String> = []
    @StateObject private var semanticVM = SemanticSearchViewModel()
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
                    semanticSearchContent
                } else {
                    mediaGrid(state: state)
                }
            }
        }
        .onChange(of: selectedPhotos) { _, items in
            importSelectedPhotos(items)
        }
        .task(id: searchableVideoSignature(for: state)) {
            await semanticVM.syncImportedMedia(searchableVideos(from: state), autoBuildIndex: isSemanticSearchActive)
        }
        .onChange(of: isSemanticSearchActive) { _, isActive in
            if isActive {
                expandedSemanticGroups.removeAll()
                isSearchFieldFocused = true
                Task {
                    await semanticVM.syncImportedMedia(searchableVideos(from: controller.state), autoBuildIndex: true)
                }
            } else {
                isSearchFieldFocused = false
                semanticVM.clearSearch()
            }
        }
    }

    @ViewBuilder
    private var topBar: some View {
        if isSemanticSearchActive {
            HStack(spacing: .spacing(.sp2)) {
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

    private var semanticSearchContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                semanticSearchStatusCard

                if semanticVM.model.results.isEmpty {
                    semanticEmptyState
                } else {
                    VStack(spacing: .spacing(.sp2)) {
                        ForEach(semanticGroups) { group in
                            SemanticResultGroupCard(
                                group: group,
                                isExpanded: Binding(
                                    get: { expandedSemanticGroups.contains(group.id) },
                                    set: { isExpanded in
                                        if isExpanded {
                                            expandedSemanticGroups.insert(group.id)
                                        } else {
                                            expandedSemanticGroups.remove(group.id)
                                        }
                                    }
                                )
                            )
                        }
                    }
                }
            }
            .padding(.sp3)
        }
    }

    private var semanticSearchStatusCard: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Semantic search")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if semanticVM.model.isBuildingIndex {
                ProgressView("Indexing imported clips...")
                    .tint(Color.ds.accentFg)
            } else if semanticVM.model.isSearching {
                ProgressView("Searching matching segments...")
                    .tint(Color.ds.accentFg)
            } else if let searchError = semanticVM.model.searchErrorMessage {
                Text(searchError)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            } else {
                Text(semanticVM.model.statusMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            Text("Drag any result into the timeline above to create a clip from that exact segment.")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.sp3)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }

    @ViewBuilder
    private var semanticEmptyState: some View {
        if semanticVM.model.videos.isEmpty {
            emptyState(
                icon: "video.slash",
                title: "No searchable clips yet",
                subtitle: "Import at least one video to search it semantically."
            )
        } else if semanticVM.model.queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            emptyState(
                icon: "text.magnifyingglass",
                title: "Describe what you want to find",
                subtitle: "Try phrases like person speaking to camera or hands typing on a keyboard."
            )
        } else if semanticVM.model.isBuildingIndex || semanticVM.model.isSearching {
            emptyState(
                icon: "sparkle.magnifyingglass",
                title: "Searching clips",
                subtitle: "Results will appear here as soon as the index finishes and the search completes."
            )
        } else {
            emptyState(
                icon: "tray",
                title: "No matches found",
                subtitle: "Try a broader description or import additional video clips."
            )
        }
    }

    private func emptyState(icon: String, title: String, subtitle: String) -> some View {
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
            guard let results = grouped[id], let first = results.first else { return nil }
            return SemanticResultGroup(
                id: id,
                title: first.videoName,
                segments: results.sorted { $0.confidence > $1.confidence }
            )
        }
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
    let title: String
    let segments: [SemanticMatchRange]

    var bestConfidence: Double {
        segments.map(\.confidence).max() ?? 0
    }
}

private struct SemanticResultGroupCard: View {
    let group: SemanticResultGroup
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Button {
                guard group.segments.count > 1 else { return }
                withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
                    isExpanded.toggle()
                }
            } label: {
                ZStack(alignment: .topLeading) {
                    if group.segments.count > 1, !isExpanded {
                        stackedBackground(offset: 8, opacity: 0.26)
                        stackedBackground(offset: 4, opacity: 0.4)
                    }

                    headerCard
                }
            }
            .buttonStyle(.plain)

            if isExpanded || group.segments.count == 1 {
                VStack(spacing: .spacing(.sp2)) {
                    ForEach(group.segments) { segment in
                        SemanticSegmentRow(result: segment)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.bottom, group.segments.count > 1 && !isExpanded ? 8 : 0)
    }

    private var headerCard: some View {
        HStack(alignment: .center, spacing: .spacing(.sp3)) {
            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                Text(group.title)
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(1)

                Text(group.segments.count == 1 ? "1 segment" : "\(group.segments.count) matching segments")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: .spacing(.sp1)) {
                Text("Best \(String(format: "%.2f", group.bestConfidence))")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.accentFg)

                if group.segments.count > 1 {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.ds.textMuted)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.sp3)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }

    private func stackedBackground(offset: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: .spacing(.sp2))
            .fill(Color.ds.surface.opacity(opacity))
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp2))
                    .stroke(Color.ds.border.opacity(opacity), lineWidth: 1)
            )
            .offset(y: offset)
            .padding(.horizontal, offset)
    }
}

private struct SemanticSegmentRow: View {
    let result: SemanticMatchRange

    var body: some View {
        let transferItem = ImportedTimelineSegment(
            mediaId: result.videoID,
            startTimeUs: timeToMicroseconds(result.startTimeSeconds),
            endTimeUs: timeToMicroseconds(result.endTimeSeconds)
        )

        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            HStack(spacing: .spacing(.sp2)) {
                Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)

                Spacer()

                Text(String(format: "%.2f", result.confidence))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.accentFg)
            }

            Text("Drag into timeline")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.sp3)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        .draggable(transferItem) {
            segmentPreview
        }
    }

    private var segmentPreview: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(result.videoName)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .lineLimit(1)

            Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
        .padding(.sp3)
        .background(Color.ds.surface)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
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

private struct ImportedTimelineSegment: Codable, Transferable {
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
