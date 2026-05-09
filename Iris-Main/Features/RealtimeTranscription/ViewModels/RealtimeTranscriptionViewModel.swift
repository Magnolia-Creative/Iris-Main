internal import Combine
import Foundation

@MainActor
final class RealtimeTranscriptionViewModel: ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isSocketActive = false
    @Published private(set) var finalizedTranscript = ""
    @Published private(set) var partialTranscript = ""
    @Published private(set) var statusMessage = "Tap the microphone to stream speech to the backend."
    @Published private(set) var errorMessage: String?

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let audioCapture = RealtimeAudioCaptureService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let urlSession: URLSession

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func toggleRecording() async {
        if isRecording {
            await stopRecordingGracefully()
        } else {
            await startRecording()
        }
    }

    /// Stops capture and closes the socket without awaiting server teardown (e.g. sheet dismiss).
    func tearDown() {
        audioCapture.stop()
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isRecording = false
        isSocketActive = false
        statusMessage = "Tap the microphone to stream speech to the backend."
    }

    private func startRecording() async {
        errorMessage = nil
        finalizedTranscript = ""
        partialTranscript = ""

        let allowed = await RealtimeAudioCaptureService.requestRecordPermission()
        guard allowed else {
            errorMessage = "Microphone access is required for live transcription."
            return
        }

        guard let socketURL = AppConfiguration.transcriptionWebSocketEndpoint() else {
            errorMessage = "Could not build the transcription WebSocket URL. Check backend configuration."
            return
        }

        tearDown()

        let task = urlSession.webSocketTask(with: socketURL)
        webSocketTask = task
        task.resume()
        isSocketActive = true
        statusMessage = "Connecting…"

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
            statusMessage = "Listening…"
        } catch {
            tearDown()
            errorMessage = error.localizedDescription
        }
    }

    private func stopRecordingGracefully() async {
        guard isRecording else {
            tearDown()
            return
        }

        audioCapture.stop()

        if let webSocketTask {
            do {
                let stop = RealtimeTranscriptionClientStopMessage()
                let data = try encoder.encode(stop)
                if let text = String(data: data, encoding: .utf8) {
                    try await webSocketTask.send(.string(text))
                }
            } catch {
                // Still close the socket.
            }
        }

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        isRecording = false
        isSocketActive = false
        statusMessage = "Tap the microphone to stream speech to the backend."
    }

    private func sendAudioPCM(_ pcmData: Data) async {
        guard isRecording, let webSocketTask else { return }
        let payload = RealtimeTranscriptionClientAudioMessage(audio: pcmData.base64EncodedString())
        guard let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) else {
            return
        }
        do {
            try await webSocketTask.send(.string(text))
        } catch {
            if isRecording {
                errorMessage = error.localizedDescription
                await stopRecordingGracefully()
            }
        }
    }

    private func receiveLoop() async {
        guard let webSocketTask else { return }

        do {
            while !Task.isCancelled {
                let message = try await webSocketTask.receive()
                if Task.isCancelled { break }

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
            if !Task.isCancelled, isSocketActive {
                if errorMessage == nil, isRecording || isSocketActive {
                    errorMessage = error.localizedDescription
                }
                partialTranscript = ""
            }
        }

        isSocketActive = false
        if !isRecording {
            partialTranscript = ""
        }
    }

    private func handleIncoming(_ data: Data) {
        let event: RealtimeTranscriptionServerEvent
        do {
            event = try RealtimeTranscriptionServerEvent.decode(from: data, using: decoder)
        } catch {
            return
        }

        switch event {
        case .sessionReady(let model):
            errorMessage = nil
            statusMessage = model.isEmpty ? "Connected." : "Connected (\(model))."
        case .delta(let text):
            partialTranscript += text
        case .completed(let text):
            if !text.isEmpty {
                if finalizedTranscript.isEmpty {
                    finalizedTranscript = text
                } else {
                    finalizedTranscript += " " + text
                }
            }
            partialTranscript = ""
        case .speechStarted:
            break
        case .speechStopped:
            break
        case .error(let detail):
            errorMessage = detail
        case .unknown:
            break
        }
    }
}
