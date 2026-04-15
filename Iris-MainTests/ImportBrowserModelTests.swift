import Foundation
import Testing
@testable import Iris_Main

struct ImportBrowserModelTests {
    @Test func processingModeFlagsMatchExpectedBehaviors() {
        #expect(ImportProcessingMode.none.runsEmbeddings == false)
        #expect(ImportProcessingMode.none.runsAgentPreprocessing == false)
        #expect(ImportProcessingMode.embeddingsOnly.runsEmbeddings)
        #expect(ImportProcessingMode.embeddingsOnly.runsAgentPreprocessing == false)
        #expect(ImportProcessingMode.agentPreprocessingOnly.runsEmbeddings == false)
        #expect(ImportProcessingMode.agentPreprocessingOnly.runsAgentPreprocessing)
        #expect(ImportProcessingMode.embeddingsAndAgentPreprocessing.runsEmbeddings)
        #expect(ImportProcessingMode.embeddingsAndAgentPreprocessing.runsAgentPreprocessing)
    }

    @Test func selectedVideoAssetUsesLocalKeyAsStableIdentity() {
        let asset = SelectedVideoAsset(
            localKey: "local-123",
            assetLocalIdentifier: nil,
            localMediaID: "media-123",
            originalURL: URL(fileURLWithPath: "/tmp/clip.mov"),
            displayName: "clip.mov",
            fileSize: 42,
            remoteClipID: nil
        )

        #expect(asset.id == "local-123")
    }

    @Test func importBrowserModelRequiresPromptCommittedClipsAndAgentPrep() {
        var model = ImportBrowserModel()
        model.prompt.text = "Tight event recap with fast hero cuts."
        model.prompt.validationMessage = nil
        model.clips = [
            ImportClipProcessingItem(
                localKey: "local-123",
                assetLocalIdentifier: "asset-123",
                displayName: "clip.mov",
                originalURL: URL(fileURLWithPath: "/tmp/clip.mov"),
                fileSize: 42,
                localMediaID: nil,
                remoteClipID: nil,
                isSelected: true,
                isCommitted: true,
                embeddingState: .succeeded("Ready"),
                transcriptState: .succeeded("Ready"),
                uploadState: .succeeded("Ready"),
                commitmentStatus: "Committed"
            )
        ]

        #expect(model.canRequestAgentStart)

        model.processingMode = .embeddingsOnly
        #expect(model.canRequestAgentStart == false)
    }

    @Test func committedVideosPreserveResolvedLocalMediaIdentity() {
        var model = ImportBrowserModel()
        model.clips = [
            ImportClipProcessingItem(
                localKey: "local-123",
                assetLocalIdentifier: "asset-123",
                displayName: "clip.mov",
                originalURL: URL(fileURLWithPath: "/tmp/clip.mov"),
                fileSize: 42,
                localMediaID: "media-123",
                remoteClipID: nil,
                isSelected: true,
                isCommitted: true,
                embeddingState: .succeeded("Ready"),
                transcriptState: .succeeded("Ready"),
                uploadState: .succeeded("Ready"),
                commitmentStatus: "Committed"
            )
        ]

        #expect(model.committedVideos.count == 1)
        #expect(model.committedVideos.first?.localMediaID == "media-123")
    }

    @Test func processedAssetsAreReorderedToMatchClipSelectionOrder() {
        let first = SelectedVideoAsset(
            localKey: "local-1",
            assetLocalIdentifier: nil,
            localMediaID: nil,
            originalURL: URL(fileURLWithPath: "/tmp/clip-1.mov"),
            displayName: "clip-1.mov",
            fileSize: 11,
            remoteClipID: nil
        )
        let second = SelectedVideoAsset(
            localKey: "local-2",
            assetLocalIdentifier: nil,
            localMediaID: nil,
            originalURL: URL(fileURLWithPath: "/tmp/clip-2.mov"),
            displayName: "clip-2.mov",
            fileSize: 22,
            remoteClipID: nil
        )

        let processedSecond = ProcessedAudioAsset(
            source: second,
            localKey: second.localKey,
            audioURL: URL(fileURLWithPath: "/tmp/clip-2.m4a"),
            mimeType: "audio/mp4",
            fileName: "clip-2.m4a"
        )
        let processedFirst = ProcessedAudioAsset(
            source: first,
            localKey: first.localKey,
            audioURL: URL(fileURLWithPath: "/tmp/clip-1.m4a"),
            mimeType: "audio/mp4",
            fileName: "clip-1.m4a"
        )

        let ordered = orderedProcessedAssetsForUpload(
            [processedSecond, processedFirst],
            matching: [first, second]
        )

        #expect(ordered.map(\.localKey) == ["local-1", "local-2"])
    }
}
