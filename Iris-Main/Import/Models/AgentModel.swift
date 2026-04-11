import Foundation

struct AgentModel {
    var promptText = ""
    var stage: AgentStage = .idle
    var statusMessage = "Connecting to the editing session."
    var extractionClips: [AgentExtractionClip] = []
    var timelineClips: [AgentTimelineClip] = []
    var pendingEditorSeed: ImportedTimelineSeed?
    var timelineNotes: [String] = []
    var feedbackDraft = ""
    var sessionID: String?
    var projectID: String?
    var errorMessage: String?
    var isAwaitingUserInput = false
    var isConnected = false
    var isSendingFeedback = false
    var hasStarted = false

    var canApproveTimeline: Bool {
        isAwaitingUserInput && isConnected && !isSendingFeedback
    }

    var canSubmitFeedback: Bool {
        isAwaitingUserInput && isConnected && !isSendingFeedback && !feedbackDraft.trimmedForTransport.isEmpty
    }

    var canLaunchEditorReview: Bool {
        pendingEditorSeed != nil && isAwaitingUserInput
    }
}

enum AgentStage: Equatable {
    case idle
    case connecting
    case extractingClips
    case assemblingTimeline
    case waitingForFeedback
    case completed
    case error
    case closed
}

struct AgentSourceClip: Identifiable, Equatable {
    let id: String
    let localKey: String
    let displayName: String
    let videoURL: URL
    let durationSeconds: Double
    let order: Int
    let remoteIdentifiers: [String]
}

struct AgentExtractionClip: Identifiable, Equatable {
    let id: String
    let displayName: String
    let videoURL: URL
    let durationSeconds: Double
    let order: Int
    let remoteClipID: String
    var summary: String?
    var ranges: [AgentClipRange]
    var usesFullClip = false
    var isAnalyzing = false
    var isDropped = false

    var selectedDurationSeconds: Double {
        if usesFullClip {
            return max(durationSeconds, 0)
        }

        return ranges.reduce(0) { partialResult, range in
            partialResult + max(range.outSec - range.inSec, 0)
        }
    }

    var hasExtractedRanges: Bool {
        usesFullClip || !ranges.isEmpty
    }
}

struct AgentClipRange: Identifiable, Equatable {
    let id: String
    let inSec: Double
    let outSec: Double
    let reason: String

    init(inSec: Double, outSec: Double, reason: String) {
        self.inSec = inSec
        self.outSec = outSec
        self.reason = reason
        id = "\(inSec)-\(outSec)-\(reason)"
    }
}

struct AgentTimelineClip: Identifiable, Equatable {
    let id: String
    let displayName: String
    let videoURL: URL?
    let remoteClipID: String
    let inSec: Double
    let outSec: Double
    let rationale: String
    let segmentDurationSeconds: Double
    let usesPlaceholderAsset: Bool
}

extension String {
    var trimmedForTransport: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
