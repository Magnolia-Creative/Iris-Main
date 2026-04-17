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
        ingestEndpoint: URL
    ) {
        closeSocket(sendDoneMessage: false)

        sourceVideos = videos
        self.ingestResponse = ingestResponse
        self.ingestEndpoint = ingestEndpoint
        sourceClipsByRemoteID = [:]

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
            sessionID: ingestResponse?.sessionID.rawValue,
            projectID: nil,
            errorMessage: nil,
            isAwaitingUserInput: false,
            isConnected: false,
            isSendingFeedback: false,
            hasStarted: false
        )

        logger.info(
            "Configured agent view. promptLength=\(promptText.count) localVideos=\(videos.count) sessionID=\(ingestResponse?.sessionID.rawValue ?? "nil", privacy: .public)"
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

            guard let ingestEndpoint,
                  let socketURL = AppConfiguration.agentWebSocketEndpoint(
                      sessionID: response.sessionID.rawValue,
                      basedOn: ingestEndpoint
                  ) else {
                throw AgentSessionError.invalidSessionEndpoint
            }

            logger.info(
                "Opening websocket session \(response.sessionID.rawValue, privacy: .public) at \(socketURL.absoluteString, privacy: .public)"
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
