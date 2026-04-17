import Foundation

struct ImportedTimelineSeed: Equatable {
    let sourceVideos: [SelectedVideoAsset]
    let segments: [ImportedTimelineSeedSegment]
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
