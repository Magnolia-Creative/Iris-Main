import Foundation
import Testing
@testable import Iris_Main

struct ClipColorFilterTests {
    @Test @MainActor func filterClampsAndRoundTripsThroughEffectParameters() {
        let filter = ClipColorFilter(
            temperature: 2,
            tint: -2,
            exposure: 8,
            brightness: 0.25,
            saturation: -0.5
        )

        #expect(filter.temperature == 1)
        #expect(filter.tint == -1)
        #expect(filter.exposure == 4)
        #expect(filter.brightness == 0.25)
        #expect(filter.saturation == -0.5)

        let effect = Effect.clipColorFilter(
            timelineId: "timeline-a",
            clipId: "clip-a",
            filter: filter
        )

        #expect(effect.type == ClipColorFilter.effectType)
        #expect(effect.appliesTo == .clip)
        #expect(effect.targetId == "clip-a")
        #expect(effect.clipColorFilter == filter)
    }

    @Test @MainActor func controllerPersistsAndResetsClipColorFilter() async throws {
        let db = try DatabaseManager.makeInMemory()
        let ids = try seedTimeline(in: db)
        let controller = TimelineController(timelineId: ids.timelineId, db: db)
        await controller.loadTimelineData()

        let filter = ClipColorFilter(
            temperature: 0.3,
            tint: -0.2,
            exposure: 1.25,
            brightness: 0.1,
            saturation: 0.4
        )

        controller.setClipColorFilter(clipId: ids.clipId, filter: filter)

        #expect(controller.clipColorFilter(for: ids.clipId) == filter)
        #expect(controller.state.effects.count == 1)

        let reloadedController = TimelineController(timelineId: ids.timelineId, db: db)
        await reloadedController.loadTimelineData()

        #expect(reloadedController.clipColorFilter(for: ids.clipId) == filter)

        reloadedController.resetClipColorFilter(clipId: ids.clipId)
        #expect(reloadedController.clipColorFilter(for: ids.clipId) == .neutral)
        #expect(reloadedController.state.effects.isEmpty)

        let resetController = TimelineController(timelineId: ids.timelineId, db: db)
        await resetController.loadTimelineData()
        #expect(resetController.clipColorFilter(for: ids.clipId) == .neutral)
    }

    @Test @MainActor func undoRedoRoundTripsClipColorFilter() async throws {
        let db = try DatabaseManager.makeInMemory()
        let ids = try seedTimeline(in: db)
        let controller = TimelineController(timelineId: ids.timelineId, db: db)
        await controller.loadTimelineData()

        let filter = ClipColorFilter(
            temperature: 0.3,
            tint: -0.2,
            exposure: 1.25,
            brightness: 0.1,
            saturation: 0.4
        )

        #expect(controller.canUndo == false)
        #expect(controller.canRedo == false)

        controller.setClipColorFilter(clipId: ids.clipId, filter: filter)
        #expect(controller.clipColorFilter(for: ids.clipId) == filter)
        #expect(controller.canUndo == true)
        #expect(controller.canRedo == false)

        controller.undoLastActionGroup()
        #expect(controller.clipColorFilter(for: ids.clipId) == .neutral)
        #expect(controller.state.effects.isEmpty)
        #expect(controller.canUndo == false)
        #expect(controller.canRedo == true)

        controller.redoLastActionGroup()
        #expect(controller.clipColorFilter(for: ids.clipId) == filter)
        #expect(controller.state.effects.count == 1)
        #expect(controller.canUndo == true)
        #expect(controller.canRedo == false)
    }
}

private struct SeededTimelineIds {
    let timelineId: String
    let clipId: String
}

private func seedTimeline(in db: DatabaseManager) throws -> SeededTimelineIds {
    let projectId = "project-filter-tests"
    let mediaLibraryId = "library-filter-tests"
    let assetRefId = "asset-filter-tests"
    let mediaId = "media-filter-tests"
    let timelineId = "timeline-filter-tests"
    let trackId = "track-filter-tests"
    let clipId = "clip-filter-tests"

    try db.create(Project(projectId: projectId, name: "Filter Tests"))
    try db.create(MediaLibrary(mediaLibraryId: mediaLibraryId, projectId: projectId))
    try db.create(AssetReference(assetRefId: assetRefId, locationType: .local, uri: "/tmp/filter-tests.mov"))
    try db.create(Media(
        mediaId: mediaId,
        mediaLibraryId: mediaLibraryId,
        kind: .video,
        assetRefId: assetRefId,
        spec: MediaSpec(duration: 2)
    ))
    try db.create(Timeline(timelineId: timelineId, projectId: projectId))
    try db.create(Track(trackId: trackId, timelineId: timelineId, kind: .video))
    try db.create(Clip(
        clipId: clipId,
        trackId: trackId,
        mediaId: mediaId,
        sourceRange: TimeRange(start: 0, end: 2_000_000),
        timelineRange: TimeRange(start: 0, end: 2_000_000)
    ))

    return SeededTimelineIds(timelineId: timelineId, clipId: clipId)
}
