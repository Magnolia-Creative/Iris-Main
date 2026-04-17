import SwiftUI

enum ImportTransitionKey {
    static let promptCard = "import-prompt-card"
    static let videosSection = "videos-section"

    static func importedVideoTile(_ localKey: String) -> String {
        "import-video-tile-\(localKey)"
    }
}

extension View {
    func importPromptCardTransition(in namespace: Namespace.ID, isSource: Bool) -> some View {
        matchedGeometryEffect(
            id: ImportTransitionKey.promptCard,
            in: namespace,
            properties: .frame,
            anchor: .topLeading,
            isSource: isSource
        )
    }

    func importVideosSectionTransition(in namespace: Namespace.ID, isSource: Bool) -> some View {
        matchedGeometryEffect(
            id: ImportTransitionKey.videosSection,
            in: namespace,
            properties: .frame,
            anchor: .topLeading,
            isSource: isSource
        )
    }

    func importVideoTileTransition(id: String, in namespace: Namespace.ID, isSource: Bool) -> some View {
        matchedGeometryEffect(
            id: ImportTransitionKey.importedVideoTile(id),
            in: namespace,
            properties: .frame,
            anchor: .center,
            isSource: isSource
        )
    }
}
