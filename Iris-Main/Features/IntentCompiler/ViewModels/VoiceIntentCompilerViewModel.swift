internal import Combine
import Foundation

@MainActor
final class VoiceIntentCompilerViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isSocketActive = false
    @Published private(set) var finalizedTranscript = ""
    @Published private(set) var partialTranscript = ""
    @Published private(set) var statusMessage = "Tap the microphone to describe an effect."
    @Published private(set) var errorMessage: String?
    @Published private(set) var outputText = ""
    @Published private(set) var audioChunkCount = 0

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let audioCapture = RealtimeAudioCaptureService()
    private let urlSession: URLSession
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let context: IntentCompilerContext

    init(
        urlSession: URLSession = .shared,
        context: IntentCompilerContext? = nil
    ) {
        self.urlSession = urlSession
        self.context = context ?? Self.makeSampleContext()
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func toggleRecording() async {
        if isRecording {
            await finishRecording()
        } else {
            await startRecording()
        }
    }

    func tearDown() {
        audioCapture.stop()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isRecording = false
        isSocketActive = false
        partialTranscript = ""
    }

    private func startRecording() async {
        errorMessage = nil
        outputText = ""
        finalizedTranscript = ""
        partialTranscript = ""
        audioChunkCount = 0

        let allowed = await RealtimeAudioCaptureService.requestRecordPermission()
        guard allowed else {
            errorMessage = "Microphone access is required for voice intent prompts."
            return
        }

        guard let socketURL = AppConfiguration.voiceIntentWebSocketEndpoint() else {
            errorMessage = "Could not build the voice intent WebSocket URL."
            return
        }

        tearDown()
        statusMessage = "Connecting to backend..."

        let task = urlSession.webSocketTask(with: socketURL)
        webSocketTask = task
        task.resume()
        isSocketActive = true

        do {
            let start = try encoder.encode(VoiceIntentStartMessage(context: context))
            if let text = String(data: start, encoding: .utf8) {
                try await task.send(.string(text))
            }
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
            return
        }

        receiveTask = Task { @MainActor [weak self] in
            await self?.receiveLoop()
        }

        do {
            try audioCapture.start { [weak self] pcmData in
                guard let self else { return }
                Task { @MainActor in
                    await self.sendAudioPCM(pcmData)
                }
            }
            isRecording = true
            statusMessage = "Listening for an effect prompt..."
        } catch {
            tearDown()
            errorMessage = error.localizedDescription
        }
    }

    private func finishRecording() async {
        guard isRecording, let webSocketTask else {
            tearDown()
            return
        }

        audioCapture.stop()
        isRecording = false
        statusMessage = "Finishing transcript..."

        do {
            let finalize = try encoder.encode(VoiceIntentFinalizeMessage())
            if let text = String(data: finalize, encoding: .utf8) {
                try await webSocketTask.send(.string(text))
            }
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
        }
    }

    private func sendAudioPCM(_ pcmData: Data) async {
        guard isRecording, let webSocketTask else { return }
        let ts = Int(Date().timeIntervalSince1970 * 1_000)
        let payload = RealtimeTranscriptionClientAudioMessage(
            audio: pcmData.base64EncodedString(),
            clientSentTimestamp: ts
        )
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await webSocketTask.send(.string(text))
            audioChunkCount += 1
        } catch {
            errorMessage = error.localizedDescription
            tearDown()
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }
        do {
            while !Task.isCancelled {
                let message = try await task.receive()
                switch message {
                case .string(let text):
                    handleIncoming(Data(text.utf8))
                case .data(let data):
                    handleIncoming(data)
                @unknown default:
                    break
                }
            }
        } catch {
            if !Task.isCancelled, isSocketActive, errorMessage == nil {
                errorMessage = error.localizedDescription
            }
        }
        isSocketActive = false
    }

    private func handleIncoming(_ data: Data) {
        guard let event = try? VoiceIntentServerEvent.decode(from: data, using: decoder) else {
            return
        }

        switch event {
        case .sessionReady(let model):
            statusMessage = model.isEmpty ? "Connected." : "Connected (\(model))."
        case .transcriptDelta(let text):
            partialTranscript += text
        case .transcriptCompleted(let text):
            if !text.isEmpty {
                finalizedTranscript = finalizedTranscript.isEmpty ? text : "\(finalizedTranscript) \(text)"
            }
            partialTranscript = ""
            statusMessage = "Processing effects..."
        case .status(let type, let message):
            statusMessage = message ?? Self.defaultStatusMessage(for: type)
        case .intentResult(_, let result):
            outputText = (try? formattedOutput(for: result)) ?? "{}"
            statusMessage = "Effect result ready."
            isSocketActive = false
            webSocketTask?.cancel(with: .normalClosure, reason: nil)
            webSocketTask = nil
        case .speechStarted:
            break
        case .speechStopped:
            break
        case .error(let detail):
            errorMessage = detail
            statusMessage = "Voice intent failed."
        case .unknown:
            break
        }
    }

    private func formattedOutput(for result: IntentCompileResult) throws -> String {
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func defaultStatusMessage(for type: String) -> String {
        switch type {
        case "planner_started":
            return "Parsing prompt."
        case "planner_completed":
            return "Prompt parsed."
        case "effect_planner_started":
            return "Planning effects."
        case "effect_planner_completed":
            return "Effects planned."
        case "validation_completed":
            return "Validated result."
        default:
            return "Processing intent."
        }
    }
}

private extension VoiceIntentCompilerViewModel {
    static func makeSampleContext() -> IntentCompilerContext {
        let clips = [
            Clip(
                clipId: "clip-a",
                trackId: "track-video",
                mediaId: "media-a",
                sourceRange: TimeRange(start: 0, end: 5_000_000),
                timelineRange: TimeRange(start: 0, end: 5_000_000)
            ),
            Clip(
                clipId: "clip-b",
                trackId: "track-video",
                mediaId: "media-b",
                sourceRange: TimeRange(start: 0, end: 10_000_000),
                timelineRange: TimeRange(start: 5_000_000, end: 15_000_000)
            ),
            Clip(
                clipId: "clip-c",
                trackId: "track-video",
                mediaId: "media-c",
                sourceRange: TimeRange(start: 0, end: 5_000_000),
                timelineRange: TimeRange(start: 15_000_000, end: 20_000_000)
            )
        ]

        var state = TimelineState(timelineId: "timeline-test")
        state.tracks = [
            Track(trackId: "track-video", timelineId: "timeline-test", kind: .video)
        ]
        state.clips = clips
        state.selectedClipId = "clip-b"
        state.currentTimeAtCenter = 10_000_000
        return state.makeIntentCompilerContext()
    }
}

