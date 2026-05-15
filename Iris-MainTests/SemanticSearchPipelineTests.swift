import CoreGraphics
import Foundation
import Testing
@testable import Iris_Main

struct SemanticSearchPipelineTests {
    @Test func incrementalBuildOnlyEmbedsNewOrChangedVideos() async throws {
        let embeddingService = TestEmbeddingService()
        let frameSampler = TestFrameSampler(
            timestampsByPath: [
                "/tmp/a.mov": [2.0],
                "/tmp/b.mov": [2.0],
                "/tmp/c.mov": [2.0],
            ]
        )
        let pipeline = SemanticSearchPipeline(
            embeddingService: embeddingService,
            frameSampler: frameSampler
        )

        let videoA = makeVideo(id: "a", name: "A", path: "/tmp/a.mov", visualSignature: "visual-a-v1")
        let videoB = makeVideo(id: "b", name: "B", path: "/tmp/b.mov", visualSignature: "visual-b-v1")
        let videoC = makeVideo(id: "c", name: "C", path: "/tmp/c.mov", visualSignature: "visual-c-v1")

        let firstState = try await pipeline.buildChunkIndex(
            videos: [videoA, videoB],
            invalidatedVideoIDs: ["a", "b"],
            onProgress: { _ in }
        )
        #expect(firstState.indexedFrameCount == 2)
        #expect(firstState.indexedVideoSignatures == ["a": "visual-a-v1", "b": "visual-b-v1"])
        #expect(await embeddingService.imageEmbeddingCallCount() == 2)

        let secondState = try await pipeline.buildChunkIndex(
            videos: [videoA, videoC],
            invalidatedVideoIDs: ["c"],
            onProgress: { _ in }
        )
        #expect(secondState.indexedFrameCount == 2)
        #expect(secondState.indexedVideoSignatures == ["a": "visual-a-v1", "c": "visual-c-v1"])
        #expect(await embeddingService.imageEmbeddingCallCount() == 3)

        _ = try await pipeline.buildChunkIndex(
            videos: [videoA, videoC],
            invalidatedVideoIDs: [],
            onProgress: { _ in }
        )
        #expect(await embeddingService.imageEmbeddingCallCount() == 3)
    }

    @Test func rebuildingChangedVideoKeepsOtherCachedEntries() async throws {
        let embeddingService = TestEmbeddingService()
        let frameSampler = TestFrameSampler(
            timestampsByPath: [
                "/tmp/a.mov": [2.0],
                "/tmp/b.mov": [2.0],
            ]
        )
        let pipeline = SemanticSearchPipeline(
            embeddingService: embeddingService,
            frameSampler: frameSampler
        )

        let originalA = makeVideo(id: "a", name: "A", path: "/tmp/a.mov", visualSignature: "visual-a-v1")
        let changedA = makeVideo(id: "a", name: "A", path: "/tmp/a.mov", visualSignature: "visual-a-v2")
        let videoB = makeVideo(id: "b", name: "B", path: "/tmp/b.mov", visualSignature: "visual-b-v1")

        _ = try await pipeline.buildChunkIndex(
            videos: [originalA, videoB],
            invalidatedVideoIDs: ["a", "b"],
            onProgress: { _ in }
        )
        #expect(await embeddingService.imageEmbeddingCallCount() == 2)

        let rebuiltState = try await pipeline.buildChunkIndex(
            videos: [changedA, videoB],
            invalidatedVideoIDs: ["a"],
            onProgress: { _ in }
        )
        #expect(rebuiltState.indexedFrameCount == 2)
        #expect(rebuiltState.indexedVideoSignatures == ["a": "visual-a-v2", "b": "visual-b-v1"])
        #expect(await embeddingService.imageEmbeddingCallCount() == 3)
    }
}

private func makeVideo(id: String, name: String, path: String, visualSignature: String) -> SemanticImportedVideo {
    SemanticImportedVideo(
        localKey: id,
        fileURL: URL(fileURLWithPath: path),
        displayName: name,
        durationSeconds: 4,
        transcriptSentences: [],
        uploadLocalKey: nil,
        visualContentSignature: visualSignature,
        transcriptContentSignature: "",
        contentSignature: "\(visualSignature)::"
    )
}

private actor TestEmbeddingService: MobileCLIPEmbeddingProviding {
    private var imageCalls = 0

    func prewarm() async {}

    func textEmbedding(for text: String) async throws -> [Float] {
        [1]
    }

    func imageEmbedding(for image: CGImage) async throws -> [Float] {
        imageCalls += 1
        return [Float(imageCalls)]
    }

    func imageEmbeddingCallCount() -> Int {
        imageCalls
    }
}

private actor TestFrameSampler: VideoFrameSampling {
    private let timestampsByPath: [String: [Double]]

    init(timestampsByPath: [String: [Double]]) {
        self.timestampsByPath = timestampsByPath
    }

    func loadDurationSeconds(videoURL: URL) async throws -> Double {
        4
    }

    func sampleFrames(
        videoURL: URL,
        atTimestamps timestamps: [Double],
        maximumDimension: CGFloat?
    ) async throws -> [SampledVideoFrame] {
        let supportedTimestamps = Set(timestampsByPath[videoURL.path] ?? [])
        return timestamps.compactMap { timestamp in
            guard supportedTimestamps.contains(timestamp) else { return nil }
            return SampledVideoFrame(
                timestampSeconds: timestamp,
                image: makeTestImage()
            )
        }
    }
}

private func makeTestImage() -> CGImage {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bytesPerPixel = 4
    let width = 1
    let height = 1
    let bytesPerRow = width * bytesPerPixel
    var pixels: [UInt8] = [255, 0, 0, 255]
    let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
    return context!.makeImage()!
}
