internal import Combine
import Foundation
import OSLog

@MainActor
final class AgentViewModel: ObservableObject {
    @Published var model = AgentModel()

    let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "AgentView"
    )
    let urlSession: URLSession
    let decoder = JSONDecoder()
    let encoder = JSONEncoder()

    var sourceVideos: [SelectedVideoAsset] = []
    var ingestResponse: IngestResponse?
    var ingestEndpoint: URL?
    /// WebSocket session id from `POST /projects/{id}/agent-sessions` when ingest has no `session_id`.
    var agentWebSocketSessionID: String?
    var sourceClipsByRemoteID: [String: AgentSourceClip] = [:]
    var webSocketTask: URLSessionWebSocketTask?
    var receiveTask: Task<Void, Never>?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func configure(
        promptText: String,
        videos: [SelectedVideoAsset],
        ingestResponse: IngestResponse?,
        ingestEndpoint: URL,
        agentWebSocketSessionID: String? = nil
    ) {
        closeSocket(sendDoneMessage: false)

        sourceVideos = videos
        self.ingestResponse = ingestResponse
        self.ingestEndpoint = ingestEndpoint
        self.agentWebSocketSessionID = agentWebSocketSessionID
        sourceClipsByRemoteID = [:]

        let resolvedSessionID = agentWebSocketSessionID ?? ingestResponse?.sessionID?.rawValue
        let resolvedProjectID = ingestResponse?.projectID?.rawValue

        model = AgentModel(
            promptText: promptText,
            stage: .idle,
            statusMessage: "Starting the editing process.",
            reasoningNotes: [],
            importedClips: videos.map { video in
                AgentImportedClip(
                    id: video.localKey,
                    displayName: video.displayName,
                    videoURL: video.originalURL
                )
            },
            extractionClips: [],
            timelineClips: [],
            pendingEditorSeed: nil,
            timelineNotes: [],
            feedbackDraft: "",
            sessionID: resolvedSessionID,
            projectID: resolvedProjectID,
            errorMessage: nil,
            isAwaitingUserInput: false,
            isConnected: false,
            isSendingFeedback: false,
            hasStarted: false
        )

        logger.info(
            "Configured agent view. promptLength=\(promptText.count) localVideos=\(videos.count) sessionID=\(resolvedSessionID ?? "nil", privacy: .public)"
        )
    }

    func startIfNeeded() async {
        guard !model.hasStarted else { return }

        model.hasStarted = true
        model.stage = .connecting
        model.errorMessage = nil
        setStatusMessage("Starting the editing process.")

        do {
            let response = try requireIngestResponse()
            sourceClipsByRemoteID = await buildSourceClipLookup(from: sourceVideos, response: response)

            guard let socketSessionId = agentWebSocketSessionID ?? response.sessionID?.rawValue else {
                throw AgentSessionError.missingSessionData
            }

            guard let ingestEndpoint,
                  let socketURL = AppConfiguration.agentWebSocketEndpoint(
                      sessionID: socketSessionId,
                      basedOn: ingestEndpoint
                  ) else {
                throw AgentSessionError.invalidSessionEndpoint
            }

            logger.info(
                "Opening websocket session \(socketSessionId, privacy: .public) at \(socketURL.absoluteString, privacy: .public)"
            )
            try await openSocket(at: socketURL)
            try await sendMessage(.startSession(prompt: model.promptText))
        } catch {
            applyError(error)
        }
    }

    func submitFeedback() async {
        guard model.canSubmitFeedback else { return }

        let prompt = model.feedbackDraft.trimmedForTransport
        model.feedbackDraft = ""
        model.isAwaitingUserInput = false
        model.isSendingFeedback = true
        model.errorMessage = nil
        model.stage = .assemblingTimeline
        setStatusMessage("Updating the edit with your feedback.")

        do {
            try await sendMessage(.reprompt(prompt: prompt))
        } catch {
            applyError(error)
        }
    }

    func approveTimeline() async {
        guard model.canApproveTimeline else { return }

        model.isAwaitingUserInput = false
        model.isSendingFeedback = true
        model.errorMessage = nil
        model.stage = .assemblingTimeline
        setStatusMessage("Finalizing your edit.")

        do {
            try await sendMessage(.reprompt(prompt: "approve"))
        } catch {
            applyError(error)
        }
    }

    func updateFeedbackDraft(_ text: String) {
        model.feedbackDraft = text
    }

    func closeIfNeeded() async {
        closeSocket(sendDoneMessage: true)
    }

    private func requireIngestResponse() throws -> IngestResponse {
        guard let ingestResponse else {
            throw AgentSessionError.missingSessionData
        }

        return ingestResponse
    }

}
