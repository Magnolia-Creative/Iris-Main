import AVFoundation
import Darwin
import Foundation

/// Captures microphone audio, converts to mono PCM Int16 @ 24 kHz, and emits fixed-size chunks for the transcription WebSocket.
final class RealtimeAudioCaptureService {
    static let outputSampleRate: Double = 24_000
    /// 100 ms of mono Int16 @ 24 kHz (matches Iris-Testing-App worklet chunk size).
    private static let chunkByteCount = 2_400 * MemoryLayout<Int16>.size

    private var engine: AVAudioEngine?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?
    private var pcmScratch = Data()
    private var onPCMChunk: (@Sendable (Data) -> Void)?

    /// Request microphone access. Call before `start`.
    static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    /// Starts capture. `onChunk` is invoked from the audio tap thread with PCM16 mono @ 24 kHz payloads (~100 ms each).
    func start(onChunk: @escaping @Sendable (Data) -> Void) throws {
        stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try session.setPreferredSampleRate(Self.outputSampleRate)
        try session.setActive(true)

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Self.outputSampleRate,
            channels: 1,
            interleaved: true
        ) else {
            throw RealtimeAudioCaptureError.invalidOutputFormat
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw RealtimeAudioCaptureError.converterInitFailed
        }

        self.engine = engine
        self.converter = converter
        self.outputFormat = outputFormat
        self.pcmScratch = Data()
        self.onPCMChunk = onChunk

        let bufferSize: AVAudioFrameCount = 4_096
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer, converter: converter, outputFormat: outputFormat)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        onPCMChunk = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        converter = nil
        outputFormat = nil
        pcmScratch.removeAll(keepingCapacity: false)

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func processInputBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        guard let onPCMChunk else { return }

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(ceil(Double(buffer.frameLength) * ratio)) + 32
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outCapacity) else {
            return
        }

        var didSupplyInput = false
        var error: NSError?
        _ = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didSupplyInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didSupplyInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error != nil {
            return
        }

        guard outputBuffer.frameLength > 0, let channelData = outputBuffer.int16ChannelData else {
            return
        }

        let byteCount = Int(outputBuffer.frameLength) * MemoryLayout<Int16>.size
        var block = Data(count: byteCount)
        block.withUnsafeMutableBytes { raw in
            guard let dst = raw.baseAddress else { return }
            memcpy(dst, channelData[0], byteCount)
        }
        pcmScratch.append(block)

        let chunkSize = Self.chunkByteCount
        while pcmScratch.count >= chunkSize {
            let chunk = pcmScratch.prefix(chunkSize)
            pcmScratch.removeFirst(chunkSize)
            onPCMChunk(Data(chunk))
        }
    }
}

enum RealtimeAudioCaptureError: LocalizedError {
    case invalidOutputFormat
    case converterInitFailed

    var errorDescription: String? {
        switch self {
        case .invalidOutputFormat:
            return "Could not create 24 kHz PCM output format."
        case .converterInitFailed:
            return "Could not create audio converter for the microphone format."
        }
    }
}
