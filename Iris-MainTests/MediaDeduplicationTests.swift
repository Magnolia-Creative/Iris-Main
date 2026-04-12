import Foundation
import Testing
@testable import Iris_Main

struct MediaDeduplicationTests {
    @Test func deduplicatedForImportPresentationKeepsEarliestInstancePerKind() {
        let baseDate = Date(timeIntervalSince1970: 1_700_000_000)
        let duplicateVideo = Media(
            mediaId: "video-b",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-shared",
            createdAt: baseDate.addingTimeInterval(10)
        )
        let earliestVideo = Media(
            mediaId: "video-a",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-shared",
            createdAt: baseDate
        )
        let photoWithSharedAsset = Media(
            mediaId: "photo-a",
            mediaLibraryId: "library-1",
            kind: .photo,
            assetRefId: "asset-shared",
            createdAt: baseDate.addingTimeInterval(20)
        )
        let uniqueVideo = Media(
            mediaId: "video-c",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-unique",
            createdAt: baseDate.addingTimeInterval(30)
        )

        let deduplicated = Media.deduplicatedForImportPresentation([
            duplicateVideo,
            uniqueVideo,
            photoWithSharedAsset,
            earliestVideo
        ])

        #expect(deduplicated.map(\.mediaId) == ["video-a", "photo-a", "video-c"])
    }

    @Test func deduplicatedForImportPresentationBreaksTimestampTiesWithMediaId() {
        let createdAt = Date(timeIntervalSince1970: 1_700_000_100)
        let laterId = Media(
            mediaId: "video-z",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-shared",
            createdAt: createdAt
        )
        let earlierId = Media(
            mediaId: "video-a",
            mediaLibraryId: "library-1",
            kind: .video,
            assetRefId: "asset-shared",
            createdAt: createdAt
        )

        let deduplicated = Media.deduplicatedForImportPresentation([laterId, earlierId])

        #expect(deduplicated.map(\.mediaId) == ["video-a"])
    }
}
