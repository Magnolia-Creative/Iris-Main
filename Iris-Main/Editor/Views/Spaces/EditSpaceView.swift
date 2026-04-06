import SwiftUI
import PhotosUI
internal import Combine

struct EditSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID

    @State private var selectedPhotos: [PhotosPickerItem] = []

    private let rulerHeight: CGFloat = 32
    private let trackTopOffset: CGFloat = 40
    private let iconSize: CGFloat = 24

    var body: some View {
        let state = controller.state

        VStack(spacing: .spacing(.sp4)) {
            PreviewSection(
                controller: playbackController ?? PlaybackController(
                    statePublisher: controller.$state.eraseToAnyPublisher(),
                    actions: controller
                ),
                renderBridge: renderBridge
            )
            .matchedGeometryEffect(id: "preview", in: namespace)
            .padding(.horizontal, .sp3)

            if let pc = playbackController {
                PlaybackControls(controller: pc)
                    .padding(.horizontal, .sp4)
            }

            TimelineSectionView(
                tracks: state.orderedTracks,
                clipsByTrackId: state.clipsByTrackId,
                mediaById: state.mediaById,
                pixelsPerSecond: state.pixelsPerSecond,
                rulerHeight: rulerHeight,
                trackTopOffset: trackTopOffset,
                iconSize: iconSize,
                timelineDurationUs: state.calculatedTimelineDurationUs,
                scrollableDurationUs: state.scrollableDurationUs,
                currentTimeAtCenter: controller.binding(\.currentTimeAtCenter),
                scrollTargetTimeUs: controller.binding(\.scrollTargetTimeUs),
                selectedClipId: controller.binding(\.selectedClipId),
                onAddSelection: controller.handleAddSelection(kind:source:),
                onMoveClip: controller.moveClip(clipId:toStartTimeUs:orderedClipIds:),
                onTrimClip: controller.trimClip(clipId:sourceRange:timelineRange:commit:)
            )
            .frame(maxHeight: .infinity)
            .matchedGeometryEffect(id: "timeline", in: namespace)
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
}
