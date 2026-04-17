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

struct AudioExtractionService: Sendable {
    func extractCompressedAudio(from video: SelectedVideoAsset) async throws -> ProcessedAudioAsset {
        let asset = AVURLAsset(url: video.originalURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        guard !audioTracks.isEmpty else {
            throw AudioExtractionError.noAudioTrack
        }

        let outputURL = makeOutputURL(for: video)
        do {
            try await extractWithExportSession(audioTracks: audioTracks, outputURL: outputURL, videoName: video.displayName)
        } catch {
            print("[AudioExtraction] AppleM4A export failed for \(video.displayName): \(error)")
            try? FileManager.default.removeItem(at: outputURL)
            try await extractByTranscoding(audioTracks: audioTracks, outputURL: outputURL, videoName: video.displayName)
        }

        return ProcessedAudioAsset(
            source: video,
            localKey: video.localKey,
            audioURL: outputURL,
            mimeType: "audio/mp4",
            fileName: "\(video.originalURL.deletingPathExtension().lastPathComponent).m4a"
        )
    }

    private func extractWithExportSession(
        audioTracks: [AVAssetTrack],
        outputURL: URL,
        videoName: String
    ) async throws {
        var lastError: Error = AudioExtractionError.exportFailed

        for (index, audioTrack) in audioTracks.enumerated() {
            try? FileManager.default.removeItem(at: outputURL)

            do {
                let composition = try await makeAudioOnlyComposition(using: audioTrack)
                guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
                    throw AudioExtractionError.exportFailed
                }
                guard exportSession.supportedFileTypes.contains(.m4a) else {
                    throw AudioExtractionError.exportFailed
                }

                exportSession.outputURL = outputURL
                exportSession.outputFileType = .m4a
                exportSession.shouldOptimizeForNetworkUse = true

                try await export(exportSession)

                guard FileManager.default.fileExists(atPath: outputURL.path) else {
                    throw AudioExtractionError.exportFailed
                }
                return
            } catch {
                lastError = error
                print("[AudioExtraction] Export track \(index + 1)/\(audioTracks.count) failed for \(videoName): \(error)")
            }
        }

        throw lastError
    }

    private func extractByTranscoding(
        audioTracks: [AVAssetTrack],
        outputURL: URL,
        videoName: String
    ) async throws {
        var lastError: Error = AudioExtractionError.exportFailed

        for (index, audioTrack) in audioTracks.enumerated() {
            try? FileManager.default.removeItem(at: outputURL)

            do {
                let composition = try await makeAudioOnlyComposition(using: audioTrack)
                try await transcodeComposition(composition, outputURL: outputURL)
                return
            } catch {
                lastError = error
                print("[AudioExtraction] Stereo fallback track \(index + 1)/\(audioTracks.count) failed for \(videoName): \(error)")
            }
        }

        throw lastError
    }

    private func makeAudioOnlyComposition(using audioTrack: AVAssetTrack) async throws -> AVMutableComposition {
        let composition = AVMutableComposition()
        guard let compositionTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw AudioExtractionError.exportFailed
        }

        let timeRange = try await audioTrack.load(.timeRange)
        try compositionTrack.insertTimeRange(timeRange, of: audioTrack, at: .zero)
        return composition
    }

    private func export(_ exportSession: AVAssetExportSession) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            exportSession.exportAsynchronously {
                switch exportSession.status {
                case .completed:
                    continuation.resume()
                case .cancelled:
                    continuation.resume(throwing: CancellationError())
                case .failed:
                    continuation.resume(throwing: exportSession.error ?? AudioExtractionError.exportFailed)
                default:
                    continuation.resume(throwing: exportSession.error ?? AudioExtractionError.exportFailed)
                }
            }
        }
    }

    private func transcodeComposition(_ composition: AVMutableComposition, outputURL: URL) async throws {
        let audioTracks = try await composition.loadTracks(withMediaType: .audio)
        let reader = try makeReader(audioTracks: audioTracks, asset: composition)
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
    }

    private func makeReader(audioTracks: [AVAssetTrack], asset: AVAsset) throws -> AVAssetReader {
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioExtractionError.unableToCreateReader
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
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

        // Stereo AAC at a standard sample rate is much more tolerant of modern
        // phone-recorded audio layouts than forcing an aggressive mono downmix.
        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVEncoderBitRateKey: 96_000,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100
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
