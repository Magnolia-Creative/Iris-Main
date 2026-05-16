import Foundation

struct ImportedTimelineSeed: Equatable {
    let sourceVideos: [SelectedVideoAsset]
    let segments: [ImportedTimelineSeedSegment]
    /// Iris backend project id string from ingest (`project_id`), for persisting `Project.backendProjectId` on the editor timeline.
    let backendProjectID: String?
    let backendProjectName: String?

    init(
        sourceVideos: [SelectedVideoAsset],
        segments: [ImportedTimelineSeedSegment],
        backendProjectID: String? = nil,
        backendProjectName: String? = nil
    ) {
        self.sourceVideos = sourceVideos
        self.segments = segments
        self.backendProjectID = backendProjectID
        self.backendProjectName = backendProjectName
    }
}

struct ImportedTimelineSeedSegment: Equatable, Identifiable {
    let sourceLocalKey: String
    let startTimeUs: Int64
    let endTimeUs: Int64

    var id: String {
        "\(sourceLocalKey)-\(startTimeUs)-\(endTimeUs)"
    }

    var sourceRange: TimeRange {
        TimeRange(start: startTimeUs, end: endTimeUs)
    }
}
