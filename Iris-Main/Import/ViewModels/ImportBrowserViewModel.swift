internal import Combine
import Foundation
import Photos

@MainActor
final class ImportBrowserViewModel: ObservableObject {
    @Published private(set) var model = ImportBrowserModel()

    private let timelineId: String?
    private let mediaImportService: MediaImportService
    private let audioExtractionService: AudioExtractionService
    private let projectClipProcessingService: ProjectClipProcessingService
    private let db: DatabaseManager
    private let semanticSearchViewModel: SemanticSearchViewModel

    private var didLoadLibrary = false
    private var assetLookup: [String: PHAsset] = [:]
    private var commitmentTasks: [String: Task<Void, Never>] = [:]
    private var embeddingTasks: [String: Task<Void, Never>] = [:]
    private var pendingUploadKeys: Set<String> = []
    private var uploadFlushTask: Task<Void, Never>?

    init(
        timelineId: String?,
        mediaImportService: MediaImportService = .shared,
        audioExtractionService: AudioExtractionService? = nil,
        projectClipProcessingService: ProjectClipProcessingService? = nil,
        db: DatabaseManager? = nil,
        semanticSearchViewModel: SemanticSearchViewModel = .shared
    ) {
        self.timelineId = timelineId
        self.mediaImportService = mediaImportService
        self.audioExtractionService = audioExtractionService ?? AudioExtractionService()
        self.projectClipProcessingService = projectClipProcessingService ?? ProjectClipProcessingService()
        self.db = db ?? .shared
        self.semanticSearchViewModel = semanticSearchViewModel
    }

    deinit {
        uploadFlushTask?.cancel()
        commitmentTasks.values.forEach { $0.cancel() }
        embeddingTasks.values.forEach { $0.cancel() }
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
            if !mode.runsEmbeddings, model.clips[index].embeddingState == .idle {
                model.clips[index].embeddingState = .succeeded("Embeddings skipped")
            }
            if !mode.runsAgentPreprocessing, model.clips[index].uploadState == .idle {
                model.clips[index].uploadState = .succeeded("Agent prep skipped")
            }
            if mode.runsEmbeddings, model.clips[index].isCommitted, model.clips[index].embeddingState.isSucceeded == false {
                startEmbeddingIfNeeded(for: model.clips[index].localKey)
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
            displayName: displayName(for: asset),
            originalURL: nil,
            fileSize: nil,
            localMediaID: nil,
            remoteClipID: nil,
            isSelected: true,
            isCommitted: false,
            embeddingState: model.processingMode.runsEmbeddings ? .queued("Waiting for commit") : .succeeded("Embeddings skipped"),
            uploadState: model.processingMode.runsAgentPreprocessing ? .queued("Waiting for commit") : .succeeded("Agent prep skipped"),
            commitmentStatus: "Hold selection to begin processing"
        )
        model.clips.append(clip)
        refreshVisibleAssetSelectionState()
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

    func cancelClip(localKey: String, removeFromSelection: Bool = true) async {
        commitmentTasks[localKey]?.cancel()
        commitmentTasks[localKey] = nil
        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = nil
        pendingUploadKeys.remove(localKey)

        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey }) else { return }
        let clip = model.clips[index]

        if let localMediaID = clip.localMediaID {
            try? db.delete(Media.self, id: localMediaID, keyColumn: "media_id")
            await resyncSemanticIndexIfNeeded()
        }

        if let remoteSession = model.remoteSession,
           clip.remoteClipID != nil || clip.uploadState.isRunning || clip.uploadState.isSucceeded || clip.uploadState.isFailed {
            try? await projectClipProcessingService.cancelClip(localKey: localKey, remoteSession: remoteSession)
        }

        if let url = clip.originalURL {
            try? FileManager.default.removeItem(at: url)
        }

        if removeFromSelection {
            model.clips.removeAll { $0.localKey == localKey }
        } else {
            model.clips[index].isSelected = false
            model.clips[index].embeddingState = .cancelled
            model.clips[index].uploadState = .cancelled
        }

        refreshVisibleAssetSelectionState()
        updateStatusAndReadiness()
    }

    private func reloadAlbums() {
        let collections = mediaImportService.fetchVideoAlbums()
        var albums = [ImportBrowserAlbum(id: ImportBrowserAlbum.allVideosID, title: "All Videos", count: mediaImportService.fetchVideos(in: nil).count)]
        albums.append(contentsOf: collections.map { collection in
            let count = mediaImportService.fetchVideos(in: collection.localIdentifier).count
            return ImportBrowserAlbum(
                id: collection.localIdentifier,
                title: collection.localizedTitle ?? "Folder",
                count: count
            )
        })
        model.albums = albums.filter { $0.count > 0 }
        if !model.albums.contains(where: { $0.id == model.selectedAlbumID }) {
            model.selectedAlbumID = model.albums.first?.id ?? ImportBrowserAlbum.allVideosID
        }
        reloadAssets()
    }

    private func reloadAssets() {
        let collectionID = model.selectedAlbumID == ImportBrowserAlbum.allVideosID ? nil : model.selectedAlbumID
        let assets = mediaImportService.fetchVideos(in: collectionID)
        assetLookup = Dictionary(uniqueKeysWithValues: assets.map { ($0.localIdentifier, $0) })
        model.visibleAssets = assets.map { asset in
            let activeClip = model.clips.first { $0.assetLocalIdentifier == asset.localIdentifier && $0.isSelected }
            return ImportBrowserAsset(
                id: asset.localIdentifier,
                displayName: displayName(for: asset),
                durationText: formatDuration(asset.duration),
                createdAt: asset.creationDate,
                isSelected: activeClip != nil,
                isCommitted: activeClip?.isCommitted ?? false
            )
        }
    }

    private func scheduleCommitment(for localKey: String) {
        commitmentTasks[localKey]?.cancel()
        commitmentTasks[localKey] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.commitClip(localKey: localKey)
        }
    }

    private func commitClip(localKey: String) async {
        commitmentTasks[localKey] = nil
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else { return }
        guard let asset = assetLookup[model.clips[index].assetLocalIdentifier] else { return }

        model.clips[index].commitmentStatus = "Exporting clip"

        do {
            let localURL = try await mediaImportService.exportVideoAssetToTemporaryURL(asset)
            guard let refreshedIndex = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else {
                try? FileManager.default.removeItem(at: localURL)
                return
            }

            model.clips[refreshedIndex].originalURL = localURL
            model.clips[refreshedIndex].fileSize = mediaImportService.fileSize(for: localURL)
            model.clips[refreshedIndex].isCommitted = true
            model.clips[refreshedIndex].commitmentStatus = "Committed"
            refreshVisibleAssetSelectionState()

            startEmbeddingIfNeeded(for: localKey)
            if model.processingMode.runsAgentPreprocessing {
                enqueueClipForUpload(localKey: localKey)
            }
        } catch {
            model.clips[index].embeddingState = .failed(error.localizedDescription)
            model.clips[index].uploadState = .failed(error.localizedDescription)
            model.clips[index].commitmentStatus = "Export failed"
        }

        updateStatusAndReadiness()
    }

    private func startEmbeddingIfNeeded(for localKey: String) {
        guard model.processingMode.runsEmbeddings else { return }
        guard let clipIndex = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else { return }
        guard model.clips[clipIndex].embeddingState.isSucceeded == false else { return }
        guard let originalURL = model.clips[clipIndex].originalURL else { return }

        model.clips[clipIndex].embeddingState = .running("Preparing local embeddings")

        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = Task { [weak self] in
            guard let self else { return }
            do {
                guard let mediaLibraryID = try self.resolveMediaLibraryID() else {
                    await MainActor.run {
                        self.updateClip(localKey: localKey) { clip in
                            clip.embeddingState = .failed("Could not resolve the local media library.")
                        }
                    }
                    return
                }

                let imported = try await self.mediaImportService.importFileURLsQuick(
                    [originalURL],
                    to: mediaLibraryID,
                    preferredKind: .video
                )
                guard let media = imported.first else {
                    throw NSError(
                        domain: "ImportBrowserViewModel",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "The clip could not be added to the local library."]
                    )
                }

                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.localMediaID = media.mediaId
                        clip.embeddingState = .succeeded("Embeddings queued locally")
                    }
                }
                await self.resyncSemanticIndexIfNeeded()
            } catch is CancellationError {
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.embeddingState = .cancelled
                    }
                }
            } catch {
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.embeddingState = .failed(error.localizedDescription)
                    }
                }
            }
            await MainActor.run {
                self.embeddingTasks[localKey] = nil
                self.updateStatusAndReadiness()
            }
        }
    }

    private func enqueueClipForUpload(localKey: String) {
        guard model.processingMode.runsAgentPreprocessing else { return }
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected && $0.isCommitted }) else {
            return
        }
        if model.clips[index].remoteClipID != nil {
            return
        }

        pendingUploadKeys.insert(localKey)
        model.clips[index].uploadState = .queued("Queued for upload")
        scheduleUploadFlushIfNeeded()
        updateStatusAndReadiness()
    }

    private func scheduleUploadFlushIfNeeded() {
        guard uploadFlushTask == nil else { return }
        uploadFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushPendingUploads()
        }
    }

    private func flushPendingUploads() async {
        uploadFlushTask = nil
        let localKeys = Array(pendingUploadKeys)
        pendingUploadKeys.removeAll()
        guard !localKeys.isEmpty else { return }

        do {
            let remoteSession = try await ensureRemoteSession()
            let selectedVideos = model.clips.compactMap { clip -> SelectedVideoAsset? in
                guard localKeys.contains(clip.localKey),
                      clip.isSelected,
                      clip.isCommitted,
                      let originalURL = clip.originalURL else { return nil }
                return SelectedVideoAsset(
                    localKey: clip.localKey,
                    originalURL: originalURL,
                    displayName: clip.displayName,
                    fileSize: clip.fileSize,
                    remoteClipID: clip.remoteClipID
                )
            }

            guard !selectedVideos.isEmpty else {
                updateStatusAndReadiness()
                return
            }

            for localKey in selectedVideos.map(\.localKey) {
                updateClip(localKey: localKey) { clip in
                    clip.uploadState = .running("Extracting audio")
                }
            }

            let processedAssets = try await extractAudioBatch(from: selectedVideos)

            for localKey in processedAssets.map(\.localKey) {
                updateClip(localKey: localKey) { clip in
                    clip.uploadState = .running("Uploading to the agent")
                }
            }

            let response = try await projectClipProcessingService.uploadBatch(processedAssets, to: remoteSession)
            cleanupProcessedAssets(processedAssets)
            applyServerResponse(response)
        } catch {
            for localKey in localKeys {
                updateClip(localKey: localKey) { clip in
                    if clip.isSelected {
                        clip.uploadState = .failed(error.localizedDescription)
                    }
                }
            }
        }

        if !pendingUploadKeys.isEmpty {
            scheduleUploadFlushIfNeeded()
        }
        updateStatusAndReadiness()
    }

    private func extractAudioBatch(from videos: [SelectedVideoAsset]) async throws -> [ProcessedAudioAsset] {
        let audioExtractionService = self.audioExtractionService
        return try await withThrowingTaskGroup(of: ProcessedAudioAsset.self) { group in
            for video in videos {
                group.addTask {
                    try await audioExtractionService.extractCompressedAudio(from: video)
                }
            }

            var processedAssets: [ProcessedAudioAsset] = []
            for try await asset in group {
                processedAssets.append(asset)
            }
            return processedAssets
        }
    }

    private func applyServerResponse(_ response: IngestResponse) {
        model.ingestResponse = response

        if let remoteSession = model.remoteSession,
           let projectID = response.projectID?.rawValue,
           projectID != remoteSession.projectID {
            model.remoteSession = RemoteImportSession(
                sessionID: response.sessionID.rawValue,
                sessionName: response.sessionName,
                projectID: projectID,
                projectName: response.projectName ?? remoteSession.projectName
            )
        }

        let responseByLocalKey: [String: IngestVideoResponse] = Dictionary(
            uniqueKeysWithValues: response.videos.compactMap { video in
                guard let localKey = video.localKey else { return nil }
                return (localKey, video)
            }
        )

        for index in model.clips.indices {
            let localKey = model.clips[index].localKey
            guard let responseVideo = responseByLocalKey[localKey] else { continue }
            model.clips[index].remoteClipID = responseVideo.clipID.rawValue

            switch responseVideo.processingStatus {
            case "ready":
                model.clips[index].uploadState = .succeeded("Ready on the server")
            case "failed":
                model.clips[index].uploadState = .failed(responseVideo.processingError ?? "Clip preprocessing failed.")
            case "cancelled":
                model.clips[index].uploadState = .cancelled
            case "processing":
                model.clips[index].uploadState = .running("Still processing on the server")
            default:
                model.clips[index].uploadState = .queued("Waiting for the server")
            }
        }
    }

    private func ensureRemoteSession() async throws -> RemoteImportSession {
        if let remoteSession = model.remoteSession {
            return remoteSession
        }

        let response = try await projectClipProcessingService.createRemoteSession(projectName: localProjectName())
        let remoteSession = RemoteImportSession(
            sessionID: response.sessionID.rawValue,
            sessionName: response.sessionName,
            projectID: response.projectID.rawValue,
            projectName: response.projectName
        )
        model.remoteSession = remoteSession
        return remoteSession
    }

    private func refreshVisibleAssetSelectionState() {
        for index in model.visibleAssets.indices {
            let assetID = model.visibleAssets[index].id
            let activeClip = model.clips.first { $0.assetLocalIdentifier == assetID && $0.isSelected }
            model.visibleAssets[index].isSelected = activeClip != nil
            model.visibleAssets[index].isCommitted = activeClip?.isCommitted ?? false
        }
    }

    private func updateClip(localKey: String, mutate: (inout ImportClipProcessingItem) -> Void) {
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey }) else { return }
        mutate(&model.clips[index])
    }

    private func updateStatusAndReadiness() {
        let selectedCount = model.selectedClipCount
        let committedCount = model.committedClipCount
        let hasFailures = model.clips.contains(where: \.hasFailure)
        let hasRunningWork = model.clips.contains {
            ($0.isSelected && $0.isCommitted && model.processingMode.runsEmbeddings && $0.embeddingState.isRunning)
                || ($0.isSelected && $0.isCommitted && model.processingMode.runsAgentPreprocessing && $0.uploadState.isRunning)
        } || !pendingUploadKeys.isEmpty || uploadFlushTask != nil

        if hasFailures {
            model.statusMessage = "Fix or remove the failed clips before starting the live session."
        } else if hasRunningWork {
            model.statusMessage = "Preparing \(committedCount) clip\(committedCount == 1 ? "" : "s") for Iris."
        } else if committedCount > 0 {
            model.statusMessage = "\(committedCount) clip\(committedCount == 1 ? "" : "s") ready for Iris."
        } else if selectedCount > 0 {
            model.statusMessage = "Keep a clip selected for 2 seconds to begin processing."
        } else {
            model.statusMessage = "Select clips to start preparing them for Iris."
        }

        let remoteReady = model.processingMode.runsAgentPreprocessing
            ? (model.ingestResponse?.readyForWebSocket ?? false)
            : false
        let embeddingReady = model.clips
            .filter { $0.isSelected && $0.isCommitted }
            .allSatisfy { clip in
                !model.processingMode.runsEmbeddings || clip.embeddingState.isSucceeded
            }
        let uploadReady = model.clips
            .filter { $0.isSelected && $0.isCommitted }
            .allSatisfy { clip in
                !model.processingMode.runsAgentPreprocessing || clip.uploadState.isSucceeded
            }
        let canTransitionToAgent = model.isAwaitingAgentStart
            && model.prompt.isReady
            && !hasFailures
            && !hasRunningWork
            && committedCount > 0
            && embeddingReady
            && uploadReady
            && remoteReady

        if canTransitionToAgent {
            model.isPreparingAgentTransition = true
        }
    }

    private func validatePromptMessage(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return nil
        }

        if trimmedText.count < 8 {
            return "Add a little more detail so Iris knows how to shape the edit."
        }

        return nil
    }

    private func resolveMediaLibraryID() throws -> String? {
        guard let timelineId else { return nil }
        guard let timeline = try db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id") else { return nil }
        return try db.getMediaLibrary(forProjectId: timeline.projectId)?.id
    }

    private func resyncSemanticIndexIfNeeded() async {
        guard let mediaLibraryID = try? resolveMediaLibraryID() else { return }
        let media = (try? db.getAllMedia(forLibraryId: mediaLibraryID)) ?? []
        semanticSearchViewModel.queueImportedMediaSync(media, autoBuildIndex: true)
    }

    private func localProjectName() -> String? {
        guard let timelineId,
              let timeline = try? db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id"),
              let project = try? db.get(Project.self, id: timeline.projectId, keyColumn: "project_id") else {
            return nil
        }
        return project.name
    }

    private func displayName(for asset: PHAsset) -> String {
        PHAssetResource.assetResources(for: asset).first?.originalFilename ?? "Clip"
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func cleanupProcessedAssets(_ assets: [ProcessedAudioAsset]) {
        for asset in assets {
            try? FileManager.default.removeItem(at: asset.audioURL)
        }
    }
}
