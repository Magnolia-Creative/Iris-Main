internal import Combine
import Foundation
import OSLog
import Photos

extension ImportBrowserViewModel {
    private static let transcriptPersistenceLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "TranscriptPersistence"
    )

    func reloadAlbums() {
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

    func reloadAssets() {
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

    func scheduleCommitment(for localKey: String) {
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

    func commitClip(localKey: String) async {
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

            if model.processingMode.runsEmbeddings {
                startEmbeddingIfNeeded(for: localKey)
                startTranscriptionIfNeeded(for: localKey)
            }
            if model.processingMode.runsAgentPreprocessing {
                enqueueClipForUpload(localKey: localKey)
            } else {
                print("[ImportBrowser] commitClip: skipping upload – processingMode=\(model.processingMode)")
            }
        } catch {
            print("[ImportBrowser] commitClip: export FAILED – \(error)")
            model.clips[index].embeddingState = .failed(error.localizedDescription)
            model.clips[index].transcriptState = .failed(error.localizedDescription)
            model.clips[index].uploadState = .failed(error.localizedDescription)
            model.clips[index].commitmentStatus = "Export failed"
        }

        updateStatusAndReadiness()
    }

    func startEmbeddingIfNeeded(for localKey: String) {
        guard model.processingMode.runsEmbeddings else { return }
        guard let clipIndex = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else { return }
        guard model.clips[clipIndex].embeddingState.isSucceeded == false else { return }
        guard model.clips[clipIndex].originalURL != nil else { return }

        model.clips[clipIndex].embeddingState = .running("Preparing local embeddings")

        embeddingTasks[localKey]?.cancel()
        embeddingTasks[localKey] = Task { [weak self] in
            guard let self else { return }
            do {
                let mediaID = try await self.ensureLocalMediaAvailable(for: localKey)
                let indexedVideoIDs = await self.resyncSemanticIndexIfNeeded(autoBuildIndex: true)
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.embeddingState = indexedVideoIDs.contains(mediaID)
                            ? .succeeded("Embeddings ready")
                            : .failed("The clip was imported locally but did not finish indexing.")
                    }
                }
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

    func startTranscriptionIfNeeded(for localKey: String) {
        guard model.processingMode.runsEmbeddings else { return }
        guard let clipIndex = model.clips.firstIndex(where: { $0.localKey == localKey && $0.isSelected }) else { return }
        guard model.clips[clipIndex].originalURL != nil else { return }
        guard model.clips[clipIndex].transcriptState.isSucceeded == false else { return }
        model.clips[clipIndex].transcriptState = .running("Preparing local transcript")
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
                _ = try await self.ensureLocalMediaAvailable(for: localKey)
                guard let request = try self.makeTranscriptRequest(for: localKey) else {
                    print("[ImportBrowser] transcript task skipped localKey=\(localKey)")
                    await MainActor.run {
                        self.updateClip(localKey: localKey) { clip in
                            clip.transcriptState = .succeeded("Transcript ready")
                        }
                    }
                    return
                }
                let audioExtractionService = self.audioExtractionService
                let clipTranscriptService = self.clipTranscriptService
                print(
                    "[ImportBrowser] transcript task started localKey=\(localKey) mediaID=\(request.mediaID) " +
                    "file=\(request.video.displayName)"
                )
                let (processedAsset, transcript) = try await Task.detached(priority: .utility) {
                    let processedAsset = try await audioExtractionService.extractCompressedAudio(from: request.video)
                    print(
                        "[ImportBrowser] transcript audio extracted localKey=\(localKey) audioURL=\(processedAsset.audioURL.lastPathComponent)"
                    )
                    let transcript = try await clipTranscriptService.transcribe(processedAsset)
                    return (processedAsset, transcript)
                }.value
                defer {
                    self.cleanupProcessedAssets([processedAsset])
                }
                print(
                    "[ImportBrowser] transcript response ready localKey=\(localKey) transcriptID=\(transcript.transcriptID) " +
                    "sentences=\(transcript.sentences.count)"
                )
                if transcript.transcriptID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Self.transcriptPersistenceLog.warning(
                        "transcript response had empty transcript_id localKey=\(localKey, privacy: .public) mediaID=\(request.mediaID, privacy: .public)"
                    )
                }
                try self.persistTranscript(transcript, forMediaID: request.mediaID)
                print("[ImportBrowser] transcript persisted localKey=\(localKey) mediaID=\(request.mediaID)")
                _ = await self.resyncSemanticIndexIfNeeded(autoBuildIndex: false)
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.transcriptState = .succeeded("Transcript ready")
                    }
                }
                print("[ImportBrowser] transcript resync queued localKey=\(localKey)")
            } catch is CancellationError {
                print("[ImportBrowser] transcript task cancelled localKey=\(localKey)")
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.transcriptState = .cancelled
                    }
                }
                return
            } catch {
                print("[ImportBrowser] transcript request failed localKey=\(localKey): \(error)")
                await MainActor.run {
                    self.updateClip(localKey: localKey) { clip in
                        clip.transcriptState = .failed(error.localizedDescription)
                    }
                }
            }
        }
    }

    func enqueueClipForUpload(localKey: String) {
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

    func scheduleUploadFlushIfNeeded() {
        guard uploadFlushTask == nil else { return }
        uploadFlushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.flushPendingUploads()
        }
    }

    func flushPendingUploads() async {
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

    func extractAudioBatch(from videos: [SelectedVideoAsset]) async throws -> [ProcessedAudioAsset] {
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
            return orderedProcessedAssetsForUpload(processedAssets, matching: videos)
        }
    }

    func applyServerResponse(_ response: IngestResponse) {
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

        applyRemoteVideoStatuses(responseByLocalKey)
        startRemoteStatusPollingIfNeeded()
    }

    func applyRemoteVideoStatuses(_ responseByLocalKey: [String: IngestVideoResponse]) {
        for index in model.clips.indices {
            let localKey = model.clips[index].localKey
            guard let responseVideo = responseByLocalKey[localKey] else { continue }
            model.clips[index].remoteClipID = responseVideo.clipID.rawValue

            switch responseVideo.processingStatus {
            case "ready":
                model.clips[index].uploadState = .succeeded("Uploaded to server")
            case "failed":
                model.clips[index].uploadState = .failed(responseVideo.processingError ?? "Clip preprocessing failed.")
            case "cancelled":
                model.clips[index].uploadState = .cancelled
            case "processing", "created":
                model.clips[index].uploadState = .succeeded("Uploaded to server")
            default:
                model.clips[index].uploadState = .queued("Waiting for server registration")
            }
        }
    }

    func startRemoteStatusPollingIfNeeded() {
        guard model.processingMode.runsAgentPreprocessing else { return }
        guard let remoteSession = model.remoteSession else { return }
        guard let ingestResponse = model.ingestResponse else { return }
        guard ingestResponse.pendingClipCount ?? 0 > 0 || ingestResponse.readyForWebSocket != true else {
            sessionStatusPollTask?.cancel()
            sessionStatusPollTask = nil
            return
        }
        guard sessionStatusPollTask == nil else { return }

        sessionStatusPollTask = Task { [weak self] in
            guard let self else { return }
            defer {
                Task { @MainActor [weak self] in
                    self?.sessionStatusPollTask = nil
                }
            }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                    let response = try await projectClipProcessingService.fetchSessionStatus(
                        sessionID: remoteSession.sessionID
                    )
                    await MainActor.run {
                        self.model.ingestResponse = response
                        let responseByLocalKey: [String: IngestVideoResponse] = Dictionary(
                            uniqueKeysWithValues: response.videos.compactMap { video in
                                guard let localKey = video.localKey else { return nil }
                                return (localKey, video)
                            }
                        )
                        self.applyRemoteVideoStatuses(responseByLocalKey)
                        self.updateStatusAndReadiness()
                    }
                    if (response.pendingClipCount ?? 0) == 0 {
                        return
                    }
                } catch is CancellationError {
                    return
                } catch {
                    print("[ImportBrowser] session status polling failed: \(error)")
                    return
                }
            }
        }
    }

    func ensureRemoteSession() async throws -> RemoteImportSession {
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

    func refreshVisibleAssetSelectionState() {
        for index in model.visibleAssets.indices {
            let assetID = model.visibleAssets[index].id
            let activeClip = model.clips.first { $0.assetLocalIdentifier == assetID && $0.isSelected }
            model.visibleAssets[index].isSelected = activeClip != nil
            model.visibleAssets[index].isCommitted = activeClip?.isCommitted ?? false
        }
    }

    func updateClip(localKey: String, mutate: (inout ImportClipProcessingItem) -> Void) {
        guard let index = model.clips.firstIndex(where: { $0.localKey == localKey }) else { return }
        mutate(&model.clips[index])
    }

    func ensureLocalMediaAvailable(for localKey: String) async throws -> String {
        guard let clip = clip(for: localKey), clip.isSelected else {
            throw CancellationError()
        }
        if clip.localMediaID != nil {
            print("[ImportBrowser] local media already available localKey=\(localKey) mediaID=\(clip.localMediaID ?? "nil")")
            if let localMediaID = clip.localMediaID {
                return localMediaID
            }
            throw makeLocalLibraryImportError("The clip is missing a local media identifier.")
        }
        if let task = localMediaTasks[localKey] {
            return try await task.value
        }
        guard let originalURL = clip.originalURL else {
            throw makeLocalLibraryImportError("The selected clip could not be exported locally.")
        }
        guard let mediaLibraryID = try resolveMediaLibraryID() else {
            throw makeLocalLibraryImportError("Could not resolve the local media library.")
        }

        let task = Task<String, Error> { [weak self] in
            guard let self else {
                throw NSError(
                    domain: "ImportBrowserViewModel",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "The clip could not be added to the local library."]
                )
            }
            let imported = try await mediaImportService.importFileURLsQuick(
                [originalURL],
                to: mediaLibraryID,
                preferredKind: .video
            )
            guard let media = imported.first else {
                throw makeLocalLibraryImportError("The clip could not be added to the local library.")
            }
            await MainActor.run {
                self.updateClip(localKey: localKey) { clip in
                    clip.localMediaID = media.mediaId
                }
            }
            print(
                "[ImportBrowser] local media imported localKey=\(localKey) mediaID=\(media.mediaId) assetRefID=\(media.assetRefId)"
            )
            return media.mediaId
        }
        localMediaTasks[localKey] = task
        defer {
            localMediaTasks[localKey] = nil
        }
        return try await task.value
    }

    func updateStatusAndReadiness() {
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
        } else if model.processingMode.runsAgentPreprocessing,
                  committedCount > 0,
                  model.ingestResponse?.readyForWebSocket != true {
            model.statusMessage = "Waiting for server transcripts before starting Iris."
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

    func validatePromptMessage(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return nil
        }

        if trimmedText.count < 8 {
            return "Add a little more detail so Iris knows how to shape the edit."
        }

        return nil
    }

    func resolveMediaLibraryID() throws -> String? {
        guard let timelineId else { return nil }
        guard let timeline = try db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id") else { return nil }
        return try db.getMediaLibrary(forProjectId: timeline.projectId)?.id
    }

    func resyncSemanticIndexIfNeeded(autoBuildIndex: Bool) async -> Set<String> {
        guard let mediaLibraryID = try? resolveMediaLibraryID() else { return [] }
        let media = (try? db.getAllMedia(forLibraryId: mediaLibraryID)) ?? []
        let transcriptVideoCount = media
            .filter { $0.kind == .video && !($0.spec.transcriptSentences?.isEmpty ?? true) }
            .count
        print(
            "[ImportBrowser] semantic resync localLibraryID=\(mediaLibraryID) mediaCount=\(media.count) " +
            "videoTranscriptCount=\(transcriptVideoCount)"
        )
        return await semanticSearchViewModel.syncImportedMediaAndWait(media, autoBuildIndex: autoBuildIndex)
    }

    func makeTranscriptRequest(for localKey: String) throws -> (video: SelectedVideoAsset, mediaID: String)? {
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
            Self.transcriptPersistenceLog.info(
                "makeTranscriptRequest skipped: already have sentences localKey=\(localKey, privacy: .public) mediaID=\(mediaID, privacy: .public) transcriptID=\(media.spec.transcriptID ?? "nil", privacy: .public) sentenceCount=\(transcriptSentences.count, privacy: .public)"
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

    func persistTranscript(_ transcript: ClipTranscriptResponse, forMediaID mediaID: String) throws {
        guard var media = try db.getMedia(mediaId: mediaID) else {
            print("[ImportBrowser] transcript persist skipped missing media mediaID=\(mediaID)")
            Self.transcriptPersistenceLog.error(
                "persistTranscript aborted: no media row for mediaID=\(mediaID, privacy: .public)"
            )
            return
        }
        let priorTranscriptID = media.spec.transcriptID
        let priorSentenceCount = media.spec.transcriptSentences?.count ?? 0
        Self.transcriptPersistenceLog.info(
            "persistTranscript applying mediaID=\(mediaID, privacy: .public) priorTranscriptID=\(priorTranscriptID ?? "nil", privacy: .public) incomingTranscriptID=\(transcript.transcriptID, privacy: .public) priorSentences=\(priorSentenceCount, privacy: .public) incomingSentences=\(transcript.sentences.count, privacy: .public)"
        )
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
        Self.transcriptPersistenceLog.info(
            "persistTranscript saved mediaID=\(mediaID, privacy: .public) storedTranscriptID=\(media.spec.transcriptID ?? "nil", privacy: .public) storedSentences=\(media.spec.transcriptSentences?.count ?? 0, privacy: .public) fullTextChars=\(media.spec.transcriptFullText?.count ?? 0, privacy: .public)"
        )
        print(
            "[ImportBrowser] transcript saved mediaID=\(mediaID) transcriptID=\(transcript.transcriptID) " +
            "sentences=\(media.spec.transcriptSentences?.count ?? 0) fullTextChars=\(transcript.fullText.count)"
        )
    }

    func localProjectName() -> String? {
        guard let timelineId,
              let timeline = try? db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id"),
              let project = try? db.get(Project.self, id: timeline.projectId, keyColumn: "project_id") else {
            return nil
        }
        return project.name
    }

    func cachedOrPlaceholderDisplayName(for assetLocalIdentifier: String) -> String {
        filenameCache[assetLocalIdentifier] ?? "Clip"
    }

    func loadOriginalFilenameIfNeeded(for assetLocalIdentifier: String) {
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

    func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(Int(duration.rounded()), 0)
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func cleanupProcessedAssets(_ assets: [ProcessedAudioAsset]) {
        for asset in assets {
            try? FileManager.default.removeItem(at: asset.audioURL)
        }
    }

    func makeLocalLibraryImportError(_ message: String) -> NSError {
        NSError(
            domain: "ImportBrowserViewModel",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
