import Foundation

struct Operation: Codable, Identifiable {
    let operationId: String
    let projectId: String
    let createdAt: Date
    var updatedAt: Date
    let type: OperationType
    var status: OperationStatus
    var progress: Double?
    var stage: Stage
    var message: String?
    let cancelable: Bool
    var resultRefs: OperationResultRefs?
    var error: OperationError?

    var id: String { operationId }

    init(
        operationId: String = UUID().uuidString,
        projectId: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        type: OperationType,
        status: OperationStatus = .queued,
        progress: Double? = nil,
        stage: Stage = .validatingInputs,
        message: String? = nil,
        cancelable: Bool = true,
        resultRefs: OperationResultRefs? = nil,
        error: OperationError? = nil
    ) {
        self.operationId = operationId
        self.projectId = projectId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.type = type
        self.status = status
        self.progress = progress
        self.stage = stage
        self.message = message
        self.cancelable = cancelable
        self.resultRefs = resultRefs
        self.error = error
    }

    mutating func updateStatus(_ newStatus: OperationStatus) {
        status = newStatus
        updatedAt = Date()
    }

    mutating func updateStage(_ newStage: Stage, message: String? = nil) {
        stage = newStage
        self.message = message
        updatedAt = Date()
    }

    mutating func updateProgress(_ newProgress: Double) {
        progress = min(max(newProgress, 0.0), 1.0)
        updatedAt = Date()
    }

    mutating func setError(code: String, userMessage: String, debugMessage: String? = nil) {
        error = OperationError(code: code, userMessage: userMessage, debugMessage: debugMessage)
        status = .failed
        updatedAt = Date()
    }
}

enum OperationType: String, Codable {
    case autoCompose = "AUTO_COMPOSE"
    case nlEdit = "NL_EDIT"
    case beatSync = "BEAT_SYNC"
    case analyze = "ANALYZE"
    case export = "EXPORT"
}

enum OperationStatus: String, Codable {
    case queued = "QUEUED"
    case running = "RUNNING"
    case succeeded = "SUCCEEDED"
    case failed = "FAILED"
    case canceled = "CANCELED"
}

struct OperationResultRefs: Codable {
    var timelineId: String?
    var actionIds: [String]?
    var artifactIds: [String]?
    var exportAssetRefId: String?

    init(
        timelineId: String? = nil,
        actionIds: [String]? = nil,
        artifactIds: [String]? = nil,
        exportAssetRefId: String? = nil
    ) {
        self.timelineId = timelineId
        self.actionIds = actionIds
        self.artifactIds = artifactIds
        self.exportAssetRefId = exportAssetRefId
    }
}

struct OperationError: Codable {
    let code: String
    let userMessage: String
    let debugMessage: String?

    init(code: String, userMessage: String, debugMessage: String? = nil) {
        self.code = code
        self.userMessage = userMessage
        self.debugMessage = debugMessage
    }
}
