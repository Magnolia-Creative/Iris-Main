import AVFoundation
import Foundation

/// Captures microphone audio and mirrors the React AudioWorklet: buffer ~100 ms,
/// linearly resample to 2400 mono Int16 samples, then emit one PCM chunk.
final class RealtimeAudioCaptureService {
    static let outputSampleRate: Double = 24_000
    /// 100 ms of mono Int16 @ 24 kHz (matches Iris-Testing-App worklet chunk size).
    private static let chunkSampleCount = 2_400
    private static let chunkByteCount = chunkSampleCount * MemoryLayout<Int16>.size

    private var engine: AVAudioEngine?
    private var inputScratch: [Float] = []
    private var inputSamplesNeeded = 0
    private var hasLoggedInputFormat = false
    private var onPCMChunk: (@Sendable (Data) -> Void)?
    private var onLevel: (@Sendable (Float) -> Void)?

    /// Request microphone access. Call before `start`.
    static func requestRecordPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { allowed in
                continuation.resume(returning: allowed)
            }
        }
    }

    /// Starts capture. `onChunk` is invoked from the audio tap thread with PCM16 mono @ 24 kHz payloads (~100 ms each).
    /// `onLevel` emits a normalized RMS level from the same mono samples and is intended for UI metering only.
    func start(
        onChunk: @escaping @Sendable (Data) -> Void,
        onLevel: (@Sendable (Float) -> Void)? = nil
    ) throws {
        stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: [.allowBluetoothHFP])
        try session.setPreferredSampleRate(Self.outputSampleRate)
        try? session.setPreferredInputNumberOfChannels(1)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RealtimeAudioCaptureError.invalidInputFormat(
                sampleRate: inputFormat.sampleRate,
                channelCount: inputFormat.channelCount
            )
        }

        self.engine = engine
        self.inputSamplesNeeded = max(1, Int(floor(inputFormat.sampleRate * 0.1)))
        self.inputScratch = []
        self.inputScratch.reserveCapacity(inputSamplesNeeded * 2)
        self.hasLoggedInputFormat = false
        self.onPCMChunk = onChunk
        self.onLevel = onLevel

        let bufferSize: AVAudioFrameCount = 4_096
        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            self?.processInputBuffer(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    func stop() {
        onPCMChunk = nil
        onLevel = nil

        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
        }
        engine = nil
        inputScratch.removeAll(keepingCapacity: false)
        inputSamplesNeeded = 0

        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let onPCMChunk else { return }
        guard inputSamplesNeeded > 0,
              buffer.frameLength > 0,
              let channelData = buffer.floatChannelData else {
            return
        }

        let sampleCount = Int(buffer.frameLength)
        let channelCount = max(1, Int(buffer.format.channelCount))
        if !hasLoggedInputFormat {
            hasLoggedInputFormat = true
            print(
                "[RealtimeAudioCaptureService] input sampleRate=\(buffer.format.sampleRate) " +
                "channels=\(channelCount) interleaved=\(buffer.format.isInterleaved) frames=\(sampleCount)"
            )
        }
        inputScratch.reserveCapacity(inputScratch.count + sampleCount)

        var sumSquares: Float = 0
        for index in 0 ..< sampleCount {
            let sample = monoSample(at: index, channelData: channelData, channelCount: channelCount, isInterleaved: buffer.format.isInterleaved)
            inputScratch.append(sample)
            sumSquares += sample * sample
        }
        emitInputLevel(sumSquares: sumSquares, sampleCount: sampleCount)

        while inputScratch.count >= inputSamplesNeeded {
            let source = Array(inputScratch.prefix(inputSamplesNeeded))
            inputScratch.removeFirst(inputSamplesNeeded)
            onPCMChunk(makePCM16Chunk(from: source))
        }
    }

    private func monoSample(
        at frameIndex: Int,
        channelData: UnsafePointer<UnsafeMutablePointer<Float>>,
        channelCount: Int,
        isInterleaved: Bool
    ) -> Float {
        guard channelCount > 1 else {
            return channelData[0][frameIndex]
        }

        var sum: Float = 0
        if isInterleaved {
            let base = frameIndex * channelCount
            for channel in 0 ..< channelCount {
                sum += channelData[0][base + channel]
            }
        } else {
            for channel in 0 ..< channelCount {
                sum += channelData[channel][frameIndex]
            }
        }
        return sum / Float(channelCount)
    }

    private func emitInputLevel(sumSquares: Float, sampleCount: Int) {
        guard sampleCount > 0 else { return }
        let rms = sqrt(sumSquares / Float(sampleCount))
        let normalized = min(1, max(0, rms * 8))
        onLevel?(normalized)
    }

    private func makePCM16Chunk(from source: [Float]) -> Data {
        var pcm = Data()
        pcm.reserveCapacity(Self.chunkByteCount)

        let lenM1 = max(source.count - 1, 0)
        for j in 0 ..< Self.chunkSampleCount {
            let t = (Float(j) + 0.5) * Float(lenM1) / Float(Self.chunkSampleCount)
            let i0 = Int(floor(t))
            let f = t - Float(i0)
            let s0 = source[min(i0, source.count - 1)]
            let s1 = source[min(i0 + 1, source.count - 1)]
            let interpolated = s0 * (1 - f) + s1 * f
            let x = interpolated * Float(Int16.max)
            var sample = Int16(max(Float(Int16.min), min(Float(Int16.max), x + 0.5)))
            withUnsafeBytes(of: &sample) { bytes in
                pcm.append(contentsOf: bytes)
            }
        }

        return pcm
    }
}

enum RealtimeAudioCaptureError: LocalizedError {
    case invalidInputFormat(sampleRate: Double, channelCount: AVAudioChannelCount)

    var errorDescription: String? {
        switch self {
        case let .invalidInputFormat(sampleRate, channelCount):
            return "Simulator microphone is unavailable or misconfigured (sample rate \(sampleRate), channels \(channelCount)). Choose a valid Simulator audio input or test on a device."
        }
    }
}
