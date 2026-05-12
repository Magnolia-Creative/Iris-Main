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
    @Published private(set) var audioChunkCount = 0
    @Published private(set) var inputLevel: Float = 0

    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private let audioCapture = RealtimeAudioCaptureService()
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let urlSession: URLSession
    private var stopFinalizationWaiter: CheckedContinuation<Void, Never>?
    private var isAwaitingStopFinalization = false

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
        inputLevel = 0
        statusMessage = "Tap the microphone to stream speech to the backend."
        isAwaitingStopFinalization = false
        if let waiter = stopFinalizationWaiter {
            stopFinalizationWaiter = nil
            waiter.resume()
        }
    }

    private func startRecording() async {
        errorMessage = nil
        finalizedTranscript = ""
        partialTranscript = ""
        audioChunkCount = 0

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
        statusMessage = "Starting microphone…"

        do {
            try audioCapture.start(
                onChunk: { [weak self] pcmData in
                    guard let self else { return }
                    Task { @MainActor in
                        await self.sendAudioPCM(pcmData)
                    }
                },
                onLevel: { [weak self] level in
                    guard let self else { return }
                    Task { @MainActor in
                        self.updateInputLevel(level)
                    }
                }
            )
            isRecording = true
        } catch {
            tearDown()
            errorMessage = error.localizedDescription
            statusMessage = "Microphone could not start."
            return
        }

        let task = urlSession.webSocketTask(with: socketURL)
        webSocketTask = task
        task.resume()
        isSocketActive = true
        statusMessage = "Connecting…"

        receiveTask = Task { @MainActor [weak self] in
            await self?.receiveLoop()
        }
    }

    private func stopRecordingGracefully() async {
        guard isRecording else {
            tearDown()
            return
        }

        audioCapture.stop()
        inputLevel = 0
        statusMessage = "Finalizing transcription…"

        // Stop sending audio chunks but keep the socket open so we can collect
        // any final `completed` event the server still has queued up.
        isRecording = false
        isAwaitingStopFinalization = true

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

        await awaitStopFinalization(timeout: .seconds(2))
        isAwaitingStopFinalization = false

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .normalClosure, reason: nil)
        webSocketTask = nil

        isSocketActive = false
        inputLevel = 0
        statusMessage = "Tap the microphone to stream speech to the backend."
    }

    private func awaitStopFinalization(timeout: Duration) async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { @MainActor [weak self] in
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    guard let self else {
                        continuation.resume()
                        return
                    }
                    self.stopFinalizationWaiter = continuation
                }
            }
            group.addTask { @MainActor [weak self] in
                try? await Task.sleep(for: timeout)
                guard let self, let waiter = self.stopFinalizationWaiter else { return }
                self.stopFinalizationWaiter = nil
                waiter.resume()
            }
            await group.next()
            group.cancelAll()
        }
    }

    private func resolveStopFinalization() {
        guard isAwaitingStopFinalization, let waiter = stopFinalizationWaiter else { return }
        stopFinalizationWaiter = nil
        waiter.resume()
    }

    private func updateInputLevel(_ level: Float) {
        let clamped = min(1, max(0, level))
        inputLevel = inputLevel * 0.65 + clamped * 0.35
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
            if audioChunkCount == 1 {
                statusMessage = "Streaming audio to backend…"
            } else if audioChunkCount.isMultiple(of: 20) {
                statusMessage = "Streaming audio to backend… \(audioChunkCount) chunks sent"
            }
        } catch {
            if isRecording {
                errorMessage = error.localizedDescription
                await stopRecordingGracefully()
            }
        }
    }

    private func receiveLoop() async {
        guard let task = webSocketTask else { return }

        do {
            while !Task.isCancelled {
                let message = try await task.receive()
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
        if isRecording, !Task.isCancelled {
            audioCapture.stop()
            webSocketTask = nil
            isRecording = false
            if errorMessage == nil {
                statusMessage = "Connection closed before transcription completed."
            }
        } else {
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
            resolveStopFinalization()
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
