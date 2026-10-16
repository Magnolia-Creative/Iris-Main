internal import Combine
import Foundation
import OSLog
import Photos

extension ImportBrowserViewModel {
    private static let transcriptPersistenceLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "TranscriptPersistence"
    )

    private static let backendMappingLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "ImportBrowser.BackendMapping"
    )

    /// Persists `projects.backend_project_id` for the timeline’s local project when `timelineId` is known.
    private func persistBackendProjectMappingForTimelineIfPossible(
        backendProjectId: String,
        backendProjectName: String?,
        context: String
    ) {
        guard let timelineId else {
            Self.backendMappingLog.warning(
                "[ImportBrowser] skip backend mapping (no timelineId) context=\(context, privacy: .public) backendProjectId=\(backendProjectId, privacy: .public)"
            )
            return
        }
        guard let timeline = try? db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id") else {
            Self.backendMappingLog.error(
                "[ImportBrowser] skip backend mapping (timeline not found) context=\(context, privacy: .public) timelineId=\(timelineId, privacy: .public)"
            )
            return
        }
        do {
            try db.saveBackendProjectMapping(
                localProjectId: timeline.projectId,
                backendProjectId: backendProjectId,
                backendProjectName: backendProjectName
            )
            Self.backendMappingLog.notice(
                "[ImportBrowser] saved backend mapping context=\(context, privacy: .public) localProjectId=\(timeline.projectId, privacy: .public) backendProjectId=\(backendProjectId, privacy: .public)"
            )
        } catch {
            Self.backendMappingLog.error(
                "[ImportBrowser] saveBackendProjectMapping failed context=\(context, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

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

        print("[ImportBrowser] commitClip: exporting localKey=\(localKey)")
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

            enqueueClipForUpload(localKey: localKey)
        } catch {
            print("[ImportBrowser] commitClip: export FAILED – \(error)")
            model.clips[index].transcriptState = .failed(error.localizedDescription)
            model.clips[index].uploadState = .failed(error.localizedDescription)
            model.clips[index].commitmentStatus = "Export failed"
        }

        updateStatusAndReadiness()
    }

    func enqueueClipForUpload(localKey: String) {
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

        var visualFramesByLocalKey: [String: [VisualFrameUploadChunk]] = [:]
        do {
            print("[ImportBrowser] flushPendingUploads: ensuring remote backend project…")
            let remoteProject = try await ensureRemoteBackendProject()
            print("[ImportBrowser] flushPendingUploads: remote project ready – projectID=\(remoteProject.projectID)")

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
                    clip.uploadState = .running("Sampling visual frames")
                }
            }

            visualFramesByLocalKey = await sampleVisualUploadFrames(for: selectedVideos)

            for localKey in processedAssets.map(\.localKey) {
                updateClip(localKey: localKey) { clip in
                    clip.uploadState = .running("Uploading to the agent")
                }
            }

            print("[ImportBrowser] flushPendingUploads: calling uploadBatch…")
            let response = try await projectClipProcessingService.uploadBatch(
                processedAssets,
                visualFramesByLocalKey: visualFramesByLocalKey,
                backendProjectID: remoteProject.projectID
            )
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

        cleanupVisualUploadFrames(visualFramesByLocalKey)

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

        if let projectID = response.projectID?.rawValue {
            let projectName = response.projectName
                ?? model.remoteBackendProject?.projectName
                ?? localProjectName()
                ?? "Iris Project"
            model.remoteBackendProject = RemoteBackendProject(
                projectID: projectID,
                projectName: projectName
            )
            persistBackendProjectMappingForTimelineIfPossible(
                backendProjectId: projectID,
                backendProjectName: projectName,
                context: "applyServerResponse"
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
            persistRemoteTranscriptIDIfAvailable(
                responseVideo.transcriptID?.rawValue,
                localKey: localKey,
                mediaID: model.clips[index].localMediaID
            )

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

    private func persistRemoteTranscriptIDIfAvailable(
        _ transcriptID: String?,
        localKey: String,
        mediaID: String?
    ) {
        let trimmedTranscriptID = transcriptID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedTranscriptID.isEmpty else { return }
        guard let mediaID else {
            Self.transcriptPersistenceLog.warning(
                "remote transcript id sync skipped: no local media localKey=\(localKey, privacy: .public) transcriptID=\(trimmedTranscriptID, privacy: .public)"
            )
            return
        }

        do {
            let updated = try db.updateMediaSpec(mediaId: mediaID) { spec in
                let existing = spec.transcriptID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existing.isEmpty {
                    spec.transcriptID = trimmedTranscriptID
                }
                let existingKey = spec.clipUploadLocalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existingKey.isEmpty {
                    spec.clipUploadLocalKey = localKey
                }
            }
            if let updated {
                NotificationCenter.default.post(
                    name: .irisMediaTranscriptDidPersist,
                    object: nil,
                    userInfo: ["mediaId": mediaID]
                )
                Self.transcriptPersistenceLog.notice(
                    "remote transcript id synced localKey=\(localKey, privacy: .public) mediaID=\(mediaID, privacy: .public) transcriptID=\(updated.spec.transcriptID ?? "nil", privacy: .public) sentences=\(updated.spec.transcriptSentences?.count ?? 0, privacy: .public)"
                )
            } else {
                Self.transcriptPersistenceLog.error(
                    "remote transcript id sync failed: media missing localKey=\(localKey, privacy: .public) mediaID=\(mediaID, privacy: .public) transcriptID=\(trimmedTranscriptID, privacy: .public)"
                )
            }
        } catch {
            Self.transcriptPersistenceLog.error(
                "remote transcript id sync failed localKey=\(localKey, privacy: .public) mediaID=\(mediaID, privacy: .public) transcriptID=\(trimmedTranscriptID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }

    func startRemoteStatusPollingIfNeeded() {
        guard let backendProject = model.remoteBackendProject else { return }
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
                    let response = try await projectClipProcessingService.fetchProjectClipStatus(
                        projectID: backendProject.projectID
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

    func ensureRemoteBackendProject() async throws -> RemoteBackendProject {
        if let existing = model.remoteBackendProject {
            print("[ImportBrowser] ensureRemoteBackendProject: reusing project \(existing.projectID)")
            return existing
        }

        if let timelineId,
           let timeline = try? db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id"),
           let project = try? db.get(Project.self, id: timeline.projectId, keyColumn: "project_id"),
           let bid = project.backendProjectId,
           !bid.isEmpty {
            let ctx = RemoteBackendProject(
                projectID: bid,
                projectName: project.backendProjectName ?? project.name
            )
            print("[ImportBrowser] ensureRemoteBackendProject: loaded from local DB projectID=\(ctx.projectID)")
            model.remoteBackendProject = ctx
            return ctx
        }

        let display = localProjectName() ?? "Iris Project"
        print("[ImportBrowser] ensureRemoteBackendProject: creating via \(AppConfiguration.projectsCreateEndpoint)")
        let created = try await projectClipProcessingService.createRemoteProject(displayName: display)
        let ctx = RemoteBackendProject(
            projectID: created.projectID.rawValue,
            projectName: created.projectName
        )
        model.remoteBackendProject = ctx
        persistBackendProjectMappingForTimelineIfPossible(
            backendProjectId: ctx.projectID,
            backendProjectName: ctx.projectName,
            context: "ensureRemoteBackendProject-created"
        )
        print("[ImportBrowser] ensureRemoteBackendProject: created projectID=\(ctx.projectID)")
        return ctx
    }

    /// Creates a backend agent session for WebSocket routing; call only when ingest is ready for AutoMake.
    func prepareAgentWebSocketSessionIfNeeded() async throws {
        let ctx = try await ensureRemoteBackendProject()
        guard model.agentWebSocketSessionID == nil else { return }
        let agent = try await projectClipProcessingService.createAgentSession(
            projectID: ctx.projectID,
            sessionName: localProjectName()
        )
        model.agentWebSocketSessionID = agent.sessionID.rawValue
        print("[ImportBrowser] prepareAgentWebSocketSessionIfNeeded: sessionID=\(agent.sessionID.rawValue)")
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
        if let existingMediaID = clip.localMediaID {
            print("[ImportBrowser] local media already available localKey=\(localKey) mediaID=\(existingMediaID)")
            do {
                if let media = try db.getMedia(mediaId: existingMediaID) {
                    let trimmedKey = localKey.trimmingCharacters(in: .whitespacesAndNewlines)
                    let existingUpload = media.spec.clipUploadLocalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !trimmedKey.isEmpty, existingUpload.caseInsensitiveCompare(trimmedKey) != .orderedSame {
                        _ = try db.updateMediaSpec(mediaId: existingMediaID) { spec in
                            spec.clipUploadLocalKey = trimmedKey
                        }
                        print(
                            "[ImportBrowser] backfilled clipUploadLocalKey for existing media mediaID=\(existingMediaID) localKey=\(trimmedKey)"
                        )
                    }
                } else {
                    Self.transcriptPersistenceLog.warning(
                        "clipUploadLocalKey backfill skipped missing media mediaID=\(existingMediaID, privacy: .public) localKey=\(localKey, privacy: .public)"
                    )
                }
            } catch {
                Self.transcriptPersistenceLog.error(
                    "clipUploadLocalKey backfill failed mediaID=\(existingMediaID, privacy: .public) localKey=\(localKey, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                throw error
            }
            return existingMediaID
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
            let trimmedKey = localKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else {
                throw makeLocalLibraryImportError("The selected clip is missing its upload key.")
            }
            guard let mediaWithUploadKey = try self.db.updateMediaSpec(
                mediaId: media.mediaId,
                mutate: { spec in
                    spec.clipUploadLocalKey = trimmedKey
                }
            ) else {
                throw makeLocalLibraryImportError("The imported clip could not be saved locally.")
            }
            await MainActor.run {
                self.updateClip(localKey: localKey) { clip in
                    clip.localMediaID = mediaWithUploadKey.mediaId
                }
            }
            print(
                "[ImportBrowser] local media imported localKey=\(localKey) mediaID=\(mediaWithUploadKey.mediaId) assetRefID=\(mediaWithUploadKey.assetRefId)"
            )
            return mediaWithUploadKey.mediaId
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
            ($0.isSelected && $0.isCommitted && $0.uploadState.isRunning)
        } || !pendingUploadKeys.isEmpty || uploadFlushTask != nil

        if hasFailures {
            model.statusMessage = "Fix or remove the failed clips before starting the live session."
        } else if hasRunningWork {
            model.statusMessage = "Preparing \(committedCount) clip\(committedCount == 1 ? "" : "s") for Iris."
        } else if committedCount > 0,
                  model.ingestResponse?.readyForWebSocket != true {
            model.statusMessage = "Waiting for server transcripts before starting Iris."
        } else if committedCount > 0 {
            model.statusMessage = "\(committedCount) clip\(committedCount == 1 ? "" : "s") ready for Iris."
        } else if selectedCount > 0 {
            model.statusMessage = "Keep a clip selected for 2 seconds to begin processing."
        } else {
            model.statusMessage = "Select clips to start preparing them for Iris."
        }

        let remoteReady = model.ingestResponse?.readyForWebSocket ?? false
        let uploadReady = model.clips
            .filter { $0.isSelected && $0.isCommitted }
            .allSatisfy(\.uploadState.isSucceeded)
        let canTransitionToAgent = model.isAwaitingAgentStart
            && model.prompt.isReady
            && !hasFailures
            && !hasRunningWork
            && committedCount > 0
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

    func sampleVisualUploadFrames(for videos: [SelectedVideoAsset]) async -> [String: [VisualFrameUploadChunk]] {
        await withTaskGroup(of: (String, [VisualFrameUploadChunk]).self) { group in
            for video in videos {
                group.addTask {
                    let url = video.originalURL
                    let key = video.localKey
                    do {
                        let frames = try await SemanticUploadFrameSampling.buildJPEGFramesForUpload(
                            videoURL: url,
                            localKey: key
                        )
                        return (key, frames)
                    } catch {
                        print("[ImportBrowser] sampleVisualUploadFrames failed localKey=\(key): \(error)")
                        return (key, [])
                    }
                }
            }
            var result: [String: [VisualFrameUploadChunk]] = [:]
            for await (localKey, frames) in group {
                result[localKey] = frames
            }
            return result
        }
    }

    func cleanupVisualUploadFrames(_ framesByLocalKey: [String: [VisualFrameUploadChunk]]) {
        for chunks in framesByLocalKey.values {
            for chunk in chunks {
                try? FileManager.default.removeItem(at: chunk.fileURL)
            }
        }
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
