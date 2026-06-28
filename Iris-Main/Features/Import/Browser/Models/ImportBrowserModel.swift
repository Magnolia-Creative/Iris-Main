import Foundation
import Photos

enum ImportProcessingMode: String, CaseIterable, Identifiable {
    case none
    case embeddingsOnly
    case agentPreprocessingOnly
    case embeddingsAndAgentPreprocessing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none:
            "Browse only"
        case .embeddingsOnly:
            "Embeddings"
        case .agentPreprocessingOnly:
            "Agent prep"
        case .embeddingsAndAgentPreprocessing:
            "Embeddings + Agent"
        }
    }

    /// MobileCLIP / on-device semantic indexing during import is disabled; server clip processing covers prep.
    var runsEmbeddings: Bool {
        false
    }

    var runsAgentPreprocessing: Bool {
        switch self {
        case .agentPreprocessingOnly, .embeddingsAndAgentPreprocessing:
            true
        case .none, .embeddingsOnly:
            false
        }
    }

    /// Local `/agent/transcriptions/sentences` is used when `runsEmbeddings` is true and agent clip upload is off.
    /// With on-device import embeddings disabled (`runsEmbeddings` is false), this stays false and transcripts come from server clip processing when agent prep runs.
    var usesLocalTranscriptionEndpoint: Bool {
        runsEmbeddings && !runsAgentPreprocessing
    }
}

enum ImportClipWorkState: Equatable {
    case idle
    case queued(String)
    case running(String)
    case succeeded(String)
    case failed(String)
    case cancelled

    var isRunning: Bool {
        switch self {
        case .queued, .running:
            true
        case .idle, .succeeded, .failed, .cancelled:
            false
        }
    }

    var isSucceeded: Bool {
        if case .succeeded = self { return true }
        return false
    }

    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .idle:
            "Idle"
        case .queued(let message), .running(let message), .succeeded(let message), .failed(let message):
            message
        case .cancelled:
            "Cancelled"
        }
    }
}

struct ImportBrowserAlbum: Identifiable, Equatable {
    static let allVideosID = "all-videos"

    let id: String
    let title: String
    let count: Int
}

struct ImportBrowserAsset: Identifiable, Equatable {
    let id: String
    let displayName: String
    let durationText: String
    let createdAt: Date?
    var isSelected: Bool
    var isCommitted: Bool
}

struct RemoteBackendProject: Equatable {
    let projectID: String
    let projectName: String
}

struct ImportClipProcessingItem: Identifiable, Equatable {
    let localKey: String
    let assetLocalIdentifier: String
    var displayName: String
    var originalURL: URL?
    var fileSize: Int64?
    var localMediaID: String?
    var remoteClipID: String?
    var isSelected = true
    var isCommitted = false
    var embeddingState: ImportClipWorkState = .idle
    var transcriptState: ImportClipWorkState = .idle
    var uploadState: ImportClipWorkState = .idle
    var commitmentStatus = "Waiting to confirm selection"

    var id: String { localKey }

    var hasFailure: Bool {
        embeddingState.isFailed || uploadState.isFailed
    }
}

struct ImportBrowserModel {
    var authorizationStatus: PHAuthorizationStatus = .notDetermined
    var isLoadingLibrary = false
    var loadErrorMessage: String?
    var albums: [ImportBrowserAlbum] = []
    var selectedAlbumID = ImportBrowserAlbum.allVideosID
    var visibleAssets: [ImportBrowserAsset] = []
    var clips: [ImportClipProcessingItem] = []
    var processingMode: ImportProcessingMode = .embeddingsAndAgentPreprocessing
    var prompt = PromptMessageState()
    var statusMessage = "Select clips to start preparing them for Iris."
    var remoteBackendProject: RemoteBackendProject?
    var agentWebSocketSessionID: String?
    var ingestResponse: IngestResponse?
    var isAwaitingAgentStart = false
    var isPreparingAgentTransition = false

    var selectedClipCount: Int {
        clips.filter(\.isSelected).count
    }

    var committedClipCount: Int {
        clips.filter(\.isCommitted).count
    }

    var committedVideos: [SelectedVideoAsset] {
        clips.compactMap { clip in
            guard clip.isCommitted, clip.isSelected, let originalURL = clip.originalURL else { return nil }
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
    }

    var canRequestAgentStart: Bool {
        processingMode.runsAgentPreprocessing && committedClipCount > 0 && prompt.isReady
    }
}
