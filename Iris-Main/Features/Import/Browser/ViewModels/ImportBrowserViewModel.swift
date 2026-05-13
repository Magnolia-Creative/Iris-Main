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
    let clipTranscriptService: ClipTranscriptService
    let projectClipProcessingService: ProjectClipProcessingService
    let db: DatabaseManager
    let semanticSearchViewModel: SemanticSearchViewModel

    var didLoadLibrary = false
    var assetLookup: [String: PHAsset] = [:]
    var commitmentTasks: [String: Task<Void, Never>] = [:]
    var localMediaTasks: [String: Task<String, Error>] = [:]
    var embeddingTasks: [String: Task<Void, Never>] = [:]
    var transcriptionTasks: [String: Task<Void, Never>] = [:]
    var sessionStatusPollTask: Task<Void, Never>?
    var pendingUploadKeys: Set<String> = []
    var uploadFlushTask: Task<Void, Never>?
    var filenameCache: [String: String] = [:]
    var filenameTasks: [String: Task<Void, Never>] = [:]

    init(
        timelineId: String?,
        mediaImportService: MediaImportService = .shared,
        audioExtractionService: AudioExtractionService? = nil,
        clipTranscriptService: ClipTranscriptService? = nil,
        projectClipProcessingService: ProjectClipProcessingService? = nil,
        db: DatabaseManager? = nil,
        semanticSearchViewModel: SemanticSearchViewModel = .shared
    ) {
        self.timelineId = timelineId
        self.mediaImportService = mediaImportService
        self.audioExtractionService = audioExtractionService ?? AudioExtractionService()
        self.clipTranscriptService = clipTranscriptService ?? ClipTranscriptService()
        self.projectClipProcessingService = projectClipProcessingService ?? ProjectClipProcessingService()
        self.db = db ?? .shared
        self.semanticSearchViewModel = semanticSearchViewModel
    }

    deinit {
        uploadFlushTask?.cancel()
        commitmentTasks.values.forEach { $0.cancel() }
        localMediaTasks.values.forEach { $0.cancel() }
        embeddingTasks.values.forEach { $0.cancel() }
        transcriptionTasks.values.forEach { $0.cancel() }
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

    func updateProcessingMode(_ mode: ImportProcessingMode) {
        guard model.processingMode != mode else { return }
        model.processingMode = mode
        for index in model.clips.indices {
            if !mode.runsEmbeddings, model.clips[index].embeddingState.isRunning {
                embeddingTasks[model.clips[index].localKey]?.cancel()
            }
            if !mode.usesLocalTranscriptionEndpoint {
                transcriptionTasks[model.clips[index].localKey]?.cancel()
            }
            if !mode.runsEmbeddings, model.clips[index].embeddingState == .idle {
                model.clips[index].embeddingState = .succeeded("Embeddings skipped")
            }
            if !mode.runsEmbeddings, model.clips[index].transcriptState == .idle {
                model.clips[index].transcriptState = .succeeded("Transcript skipped")
            }
            if !mode.runsAgentPreprocessing, model.clips[index].uploadState == .idle {
                model.clips[index].uploadState = .succeeded("Agent prep skipped")
            }
            if mode.runsEmbeddings, model.clips[index].isCommitted, model.clips[index].embeddingState.isSucceeded == false {
                startEmbeddingIfNeeded(for: model.clips[index].localKey)
            }
            if mode.usesLocalTranscriptionEndpoint, model.clips[index].isCommitted, model.clips[index].transcriptState.isSucceeded == false {
                startTranscriptionIfNeeded(for: model.clips[index].localKey)
            }
            if mode.runsAgentPreprocessing, mode.runsEmbeddings, model.clips[index].transcriptState.isSucceeded == false {
                model.clips[index].transcriptState = .succeeded("Transcript on server")
            }
            if mode.runsAgentPreprocessing, model.clips[index].isCommitted, model.clips[index].remoteClipID == nil {
                enqueueClipForUpload(localKey: model.clips[index].localKey)
            }
        }
        updateStatusAndReadiness()
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
            embeddingState: model.processingMode.runsEmbeddings ? .queued("Waiting for commit") : .succeeded("Embeddings skipped"),
            transcriptState: {
                if model.processingMode.usesLocalTranscriptionEndpoint {
                    return .queued("Waiting for local transcript")
                }
                if model.processingMode.runsAgentPreprocessing, model.processingMode.runsEmbeddings {
                    return .succeeded("Transcript on server")
                }
                return .succeeded("Transcript skipped")
            }(),
            uploadState: model.processingMode.runsAgentPreprocessing ? .queued("Waiting for commit") : .succeeded("Agent prep skipped"),
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
                updateClip(localKey: localKey) { clip in
                    clip.embeddingState = .failed(error.localizedDescription)
                }
            }
        }

        updateStatusAndReadiness()

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
        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = nil
        transcriptionTasks[localKey]?.cancel()
        transcriptionTasks[localKey] = nil
        pendingUploadKeys.remove(localKey)

        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey }) else { return }
        let clip = model.clips[index]

        if let localMediaID = clip.localMediaID {
            try? db.delete(Media.self, id: localMediaID, keyColumn: "media_id")
            _ = await resyncSemanticIndexIfNeeded(autoBuildIndex: true)
        }

        if let remoteSession = model.remoteSession,
           clip.remoteClipID != nil || clip.uploadState.isRunning || clip.uploadState.isSucceeded || clip.uploadState.isFailed {
            _ = try? await projectClipProcessingService.cancelClip(localKey: localKey, remoteSession: remoteSession)
        }

        if let url = clip.originalURL {
            try? FileManager.default.removeItem(at: url)
        }

        if removeFromSelection {
            model.clips.removeAll { $0.localKey == localKey }
        } else {
            model.clips[index].isSelected = false
            model.clips[index].embeddingState = .cancelled
            model.clips[index].transcriptState = .cancelled
            model.clips[index].uploadState = .cancelled
        }

        refreshVisibleAssetSelectionState()
        updateStatusAndReadiness()
    }

}
