@preconcurrency import AVFoundation
import Foundation

enum AudioExtractionError: LocalizedError {
    case noAudioTrack
    case unableToCreateReader
    case unableToCreateWriter
    case exportFailed

    var errorDescription: String? {
        switch self {
        case .noAudioTrack:
            return "One of the selected videos does not contain an audio track."
        case .unableToCreateReader:
            return "The app could not read audio from the selected video."
        case .unableToCreateWriter:
            return "The app could not create a compressed audio file."
        case .exportFailed:
            return "The compressed audio export did not finish successfully."
        }
    }
}

struct AudioExtractionService {
    func extractCompressedAudio(from video: SelectedVideoAsset) async throws -> ProcessedAudioAsset {
        let asset = AVURLAsset(url: video.originalURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw AudioExtractionError.noAudioTrack
        }

        let outputURL = makeOutputURL(for: video)
        let reader = try makeReader(audioTracks: audioTracks, asset: asset)
        let writer = try makeWriter(outputURL: outputURL)

        guard reader.startReading() else {
            throw reader.error ?? AudioExtractionError.unableToCreateReader
        }

        guard writer.startWriting() else {
            throw writer.error ?? AudioExtractionError.unableToCreateWriter
        }

        writer.startSession(atSourceTime: .zero)

        let readerOutput = reader.outputs[0]
        let writerInput = writer.inputs[0]

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "audio.extraction.writer")

            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if reader.status == .reading,
                       let sampleBuffer = readerOutput.copyNextSampleBuffer() {
                        if !writerInput.append(sampleBuffer) {
                            writerInput.markAsFinished()
                            reader.cancelReading()
                            writer.cancelWriting()
                            continuation.resume(throwing: writer.error ?? AudioExtractionError.exportFailed)
                            return
                        }
                    } else {
                        writerInput.markAsFinished()

                        if reader.status == .failed {
                            writer.cancelWriting()
                            continuation.resume(throwing: reader.error ?? AudioExtractionError.exportFailed)
                            return
                        }

                        writer.finishWriting {
                            if writer.status == .completed {
                                continuation.resume()
                            } else {
                                continuation.resume(throwing: writer.error ?? AudioExtractionError.exportFailed)
                            }
                        }
                        return
                    }
                }
            }
        }

        return ProcessedAudioAsset(
            source: video,
            localKey: video.localKey,
            audioURL: outputURL,
            mimeType: "audio/mp4",
            fileName: "\(video.originalURL.deletingPathExtension().lastPathComponent).m4a"
        )
    }

    private func makeReader(audioTracks: [AVAssetTrack], asset: AVAsset) throws -> AVAssetReader {
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioExtractionError.unableToCreateReader
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMBitDepthKey: 16
        ]

        let output = AVAssetReaderAudioMixOutput(audioTracks: audioTracks, audioSettings: outputSettings)
        output.alwaysCopiesSampleData = false

        guard reader.canAdd(output) else {
            throw AudioExtractionError.unableToCreateReader
        }

        reader.add(output)
        return reader
    }

    private func makeWriter(outputURL: URL) throws -> AVAssetWriter {
        try? FileManager.default.removeItem(at: outputURL)

        guard let writer = try? AVAssetWriter(outputURL: outputURL, fileType: .m4a) else {
            throw AudioExtractionError.unableToCreateWriter
        }

        // 48 kbps AAC mono at 24 kHz is a practical speech-oriented balance:
        // much smaller than video while preserving most vocal intelligibility.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: 48_000,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: 24_000
        ]

        let input = AVAssetWriterInput(mediaType: .audio, outputSettings: outputSettings)
        input.expectsMediaDataInRealTime = false

        guard writer.canAdd(input) else {
            throw AudioExtractionError.unableToCreateWriter
        }

        writer.add(input)
        return writer
    }

    private func makeOutputURL(for video: SelectedVideoAsset) -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
    }
}
