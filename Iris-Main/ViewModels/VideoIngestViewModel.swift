import Combine
import Foundation

@MainActor
final class VideoIngestViewModel: ObservableObject {
    @Published private(set) var selectedVideos: [SelectedVideoAsset] = []
    @Published private(set) var isLoadingSelection = false
    @Published private(set) var isUploading = false
    @Published private(set) var statusMessage = "Choose videos from the camera roll. The app will extract speech-friendly compressed audio and upload that audio under the `videos` form field."
    @Published private(set) var serverResponse = ""
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

    func importSelection(from sourceURLs: [URL]) {
        guard !sourceURLs.isEmpty else {
            selectedVideos = []
            isLoadingSelection = false
            statusMessage = "No videos selected yet."
            return
        }

        do {
            var importedVideos: [SelectedVideoAsset] = []

            for sourceURL in sourceURLs {
                importedVideos.append(try copyVideo(from: sourceURL))
            }

            selectedVideos = importedVideos
            statusMessage = "\(importedVideos.count) video\(importedVideos.count == 1 ? "" : "s") ready. Upload sends compressed audio only."
        } catch {
            selectedVideos = []
            statusMessage = error.localizedDescription
        }

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
        statusMessage = "Extracting audio and preparing upload..."

        var processedAssets: [ProcessedAudioAsset] = []

        do {
            for video in selectedVideos {
                statusMessage = "Compressing audio from \(video.displayName)..."
                let processed = try await audioExtractionService.extractCompressedAudio(from: video)
                processedAssets.append(processed)
            }

            statusMessage = "Uploading \(processedAssets.count) compressed audio file\(processedAssets.count == 1 ? "" : "s")..."
            let responseBody = try await uploadService.upload(processedAssets, to: endpoint)
            lastUploadedCount = processedAssets.count
            statusMessage = "Upload complete. Sent \(processedAssets.count) compressed audio file\(processedAssets.count == 1 ? "" : "s") to \(endpoint.absoluteString)."
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

    private func copyVideo(from sourceURL: URL) throws -> SelectedVideoAsset {
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let fileValues = try? destinationURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(fileValues?.fileSize ?? 0)

        return SelectedVideoAsset(
            originalURL: destinationURL,
            displayName: sourceURL.lastPathComponent,
            fileSize: size > 0 ? size : nil
        )
    }

    private func cleanupProcessedAssets(_ assets: [ProcessedAudioAsset]) {
        for asset in assets {
            try? FileManager.default.removeItem(at: asset.audioURL)
        }
    }
}
