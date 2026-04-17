import CoreTransferable
import AVKit
import SwiftUI
import UniformTypeIdentifiers
internal import Combine

@MainActor
struct ImportPanelContent: View {
    @ObservedObject var controller: TimelineController
    let onOpenVideoImport: () -> Void

    @State private var filterTag: MediaFilterTag = .all
    @State private var isSemanticSearchActive = false
    @State private var selectedSemanticGroupSelection: SemanticGroupSelection?
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
                "semantic search toggled active=\(isActive) selectedVideo=\(selectedSemanticGroupSelection?.videoID ?? "nil")"
            )
            if isActive {
                Task { @MainActor in
                    await Task.yield()
                    isSearchFieldFocused = true
                    EditorDebugTrace.log("ImportPanelContent", "search field focus requested")
                }
            } else {
                isSearchFieldFocused = false
                selectedSemanticGroupSelection = nil
                semanticVM.clearSearch()
            }
        }
        .onChange(of: semanticVM.model.results) { _, results in
            EditorDebugTrace.log(
                "ImportPanelContent",
                "semantic results updated count=\(results.count) isSearching=\(semanticVM.model.isSearching)"
            )
            guard let selectedSemanticGroupSelection else { return }
            if !results.contains(where: {
                $0.videoID == selectedSemanticGroupSelection.videoID
                    && $0.source == selectedSemanticGroupSelection.source
            }) {
                self.selectedSemanticGroupSelection = nil
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
                if selectedSemanticGroupSelection != nil {
                    Button {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                            selectedSemanticGroupSelection = nil
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
                                selectedSemanticGroupSelection = nil
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
        } else if visualSemanticGroups.isEmpty && audioSemanticGroups.isEmpty {
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
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                semanticResultSection(
                    title: "Visual matches",
                    groups: visualSemanticGroups,
                    state: state
                )
                semanticResultSection(
                    title: "Audio matches",
                    groups: audioSemanticGroups,
                    state: state
                )
            }
            .padding(.horizontal, .sp3)
            .padding(.vertical, .sp3)
        }
    }

    @ViewBuilder
    private func semanticResultSection(
        title: String,
        groups: [SemanticResultGroup],
        state: TimelineState
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            if groups.isEmpty {
                Text("No matches")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 4)], spacing: 4) {
                    ForEach(groups) { group in
                        if let media = state.mediaById[group.id] {
                            SemanticVideoResultCell(media: media, matchCount: group.segments.count)
                                .onTapGesture {
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.88)) {
                                        selectedSemanticGroupSelection = SemanticGroupSelection(
                                            source: group.source,
                                            videoID: group.id
                                        )
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    private func semanticRangeGrid(for group: SemanticResultGroup, state: TimelineState) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                Text(group.source == .visual ? "Visual matches" : "Audio matches")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .padding(.horizontal, .sp3)
                    .padding(.top, .sp3)

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
                .padding(.horizontal, .sp3)
                .padding(.bottom, .sp3)
            }
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

    private var visualSemanticGroups: [SemanticResultGroup] {
        semanticGroups(for: semanticVM.model.visualResults)
    }

    private var audioSemanticGroups: [SemanticResultGroup] {
        semanticGroups(for: semanticVM.model.audioResults)
    }

    private func semanticGroups(for results: [SemanticMatchRange]) -> [SemanticResultGroup] {
        var grouped: [String: [SemanticMatchRange]] = [:]
        var orderedIds: [String] = []

        for result in results {
            if grouped[result.videoID] == nil {
                orderedIds.append(result.videoID)
            }
            grouped[result.videoID, default: []].append(result)
        }

        return orderedIds.compactMap { id in
            guard let results = grouped[id] else { return nil }
            return SemanticResultGroup(
                id: id,
                source: results.first?.source ?? .visual,
                segments: results.sorted { $0.confidence > $1.confidence }
            )
        }
    }

    private var selectedGroup: SemanticResultGroup? {
        guard let selectedSemanticGroupSelection else { return nil }
        let groups = selectedSemanticGroupSelection.source == .visual ? visualSemanticGroups : audioSemanticGroups
        return groups.first(where: { $0.id == selectedSemanticGroupSelection.videoID })
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
