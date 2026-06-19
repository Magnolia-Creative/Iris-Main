import Foundation

enum EditorJITTimelineSelection {
    static func trackKind(
        for segmentId: String,
        in tracks: [TimelineTrackModel]
    ) -> TimelineTrackContentKind? {
        for track in tracks {
            if track.segments.contains(where: { $0.id == segmentId }) {
                return track.kind
            }
        }
        return nil
    }

    static func isClipSelection(_ segmentId: String, in tracks: [TimelineTrackModel]) -> Bool {
        switch trackKind(for: segmentId, in: tracks) {
        case .video, .audio:
            return true
        default:
            return false
        }
    }
}
