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
                uploadState: .succeeded("Ready"),
                commitmentStatus: "Committed"
            )
        ]

        #expect(model.canRequestAgentStart)

        model.processingMode = .embeddingsOnly
        #expect(model.canRequestAgentStart == false)
    }
}
