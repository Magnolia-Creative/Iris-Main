internal import Combine
import Foundation
import Photos

@MainActor
final class ImportBrowserViewModel: ObservableObject {
    @Published private(set) var model = ImportBrowserModel()

    private let timelineId: String?
    private let mediaImportService: MediaImportService
    private let audioExtractionService: AudioExtractionService
    private let clipTranscriptService: ClipTranscriptService
    private let projectClipProcessingService: ProjectClipProcessingService
    private let db: DatabaseManager
    private let semanticSearchViewModel: SemanticSearchViewModel

    private var didLoadLibrary = false
    private var assetLookup: [String: PHAsset] = [:]
    private var commitmentTasks: [String: Task<Void, Never>] = [:]
    private var embeddingTasks: [String: Task<Void, Never>] = [:]
    private var transcriptionTasks: [String: Task<Void, Never>] = [:]
    private var pendingUploadKeys: Set<String> = []
    private var uploadFlushTask: Task<Void, Never>?
    private var filenameCache: [String: String] = [:]
    private var filenameTasks: [String: Task<Void, Never>] = [:]

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
        embeddingTasks.values.forEach { $0.cancel() }
        transcriptionTasks.values.forEach { $0.cancel() }
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
            if !mode.runsEmbeddings {
                transcriptionTasks[model.clips[index].localKey]?.cancel()
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
            displayName: cachedOrPlaceholderDisplayName(for: asset.localIdentifier),
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
            if let task = embeddingTasks[localKey] {
                await task.value
            }

            do {
                try await ensureLocalMediaAvailable(for: localKey)
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
        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = nil
        transcriptionTasks[localKey]?.cancel()
        transcriptionTasks[localKey] = nil
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
                displayName: cachedOrPlaceholderDisplayName(for: asset.localIdentifier),
                durationText: formatDuration(asset.duration),
                createdAt: asset.creationDate,
                isSelected: activeClip != nil,
                isCommitted: activeClip?.isCommitted ?? false
            )
        }
    }

    private func scheduleCommitment(for localKey: String) {
        print("[ImportBrowser] scheduleCommitment: localKey=\(localKey) (2s timer)")
        commitmentTasks[localKey]?.cancel()
        commitmentTasks[localKey] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else {
                print("[ImportBrowser] scheduleCommitment: CANCELLED for localKey=\(localKey)")
                return
            }
            await self?.commitClip(localKey: localKey)
        }
    }

    private func commitClip(localKey: String) async {
        commitmentTasks[localKey] = nil
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else {
            print("[ImportBrowser] commitClip: no selected clip for localKey=\(localKey)")
            return
        }
        guard let asset = assetLookup[model.clips[index].assetLocalIdentifier] else {
            print("[ImportBrowser] commitClip: no PHAsset for \(model.clips[index].assetLocalIdentifier)")
            return
        }

        print("[ImportBrowser] commitClip: exporting localKey=\(localKey) processingMode=\(model.processingMode)")
        model.clips[index].commitmentStatus = "Exporting clip"

        do {
            let localURL = try await mediaImportService.exportVideoAssetToTemporaryURL(asset)
            guard let refreshedIndex = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else {
                try? FileManager.default.removeItem(at: localURL)
                print("[ImportBrowser] commitClip: clip deselected during export, discarding")
                return
            }

            model.clips[refreshedIndex].originalURL = localURL
            model.clips[refreshedIndex].fileSize = mediaImportService.fileSize(for: localURL)
            model.clips[refreshedIndex].isCommitted = true
            model.clips[refreshedIndex].commitmentStatus = "Committed"
            print("[ImportBrowser] commitClip: committed localKey=\(localKey) url=\(localURL.lastPathComponent)")
            refreshVisibleAssetSelectionState()

            startEmbeddingIfNeeded(for: localKey)
            if model.processingMode.runsAgentPreprocessing {
                enqueueClipForUpload(localKey: localKey)
            } else {
                print("[ImportBrowser] commitClip: skipping upload – processingMode=\(model.processingMode)")
            }
        } catch {
            print("[ImportBrowser] commitClip: export FAILED – \(error)")
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
        guard model.clips[clipIndex].originalURL != nil else { return }

        model.clips[clipIndex].embeddingState = .running("Preparing local embeddings")

        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureLocalMediaAvailable(for: localKey)
                self.updateClip(localKey: localKey) { clip in
                    clip.embeddingState = .succeeded("Embeddings queued locally")
                }
                self.startTranscriptionIfNeeded(for: localKey)
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

    private func startTranscriptionIfNeeded(for localKey: String) {
        print("[ImportBrowser] transcript task scheduling localKey=\(localKey)")
        transcriptionTasks[localKey]?.cancel()
        transcriptionTasks[localKey] = Task(priority: .utility) { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.transcriptionTasks[localKey] = nil
                }
            }

            do {
                guard let request = try self.makeTranscriptRequest(for: localKey) else {
                    print("[ImportBrowser] transcript task skipped localKey=\(localKey)")
                    return
                }
                print(
                    "[ImportBrowser] transcript task started localKey=\(localKey) mediaID=\(request.mediaID) " +
                    "file=\(request.video.displayName)"
                )
                let processedAsset = try await self.audioExtractionService.extractCompressedAudio(from: request.video)
                print(
                    "[ImportBrowser] transcript audio extracted localKey=\(localKey) audioURL=\(processedAsset.audioURL.lastPathComponent)"
                )
                defer {
                    self.cleanupProcessedAssets([processedAsset])
                }

                let transcript = try await self.clipTranscriptService.transcribe(processedAsset)
                print(
                    "[ImportBrowser] transcript response ready localKey=\(localKey) transcriptID=\(transcript.transcriptID) " +
                    "sentences=\(transcript.sentences.count)"
                )
                try self.persistTranscript(transcript, forMediaID: request.mediaID)
                print("[ImportBrowser] transcript persisted localKey=\(localKey) mediaID=\(request.mediaID)")
                await self.resyncSemanticIndexIfNeeded()
                print("[ImportBrowser] transcript resync queued localKey=\(localKey)")
            } catch is CancellationError {
                print("[ImportBrowser] transcript task cancelled localKey=\(localKey)")
                return
            } catch {
                print("[ImportBrowser] transcript request failed localKey=\(localKey): \(error)")
            }
        }
    }

    private func enqueueClipForUpload(localKey: String) {
        guard model.processingMode.runsAgentPreprocessing else {
            print("[ImportBrowser] enqueueClipForUpload skipped: processingMode does not run agent preprocessing")
            return
        }
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected && $0.isCommitted }) else {
            print("[ImportBrowser] enqueueClipForUpload skipped: no matching selected+committed clip for localKey=\(localKey)")
            return
        }
        if model.clips[index].remoteClipID != nil {
            print("[ImportBrowser] enqueueClipForUpload skipped: clip already has remoteClipID")
            return
        }

        print("[ImportBrowser] enqueueClipForUpload: queuing localKey=\(localKey)")
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
        guard !localKeys.isEmpty else {
            print("[ImportBrowser] flushPendingUploads: no pending keys, returning early")
            return
        }

        print("[ImportBrowser] flushPendingUploads: flushing \(localKeys.count) clip(s): \(localKeys)")

        do {
            print("[ImportBrowser] flushPendingUploads: ensuring remote session…")
            let remoteSession = try await ensureRemoteSession()
            print("[ImportBrowser] flushPendingUploads: remote session ready – projectID=\(remoteSession.projectID) sessionID=\(remoteSession.sessionID)")

            let selectedVideos = model.clips.compactMap { clip -> SelectedVideoAsset? in
                guard localKeys.contains(clip.localKey),
                      clip.isSelected,
                      clip.isCommitted,
                      let originalURL = clip.originalURL else { return nil }
                return SelectedVideoAsset(
                    localKey: clip.localKey,
                    assetLocalIdentifier: clip.assetLocalIdentifier,
                    localMediaID: clip.localMediaID,
                    originalURL: originalURL,
                    displayName: clip.displayName,
                    fileSize: clip.fileSize,
                    remoteClipID: clip.remoteClipID
                )
            }

            guard !selectedVideos.isEmpty else {
                print("[ImportBrowser] flushPendingUploads: no matching videos after filtering, returning")
                updateStatusAndReadiness()
                return
            }
            print("[ImportBrowser] flushPendingUploads: \(selectedVideos.count) video(s) matched for upload")

            for localKey in selectedVideos.map(\.localKey) {
                updateClip(localKey: localKey) { clip in
                    clip.uploadState = .running("Extracting audio")
                }
            }

            print("[ImportBrowser] flushPendingUploads: starting audio extraction…")
            let processedAssets = try await extractAudioBatch(from: selectedVideos)
            print("[ImportBrowser] flushPendingUploads: audio extraction complete – \(processedAssets.count) asset(s)")

            for localKey in processedAssets.map(\.localKey) {
                updateClip(localKey: localKey) { clip in
                    clip.uploadState = .running("Uploading to the agent")
                }
            }

            print("[ImportBrowser] flushPendingUploads: calling uploadBatch…")
            let response = try await projectClipProcessingService.uploadBatch(processedAssets, to: remoteSession)
            print("[ImportBrowser] flushPendingUploads: uploadBatch succeeded")
            cleanupProcessedAssets(processedAssets)
            applyServerResponse(response)
        } catch {
            print("[ImportBrowser] flushPendingUploads: ERROR – \(error)")
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
            print("[ImportBrowser] ensureRemoteSession: reusing existing session \(remoteSession.sessionID)")
            return remoteSession
        }

        print("[ImportBrowser] ensureRemoteSession: creating new session via \(AppConfiguration.agentSessionEndpoint)")
        let response = try await projectClipProcessingService.createRemoteSession(projectName: localProjectName())
        let remoteSession = RemoteImportSession(
            sessionID: response.sessionID.rawValue,
            sessionName: response.sessionName,
            projectID: response.projectID.rawValue,
            projectName: response.projectName
        )
        print("[ImportBrowser] ensureRemoteSession: created sessionID=\(remoteSession.sessionID) projectID=\(remoteSession.projectID)")
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

    private func ensureLocalMediaAvailable(for localKey: String) async throws {
        guard let clip = clip(for: localKey), clip.isSelected else { return }
        if clip.localMediaID != nil {
            print("[ImportBrowser] local media already available localKey=\(localKey) mediaID=\(clip.localMediaID ?? "nil")")
            updateClip(localKey: localKey) { clip in
                clip.embeddingState = .succeeded("Embeddings queued locally")
            }
            return
        }
        guard let originalURL = clip.originalURL else {
            throw makeLocalLibraryImportError("The selected clip could not be exported locally.")
        }
        guard let mediaLibraryID = try resolveMediaLibraryID() else {
            throw makeLocalLibraryImportError("Could not resolve the local media library.")
        }

        let imported = try await mediaImportService.importFileURLsQuick(
            [originalURL],
            to: mediaLibraryID,
            preferredKind: .video
        )
        guard let media = imported.first else {
            throw makeLocalLibraryImportError("The clip could not be added to the local library.")
        }

        updateClip(localKey: localKey) { clip in
            clip.localMediaID = media.mediaId
            clip.embeddingState = .succeeded("Embeddings queued locally")
        }
        print(
            "[ImportBrowser] local media imported localKey=\(localKey) mediaID=\(media.mediaId) assetRefID=\(media.assetRefId)"
        )
        await resyncSemanticIndexIfNeeded()
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
        let transcriptVideoCount = media
            .filter { $0.kind == .video && !($0.spec.transcriptSentences?.isEmpty ?? true) }
            .count
        print(
            "[ImportBrowser] semantic resync localLibraryID=\(mediaLibraryID) mediaCount=\(media.count) " +
            "videoTranscriptCount=\(transcriptVideoCount)"
        )
        semanticSearchViewModel.queueImportedMediaSync(media, autoBuildIndex: true)
    }

    private func makeTranscriptRequest(for localKey: String) throws -> (video: SelectedVideoAsset, mediaID: String)? {
        guard let clip = clip(for: localKey),
              clip.isSelected,
              let originalURL = clip.originalURL,
              let mediaID = clip.localMediaID else {
            print(
                "[ImportBrowser] transcript request unavailable localKey=\(localKey) " +
                "isSelected=\(clip(for: localKey)?.isSelected ?? false) mediaID=\(clip(for: localKey)?.localMediaID ?? "nil")"
            )
            return nil
        }

        if let media = try db.getMedia(mediaId: mediaID),
           let transcriptSentences = media.spec.transcriptSentences,
           !transcriptSentences.isEmpty {
            print(
                "[ImportBrowser] transcript request skipped existing transcript localKey=\(localKey) " +
                "mediaID=\(mediaID) sentences=\(transcriptSentences.count)"
            )
            return nil
        }

        let video = SelectedVideoAsset(
            localKey: clip.localKey,
            assetLocalIdentifier: clip.assetLocalIdentifier,
            localMediaID: clip.localMediaID,
            originalURL: originalURL,
            displayName: clip.displayName,
            fileSize: clip.fileSize,
            remoteClipID: clip.remoteClipID
        )
        print(
            "[ImportBrowser] transcript request prepared localKey=\(localKey) mediaID=\(mediaID) " +
            "file=\(video.displayName) originalURL=\(video.originalURL.lastPathComponent)"
        )
        return (video, mediaID)
    }

    private func persistTranscript(_ transcript: ClipTranscriptResponse, forMediaID mediaID: String) throws {
        guard var media = try db.getMedia(mediaId: mediaID) else {
            print("[ImportBrowser] transcript persist skipped missing media mediaID=\(mediaID)")
            return
        }
        media.spec.transcriptID = transcript.transcriptID
        media.spec.transcriptFullText = transcript.fullText
        media.spec.transcriptSentences = transcript.sentences.map {
            MediaTranscriptSentence(
                text: $0.text,
                startTimeSeconds: $0.start,
                endTimeSeconds: $0.end,
                confidence: $0.confidence,
                speaker: $0.speaker,
                channel: $0.channel
            )
        }
        if media.spec.duration == nil, let audioDuration = transcript.audioDuration {
            media.spec.duration = audioDuration
        }
        media.updatedAt = Date()
        try db.update(media)
        print(
            "[ImportBrowser] transcript saved mediaID=\(mediaID) transcriptID=\(transcript.transcriptID) " +
            "sentences=\(media.spec.transcriptSentences?.count ?? 0) fullTextChars=\(transcript.fullText.count)"
        )
    }

    private func localProjectName() -> String? {
        guard let timelineId,
              let timeline = try? db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id"),
              let project = try? db.get(Project.self, id: timeline.projectId, keyColumn: "project_id") else {
            return nil
        }
        return project.name
    }

    private func cachedOrPlaceholderDisplayName(for assetLocalIdentifier: String) -> String {
        filenameCache[assetLocalIdentifier] ?? "Clip"
    }

    private func loadOriginalFilenameIfNeeded(for assetLocalIdentifier: String) {
        guard filenameCache[assetLocalIdentifier] == nil else { return }
        guard filenameTasks[assetLocalIdentifier] == nil else { return }

        filenameTasks[assetLocalIdentifier] = Task { [weak self] in
            guard let self else { return }
            let filename = await mediaImportService.requestOriginalFilename(for: assetLocalIdentifier)
            guard !Task.isCancelled else { return }

            filenameTasks[assetLocalIdentifier] = nil

            guard let filename, !filename.isEmpty else { return }
            filenameCache[assetLocalIdentifier] = filename

            for index in model.clips.indices where model.clips[index].assetLocalIdentifier == assetLocalIdentifier {
                model.clips[index].displayName = filename
            }
        }
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

    private func makeLocalLibraryImportError(_ message: String) -> NSError {
        NSError(
            domain: "ImportBrowserViewModel",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
