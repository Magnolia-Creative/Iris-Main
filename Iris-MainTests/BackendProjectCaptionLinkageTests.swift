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
}

private struct CaptionLinkageFixture {
    let projectId: String
    let timelineId: String
}

private func seedMinimalProjectAndTimeline(in db: DatabaseManager) throws -> CaptionLinkageFixture {
    let projectId = "proj-caption-backend-link"

    try db.create(Project(projectId: projectId, name: "Caption Backend"))
    try db.create(MediaLibrary(projectId: projectId))
    let timeline = try db.createTimeline(forProjectId: projectId)
    return CaptionLinkageFixture(projectId: projectId, timelineId: timeline.timelineId)
}
