import Foundation
import Testing
@testable import Iris_Main

struct BackendProjectCaptionLinkageTests {
    @Test func timelinePersistenceSurfacesSavedBackendProjectId() throws {
        let db = try DatabaseManager.makeInMemory()
        let fixture = try seedMinimalProjectAndTimeline(in: db)

        let before = try TimelinePersistence(db: db).loadTimelineData(timelineId: fixture.timelineId)
        #expect(before.backendProjectId == nil)

        try db.saveBackendProjectMapping(
            localProjectId: fixture.projectId,
            backendProjectId: "163",
            backendProjectName: "Remote"
        )

        let after = try TimelinePersistence(db: db).loadTimelineData(timelineId: fixture.timelineId)
        #expect(after.backendProjectId == "163")
    }

    @Test @MainActor
    func refreshBackendProjectMappingFromStoreRepairsMissingState() async throws {
        let db = try DatabaseManager.makeInMemory()
        let fixture = try seedMinimalProjectAndTimeline(in: db)
        let controller = TimelineController(timelineId: fixture.timelineId, db: db)
        await controller.loadTimelineData()
        #expect(controller.state.backendProjectId == nil)

        try db.saveBackendProjectMapping(
            localProjectId: fixture.projectId,
            backendProjectId: "163",
            backendProjectName: "Remote"
        )

        await controller.refreshBackendProjectMappingFromStoreIfNeeded()
        #expect(controller.state.backendProjectId == "163")
    }

    @Test func timelinePersistenceSurfacesSavedClipUploadLocalKey() throws {
        let db = try DatabaseManager.makeInMemory()
        let fixture = try seedMinimalProjectAndTimeline(in: db)
        let media = try seedVideoMediaOnTimeline(in: db, fixture: fixture, localKey: "upload-local-key")

        let loaded = try TimelinePersistence(db: db).loadTimelineData(timelineId: fixture.timelineId)

        #expect(loaded.mediaById[media.mediaId]?.spec.clipUploadLocalKey == "upload-local-key")
        #expect(loaded.clips.contains { $0.mediaId == media.mediaId })
    }

    @Test func updateMediaSpecMergesWithoutErasingCaptionMetadata() throws {
        let db = try DatabaseManager.makeInMemory()
        let fixture = try seedMinimalProjectAndTimeline(in: db)
        let media = try seedVideoMediaOnTimeline(in: db, fixture: fixture, localKey: "upload-local-key")

        _ = try #require(try db.updateMediaSpec(mediaId: media.mediaId) { spec in
            spec.transcriptID = "transcript-1"
            spec.transcriptFullText = "hello world"
            spec.transcriptSentences = [
                MediaTranscriptSentence(
                    text: "hello world",
                    startTimeSeconds: 0,
                    endTimeSeconds: 1,
                    confidence: 0.9,
                    speaker: nil,
                    channel: nil
                )
            ]
        })

        let thumbnailUpdated = try #require(try db.updateMediaSpec(mediaId: media.mediaId) { spec in
            spec.thumbnailStripPath = "thumbs/caption-upload.jpg"
            spec.thumbnailStripHeight = 72
            spec.thumbnailStripFrameCount = 12
        })

        #expect(thumbnailUpdated.spec.clipUploadLocalKey == "upload-local-key")
        #expect(thumbnailUpdated.spec.transcriptID == "transcript-1")
        #expect(thumbnailUpdated.spec.transcriptFullText == "hello world")
        #expect(thumbnailUpdated.spec.transcriptSentences?.count == 1)
        #expect(thumbnailUpdated.spec.thumbnailStripPath == "thumbs/caption-upload.jpg")

        let keyUpdated = try #require(try db.updateMediaSpec(mediaId: media.mediaId) { spec in
            spec.clipUploadLocalKey = "replacement-upload-key"
        })

        #expect(keyUpdated.spec.clipUploadLocalKey == "replacement-upload-key")
        #expect(keyUpdated.spec.transcriptID == "transcript-1")
        #expect(keyUpdated.spec.thumbnailStripFrameCount == 12)
    }
}

private struct CaptionLinkageFixture {
    let projectId: String
    let timelineId: String
    let mediaLibraryId: String
}

private func seedMinimalProjectAndTimeline(in db: DatabaseManager) throws -> CaptionLinkageFixture {
    let projectId = "proj-caption-backend-link"

    try db.create(Project(projectId: projectId, name: "Caption Backend"))
    let library = MediaLibrary(projectId: projectId)
    try db.create(library)
    let timeline = try db.createTimeline(forProjectId: projectId)
    return CaptionLinkageFixture(
        projectId: projectId,
        timelineId: timeline.timelineId,
        mediaLibraryId: library.mediaLibraryId
    )
}

@discardableResult
private func seedVideoMediaOnTimeline(
    in db: DatabaseManager,
    fixture: CaptionLinkageFixture,
    localKey: String
) throws -> Media {
    let assetReference = AssetReference(
        assetRefId: "asset-caption-upload",
        locationType: .local,
        uri: "file:///caption-upload.mp4"
    )
    try db.create(assetReference)

    var spec = MediaSpec()
    spec.duration = 10
    spec.width = 1920
    spec.height = 1080
    spec.clipUploadLocalKey = localKey
    let media = Media(
        mediaId: "media-caption-upload",
        mediaLibraryId: fixture.mediaLibraryId,
        kind: .video,
        assetRefId: assetReference.assetRefId,
        spec: spec
    )
    try db.create(media)

    let videoTrack = try db
        .ensureCoreTracks(forTimelineId: fixture.timelineId)
        .first { $0.kind == .video }
    let track = try #require(videoTrack)
    try db.create(Clip(
        clipId: "clip-caption-upload",
        trackId: track.trackId,
        mediaId: media.mediaId,
        sourceRange: TimeRange(start: 0, end: 10_000_000),
        timelineRange: TimeRange(start: 0, end: 10_000_000)
    ))

    return media
}
