internal import Combine
import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var model = ImportModel()
    let endpoint: URL

    private let audioExtractionService: AudioExtractionService
    private let uploadService: IngestUploadService
    private let db: DatabaseManager

    init(
        endpoint: URL? = nil,
        audioExtractionService: AudioExtractionService? = nil,
        uploadService: IngestUploadService? = nil,
        db: DatabaseManager? = nil
    ) {
        self.endpoint = endpoint ?? AppConfiguration.ingestEndpoint
        self.audioExtractionService = audioExtractionService ?? AudioExtractionService()
        self.uploadService = uploadService ?? IngestUploadService()
        self.db = db ?? DatabaseManager.shared
    }

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedVideo]) {
        guard !importedVideos.isEmpty else {
            model.videos = []
            model.isImportingVideos = false
            model.importErrorMessage = nil
            model.uploadStatusMessage = "Import videos, add a prompt, then start editing to compress the audio and upload it."
            return
        }

        do {
            model.videos = try importedVideos.map(makeSelectedVideo(from:))
            model.importErrorMessage = nil
            model.uploadStatusMessage = "\(model.videos.count) video\(model.videos.count == 1 ? "" : "s") ready for compression and upload."
        } catch {
            model.videos = []
            model.importErrorMessage = error.localizedDescription
        }

        model.isImportingVideos = false
    }

    func completeVideoImport(with error: Error) {
        model.videos = []
        model.isImportingVideos = false
        model.importErrorMessage = error.localizedDescription
    }

    func removeVideo(id: SelectedVideoAsset.ID) {
        model.videos.removeAll { $0.id == id }
        model.uploadStatusMessage = model.videos.isEmpty
            ? "Import videos, add a prompt, then start editing to compress the audio and upload it."
            : "\(model.videos.count) video\(model.videos.count == 1 ? "" : "s") ready for compression and upload."
    }

    func updatePromptMessage(_ text: String) {
        model.prompt.text = text
        model.prompt.validationMessage = validatePromptMessage(text)
    }

    func applyPromptSuggestion(_ suggestion: String) {
        updatePromptMessage(suggestion)
    }

    func clearPromptMessage() {
        updatePromptMessage("")
    }

    func beginProcessing() {
        guard !model.videos.isEmpty else {
            model.uploadStatusMessage = "Select at least one video before starting."
            return
        }

        let trimmedPrompt = model.prompt.trimmedText
        guard !trimmedPrompt.isEmpty, model.prompt.validationMessage == nil else {
            model.uploadStatusMessage = model.prompt.validationMessage ?? "Add an editing prompt before starting."
            return
        }

        model.screen = .processing
        model.hasStartedUpload = false
        model.uploadDidComplete = false
        model.uploadStatusMessage = "Processing clips, please wait."
    }

    func showAgentView() {
        guard model.uploadDidComplete else { return }
        model.screen = .agent
    }

    func resolveEditorTimelineID(preferredTimelineID: String?) -> String? {
        if let preferredTimelineID {
            return preferredTimelineID
        }

        let project = Project(name: "AI Assembly")

        do {
            try db.create(project)
            let library = MediaLibrary(projectId: project.projectId)
            try db.create(library)
            let timeline = try db.createTimeline(forProjectId: project.projectId)
            return timeline.timelineId
        } catch {
            model.uploadStatusMessage = "Couldn't create a timeline for the assembled edit."
            return nil
        }
    }

    func startProcessingIfNeeded() async {
        guard model.screen == .processing, !model.hasStartedUpload else { return }

        model.hasStartedUpload = true
        model.isUploading = true
        model.uploadDidComplete = false
        model.lastUploadedCount = 0
        model.serverResponse = ""
        model.parsedResponse = nil
        model.processingDuration = nil
        model.audioExtractionDuration = nil
        model.serverProcessingDuration = nil
        for index in model.videos.indices {
            model.videos[index].remoteClipID = nil
        }
        model.uploadStatusMessage = "Processing clips, please wait."
        let requestStart = ContinuousClock.now

        if AppConfiguration.simulateImportProcessing {
            await runSimulatedProcessing(startedAt: requestStart)
            model.isUploading = false
            return
        }

        var processedAssets: [ProcessedAudioAsset] = []

        do {
            let extractionStart = ContinuousClock.now

            for video in model.videos {
                model.uploadStatusMessage = "Compressing audio from \(video.displayName)..."
                let processed = try await audioExtractionService.extractCompressedAudio(from: video)
                processedAssets.append(processed)
            }

            let extractionElapsed = extractionStart.duration(to: ContinuousClock.now)
            model.audioExtractionDuration = extractionElapsed.timeInterval

            model.uploadStatusMessage = "Uploading \(processedAssets.count) compressed audio file\(processedAssets.count == 1 ? "" : "s")..."
            let uploadStart = ContinuousClock.now
            let uploadResponse = try await uploadService.upload(processedAssets, to: endpoint)
            let uploadElapsed = uploadStart.duration(to: ContinuousClock.now)
            let elapsed = requestStart.duration(to: ContinuousClock.now)
            let responseBody = uploadResponse.rawBody
            print("[IngestUpload] Raw response body:\n\(responseBody.isEmpty ? "(empty response body)" : responseBody)")
            let parsedResponse = decodeResponse(from: responseBody)
            if let parsedResponse {
                storeUploadedClipReferences(from: parsedResponse)
            }

            model.lastUploadedCount = processedAssets.count
            model.processingDuration = elapsed.timeInterval
            model.serverProcessingDuration = uploadElapsed.timeInterval
            model.parsedResponse = parsedResponse
            model.serverResponse = responseBody.isEmpty ? "(empty response body)" : responseBody
            model.uploadDidComplete = parsedResponse != nil
            model.uploadStatusMessage = uploadCompletionMessage(
                uploadedCount: processedAssets.count,
                response: parsedResponse
            )
        } catch {
            model.uploadStatusMessage = error.localizedDescription
            model.uploadDidComplete = false
        }

        cleanupProcessedAssets(processedAssets)
        model.isUploading = false
    }

    private func runSimulatedProcessing(startedAt requestStart: ContinuousClock.Instant) async {
        try? await Task.sleep(nanoseconds: 1_000_000_000)

        let elapsed = requestStart.duration(to: ContinuousClock.now)
        model.lastUploadedCount = model.videos.count
        model.processingDuration = elapsed.timeInterval
        model.audioExtractionDuration = elapsed.timeInterval
        model.serverProcessingDuration = elapsed.timeInterval
        model.serverResponse = "(simulated processing)"
        model.parsedResponse = nil
        model.uploadDidComplete = true
        model.uploadStatusMessage = "Processing complete"
    }

    private func makeSelectedVideo(from importedVideo: ImportedVideo) throws -> SelectedVideoAsset {
        let fileValues = try importedVideo.localURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(fileValues.fileSize ?? 0)

        return SelectedVideoAsset(
            localKey: importedVideo.localKey,
            originalURL: importedVideo.localURL,
            displayName: importedVideo.displayName,
            fileSize: size > 0 ? size : nil,
            remoteClipID: nil
        )
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

    private func cleanupProcessedAssets(_ assets: [ProcessedAudioAsset]) {
        for asset in assets {
            try? FileManager.default.removeItem(at: asset.audioURL)
        }
    }

    private func decodeResponse(from rawBody: String) -> IngestResponse? {
        guard let data = rawBody.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(IngestResponse.self, from: data)
    }

    private func storeUploadedClipReferences(from response: IngestResponse) {
        let clipIDsByLocalKey = response.videos.reduce(into: [String: String]()) { result, video in
            guard let localKey = video.localKey, !localKey.isEmpty else { return }
            result[localKey] = video.clipID.rawValue
        }

        for index in model.videos.indices {
            model.videos[index].remoteClipID = clipIDsByLocalKey[model.videos[index].localKey]
        }
    }

    private func uploadCompletionMessage(uploadedCount: Int, response: IngestResponse?) -> String {
        if response != nil {
            return "Processing complete"
        }

        return uploadedCount == 1
            ? "Upload finished, but the server response did not include the session data needed to open the agent view."
            : "Uploads finished, but the server response did not include the session data needed to open the agent view."
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
