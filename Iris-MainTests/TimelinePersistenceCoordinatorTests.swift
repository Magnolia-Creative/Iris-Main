import XCTest
@testable import Iris_Main

@MainActor
final class TimelinePersistenceCoordinatorTests: XCTestCase {
    func testClipDiffDetectsAddedUpdatedAndDeletedClips() {
        let unchanged = makeClip(id: "unchanged", start: 0, end: 1_000_000)
        let updatedBefore = makeClip(id: "updated", start: 1_000_000, end: 2_000_000)
        let updatedAfter = makeClip(id: "updated", start: 1_500_000, end: 2_500_000)
        let deleted = makeClip(id: "deleted", start: 2_000_000, end: 3_000_000)
        let added = makeClip(id: "added", start: 3_000_000, end: 4_000_000)

        let diff = makeCoordinator().clipDiff(
            before: [unchanged, updatedBefore, deleted],
            after: [unchanged, updatedAfter, added]
        )

        XCTAssertEqual(diff.added.map(\.clipId).sorted(), ["added"])
        XCTAssertEqual(diff.updated.map(\.clipId).sorted(), ["updated"])
        XCTAssertEqual(diff.deletedIds.sorted(), ["deleted"])
    }

    func testEffectDiffDetectsCreatedUpdatedAndDeletedEffects() {
        let unchanged = makeColorEffect(id: "unchanged", temperature: 0.1)
        let updatedBefore = makeColorEffect(id: "updated", temperature: 0.2)
        let updatedAfter = makeColorEffect(id: "updated", temperature: 0.8)
        let deleted = makeColorEffect(id: "deleted", temperature: 0.3)
        let created = makeColorEffect(id: "created", temperature: 0.4)

        let diff = makeCoordinator().effectDiff(
            before: [unchanged, updatedBefore, deleted],
            after: [unchanged, updatedAfter, created]
        )

        XCTAssertEqual(diff.created.map(\.effectId).sorted(), ["created"])
        XCTAssertEqual(diff.updated.map(\.effectId).sorted(), ["updated"])
        XCTAssertEqual(diff.deletedIds.sorted(), ["deleted"])
    }

    func testCaptionCueDiffDetectsCreatedUpdatedAndDeletedCues() {
        let unchanged = makeCue(id: "unchanged", text: "same")
        let updatedBefore = makeCue(id: "updated", text: "before")
        let updatedAfter = makeCue(id: "updated", text: "after")
        let deleted = makeCue(id: "deleted", text: "removed")
        let created = makeCue(id: "created", text: "new")

        let diff = makeCoordinator().captionCueDiff(
            before: [unchanged, updatedBefore, deleted],
            after: [unchanged, updatedAfter, created]
        )

        XCTAssertEqual(diff.created.map(\.cueId).sorted(), ["created"])
        XCTAssertEqual(diff.updated.map(\.cueId).sorted(), ["updated"])
        XCTAssertEqual(diff.deletedIds.sorted(), ["deleted"])
    }

    private func makeCoordinator() -> TimelinePersistenceCoordinator {
        TimelinePersistenceCoordinator(persistence: TimelinePersistence(db: .shared))
    }

    private func makeClip(id: String, start: Int64, end: Int64) -> Clip {
        Clip(
            clipId: id,
            trackId: "track-video",
            mediaId: "media-video",
            sourceRange: TimeRange(start: start, end: end),
            timelineRange: TimeRange(start: start, end: end)
        )
    }

    private func makeColorEffect(id: String, temperature: Float) -> Effect {
        Effect.clipColorFilter(
            timelineId: "timeline-1",
            clipId: "clip-1",
            filter: ClipColorFilter(temperature: temperature),
            effectId: id
        )
    }

    private func makeCue(id: String, text: String) -> CaptionCue {
        CaptionCue(
            cueId: id,
            groupId: "group-1",
            text: text,
            timelineStartUs: 0,
            timelineEndUs: 1_000_000,
            sourceStartUs: 0,
            sourceEndUs: 1_000_000
        )
    }
}
