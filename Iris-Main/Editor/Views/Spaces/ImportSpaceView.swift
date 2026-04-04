import SwiftUI
import PhotosUI
internal import Combine

struct ImportSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID

    @State private var selectedPhotos: [PhotosPickerItem] = []
    @State private var filterTag: MediaFilterTag = .all
    @State private var showSemanticSearch = false
    @StateObject private var semanticVM = SemanticSearchViewModel()

    enum MediaFilterTag: String, CaseIterable {
        case all = "All"
        case photos = "Photos"
        case videos = "Videos"
    }

    var body: some View {
        let state = controller.state

        VStack(spacing: 0) {
            // Compressed preview
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

            // Compressed timeline
            TimelineSectionView(
                tracks: state.orderedTracks,
                clipsByTrackId: state.clipsByTrackId,
                mediaById: state.mediaById,
                pixelsPerSecond: state.pixelsPerSecond,
                rulerHeight: 28,
                trackTopOffset: 32,
                iconSize: 20,
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
            .frame(height: 100)
            .matchedGeometryEffect(id: "timeline", in: namespace)

            // Import panel
            VStack(spacing: 0) {
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
                                    .background(filterTag == tag ? Color.ds.accentBg : Color.ds.surface)
                                    .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Spacer()

                    Button { showSemanticSearch.toggle() } label: {
                        Image(systemName: "sparkle.magnifyingglass")
                            .font(.system(size: 20))
                            .foregroundColor(Color.ds.accentFg)
                    }
                }
                .padding(.horizontal, .sp4)
                .padding(.vertical, .sp3)

                Divider().background(Color.ds.border)

                mediaGrid(state: state)
            }
            .frame(maxHeight: .infinity)
            .background(Color.ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4), style: .continuous))
            .padding(.horizontal, .sp3)
        }
        .onChange(of: selectedPhotos) { _, items in
            importSelectedPhotos(items)
        }
        .sheet(isPresented: $showSemanticSearch) {
            SemanticView()
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

    private func importSelectedPhotos(_ items: [PhotosPickerItem]) {
        guard !items.isEmpty, let library = controller.state.mediaLibrary else { return }
        Task {
            var importedMedia: [Media] = []
            for item in items {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    let fileManager = FileManager.default
                    let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    let importsURL = documentsURL.appendingPathComponent("Imports", isDirectory: true)
                    try? fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)
                    let fileName = "\(UUID().uuidString).mov"
                    let fileURL = importsURL.appendingPathComponent(fileName)
                    try? data.write(to: fileURL)
                    let media = try await MediaImportService.shared.importFileURLs(
                        [fileURL], to: library.id, preferredKind: .video
                    )
                    importedMedia.append(contentsOf: media)
                }
            }
            if !importedMedia.isEmpty {
                await MainActor.run {
                    controller.ingestMedia(importedMedia, kind: .video)
                }
            }
            selectedPhotos = []
        }
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
