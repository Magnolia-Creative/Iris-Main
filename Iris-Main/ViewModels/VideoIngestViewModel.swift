import Combine
import Foundation

@MainActor
final class VideoIngestViewModel: ObservableObject {
    @Published private(set) var selectedVideos: [SelectedVideoAsset] = []
    @Published private(set) var isLoadingSelection = false
    @Published private(set) var isUploading = false
    @Published private(set) var statusMessage = "Choose videos from the camera roll. The app will extract speech-friendly compressed audio and upload that audio under the `videos` form field."
    @Published private(set) var serverResponse = ""
    @Published private(set) var parsedResponse: IngestResponse?
    @Published private(set) var processingDuration: TimeInterval?
    @Published private(set) var audioExtractionDuration: TimeInterval?
    @Published private(set) var serverProcessingDuration: TimeInterval?
    @Published private(set) var lastUploadedCount = 0

    let endpoint: URL

    private let audioExtractionService: AudioExtractionService
    private let uploadService: IngestUploadService

    init(
        endpoint: URL? = nil,
        audioExtractionService: AudioExtractionService? = nil,
        uploadService: IngestUploadService? = nil
    ) {
        self.endpoint = endpoint ?? AppConfiguration.ingestEndpoint
        self.audioExtractionService = audioExtractionService ?? AudioExtractionService()
        self.uploadService = uploadService ?? IngestUploadService()
    }

    func beginSelectionImport() {
        isLoadingSelection = true
    }

    func importSelection(from importedVideos: [ImportedVideo]) {
        guard !importedVideos.isEmpty else {
            selectedVideos = []
            isLoadingSelection = false
            statusMessage = "No videos selected yet."
            return
        }

        var selectedAssets: [SelectedVideoAsset] = []

        for importedVideo in importedVideos {
            selectedAssets.append(makeSelectedVideo(from: importedVideo))
        }

        selectedVideos = selectedAssets
        statusMessage = "\(selectedAssets.count) video\(selectedAssets.count == 1 ? "" : "s") ready. Upload sends compressed audio only."
        isLoadingSelection = false
    }

    func completeSelectionImport(with error: Error) {
        selectedVideos = []
        isLoadingSelection = false
        statusMessage = error.localizedDescription
    }

    func uploadSelection() async {
        guard !selectedVideos.isEmpty else {
            statusMessage = "Select at least one video before uploading."
            return
        }

        isUploading = true
        lastUploadedCount = 0
        serverResponse = ""
        parsedResponse = nil
        processingDuration = nil
        audioExtractionDuration = nil
        serverProcessingDuration = nil
        statusMessage = "Extracting audio and preparing upload..."
        let requestStart = ContinuousClock.now

        var processedAssets: [ProcessedAudioAsset] = []

        do {
            let extractionStart = ContinuousClock.now
            for video in selectedVideos {
                statusMessage = "Compressing audio from \(video.displayName)..."
                let processed = try await audioExtractionService.extractCompressedAudio(from: video)
                processedAssets.append(processed)
            }
            let extractionElapsed = extractionStart.duration(to: ContinuousClock.now)
            audioExtractionDuration = extractionElapsed.timeInterval

            statusMessage = "Uploading \(processedAssets.count) compressed audio file\(processedAssets.count == 1 ? "" : "s")..."
            let uploadStart = ContinuousClock.now
            let uploadResponse = try await uploadService.upload(processedAssets, to: endpoint)
            let uploadElapsed = uploadStart.duration(to: ContinuousClock.now)
            let elapsed = requestStart.duration(to: ContinuousClock.now)
            let responseBody = uploadResponse.rawBody
            lastUploadedCount = processedAssets.count
            processingDuration = elapsed.timeInterval
            serverProcessingDuration = uploadElapsed.timeInterval
            parsedResponse = decodeResponse(from: responseBody)
            statusMessage = "Upload complete. Sent \(processedAssets.count) compressed audio file\(processedAssets.count == 1 ? "" : "s") to \(endpoint.absoluteString) in \(formattedDuration(elapsed.timeInterval))."
            serverResponse = responseBody.isEmpty ? "(empty response body)" : responseBody
            print("Ingest response:\n\(serverResponse)")
        } catch {
            statusMessage = error.localizedDescription
        }

        cleanupProcessedAssets(processedAssets)
        isUploading = false
    }

    func removeVideo(id: SelectedVideoAsset.ID) {
        selectedVideos.removeAll { $0.id == id }
        statusMessage = selectedVideos.isEmpty
            ? "No videos selected yet."
            : "\(selectedVideos.count) video\(selectedVideos.count == 1 ? "" : "s") ready. Upload sends compressed audio only."
    }

    private func makeSelectedVideo(from importedVideo: ImportedVideo) -> SelectedVideoAsset {
        let fileValues = try? importedVideo.localURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(fileValues?.fileSize ?? 0)

        return SelectedVideoAsset(
            originalURL: importedVideo.localURL,
            displayName: importedVideo.displayName,
            fileSize: size > 0 ? size : nil
        )
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

    private func formattedDuration(_ duration: TimeInterval) -> String {
        String(format: "%.2fs", duration)
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        TimeInterval(components.seconds) + (TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000)
    }
}
