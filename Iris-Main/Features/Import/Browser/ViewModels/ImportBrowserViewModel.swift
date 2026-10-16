internal import Combine
import Foundation
import Photos

func orderedProcessedAssetsForUpload(
    _ processedAssets: [ProcessedAudioAsset],
    matching videos: [SelectedVideoAsset]
) -> [ProcessedAudioAsset] {
    var assetsByLocalKey = Dictionary(uniqueKeysWithValues: processedAssets.map { ($0.localKey, $0) })
    var orderedAssets = videos.compactMap { assetsByLocalKey.removeValue(forKey: $0.localKey) }
    orderedAssets.append(contentsOf: assetsByLocalKey.values.sorted { $0.localKey < $1.localKey })
    return orderedAssets
}

@MainActor
final class ImportBrowserViewModel: ObservableObject {
    @Published var model = ImportBrowserModel()

    let timelineId: String?
    let mediaImportService: MediaImportService
    let audioExtractionService: AudioExtractionService
    let projectClipProcessingService: ProjectClipProcessingService
    let db: DatabaseManager

    var didLoadLibrary = false
    var assetLookup: [String: PHAsset] = [:]
    var commitmentTasks: [String: Task<Void, Never>] = [:]
    var localMediaTasks: [String: Task<String, Error>] = [:]
    var sessionStatusPollTask: Task<Void, Never>?
    var pendingUploadKeys: Set<String> = []
    var uploadFlushTask: Task<Void, Never>?
    var filenameCache: [String: String] = [:]
    var filenameTasks: [String: Task<Void, Never>] = [:]

    init(
        timelineId: String?,
        mediaImportService: MediaImportService = .shared,
        audioExtractionService: AudioExtractionService? = nil,
        projectClipProcessingService: ProjectClipProcessingService? = nil,
        db: DatabaseManager? = nil
    ) {
        self.timelineId = timelineId
        self.mediaImportService = mediaImportService
        self.audioExtractionService = audioExtractionService ?? AudioExtractionService()
        self.projectClipProcessingService = projectClipProcessingService ?? ProjectClipProcessingService()
        self.db = db ?? .shared
    }

    deinit {
        uploadFlushTask?.cancel()
        commitmentTasks.values.forEach { $0.cancel() }
        localMediaTasks.values.forEach { $0.cancel() }
        sessionStatusPollTask?.cancel()
        filenameTasks.values.forEach { $0.cancel() }
    }

    func loadLibraryIfNeeded() async {
        guard !didLoadLibrary else { return }
        didLoadLibrary = true
        model.isLoadingLibrary = true
        model.loadErrorMessage = nil

        let currentStatus = mediaImportService.authorizationStatus()
        if currentStatus == .notDetermined {
            model.authorizationStatus = await mediaImportService.requestPhotoLibraryAccess()
        } else {
            model.authorizationStatus = currentStatus
        }

        guard model.authorizationStatus == .authorized || model.authorizationStatus == .limited else {
            model.isLoadingLibrary = false
            model.loadErrorMessage = "Allow photo library access to browse your clips."
            model.statusMessage = "Photo library access is required to import clips."
            return
        }

        reloadAlbums()
        model.isLoadingLibrary = false
    }

    func selectAlbum(_ albumID: String) {
        guard model.selectedAlbumID != albumID else { return }
        model.selectedAlbumID = albumID
        reloadAssets()
    }

    func updatePromptMessage(_ text: String) {
        model.prompt.text = text
        model.prompt.validationMessage = validatePromptMessage(text)
        updateStatusAndReadiness()
    }

    func applyPromptSuggestion(_ suggestion: String) {
        updatePromptMessage(suggestion)
    }

    func toggleSelection(for assetID: String) {
        if let existingIndex = model.clips.firstIndex(where: { $0.assetLocalIdentifier == assetID && $0.isSelected }) {
            let localKey = model.clips[existingIndex].localKey
            Task {
                await cancelClip(localKey: localKey, removeFromSelection: true)
            }
            return
        }

        guard let asset = assetLookup[assetID] else { return }
        let localKey = UUID().uuidString
        let clip = ImportClipProcessingItem(
            localKey: localKey,
            assetLocalIdentifier: asset.localIdentifier,
            displayName: cachedOrPlaceholderDisplayName(for: asset.localIdentifier),
            originalURL: nil,
            fileSize: nil,
            localMediaID: nil,
            remoteClipID: nil,
            isSelected: true,
            isCommitted: false,
            transcriptState: .succeeded("Transcript on server"),
            uploadState: .queued("Waiting for commit"),
            commitmentStatus: "Hold selection to begin processing"
        )
        model.clips.append(clip)
        refreshVisibleAssetSelectionState()
        loadOriginalFilenameIfNeeded(for: asset.localIdentifier)
        scheduleCommitment(for: localKey)
        updateStatusAndReadiness()
    }

    func requestAgentStart() {
        guard model.canRequestAgentStart else { return }
        model.isAwaitingAgentStart = true
        updateStatusAndReadiness()
    }

    func finishPreparingAgentTransition() {
        model.isPreparingAgentTransition = false
    }

    func clearAwaitingAgentStart() {
        model.isAwaitingAgentStart = false
    }

    func clip(for localKey: String) -> ImportClipProcessingItem? {
        model.clips.first(where: { $0.localKey == localKey })
    }

    func finalizeSelectedMediaImports() async -> [Media] {
        let selectedKeys = model.clips
            .filter(\.isSelected)
            .map(\.localKey)
        guard !selectedKeys.isEmpty else { return [] }

        for localKey in selectedKeys {
            guard let clip = clip(for: localKey), clip.isCommitted == false else { continue }
            commitmentTasks[localKey]?.cancel()
            await commitClip(localKey: localKey)
        }

        for localKey in selectedKeys {
            do {
                _ = try await ensureLocalMediaAvailable(for: localKey)
            } catch {
                print("[ImportBrowser] local media import failed localKey=\(localKey): \(error)")
            }
        }

        updateStatusAndReadiness()

        // Agent upload is debounced by `scheduleUploadFlushIfNeeded` (~1s). Dismissing the import sheet
        // deinitializes this view model and cancels `uploadFlushTask`, so uploads would never run unless
        // we flush here before returning (e.g. editor `ClipImportSheetView` dismisses immediately after Add).
        uploadFlushTask?.cancel()
        uploadFlushTask = nil
        if !pendingUploadKeys.isEmpty {
            await flushPendingUploads()
        }

        return selectedKeys.compactMap { localKey in
            guard let mediaID = clip(for: localKey)?.localMediaID else { return nil }
            return try? db.getMedia(mediaId: mediaID)
        }
    }

    func cancelClip(localKey: String, removeFromSelection: Bool = true) async {
        commitmentTasks[localKey]?.cancel()
        commitmentTasks[localKey] = nil
        localMediaTasks[localKey]?.cancel()
        localMediaTasks[localKey] = nil
        pendingUploadKeys.remove(localKey)

        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey }) else { return }
        let clip = model.clips[index]

        if let localMediaID = clip.localMediaID {
            try? db.delete(Media.self, id: localMediaID, keyColumn: "media_id")
        }

        if let backendProject = model.remoteBackendProject,
           clip.remoteClipID != nil || clip.uploadState.isRunning || clip.uploadState.isSucceeded || clip.uploadState.isFailed {
            _ = try? await projectClipProcessingService.cancelClip(
                localKey: localKey,
                backendProjectID: backendProject.projectID
            )
        }

        if let url = clip.originalURL {
            try? FileManager.default.removeItem(at: url)
        }

        if removeFromSelection {
            model.clips.removeAll { $0.localKey == localKey }
        } else {
            model.clips[index].isSelected = false
            model.clips[index].transcriptState = .cancelled
            model.clips[index].uploadState = .cancelled
        }

        refreshVisibleAssetSelectionState()
        updateStatusAndReadiness()
    }

}
