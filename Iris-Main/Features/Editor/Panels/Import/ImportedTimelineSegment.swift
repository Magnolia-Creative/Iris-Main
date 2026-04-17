import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct ImportedTimelineSegment: Codable, Transferable {
    static let fallbackDurationUs: Int64 = 2_000_000

    let mediaId: String
    let startTimeUs: Int64
    let endTimeUs: Int64

    init(mediaId: String, startTimeUs: Int64, endTimeUs: Int64) {
        self.mediaId = mediaId
        self.startTimeUs = startTimeUs
        self.endTimeUs = endTimeUs
    }

    init(media: Media, fallbackDurationUs: Int64 = ImportedTimelineSegment.fallbackDurationUs) {
        let resolvedDurationUs: Int64
        if let seconds = media.spec.duration, seconds > 0 {
            resolvedDurationUs = max(1, Int64((seconds * 1_000_000).rounded()))
        } else {
            resolvedDurationUs = fallbackDurationUs
        }

        self.mediaId = media.mediaId
        self.startTimeUs = 0
        self.endTimeUs = resolvedDurationUs
    }

    var sourceRange: TimeRange {
        TimeRange(start: startTimeUs, end: endTimeUs)
    }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .importedTimelineSegment)
    }
}

private extension UTType {
    static let importedTimelineSegment = UTType(exportedAs: "com.iris.editor.imported-timeline-segment")
}

extension View {
    @ViewBuilder
    func draggableIfPresent<Preview: View>(
        _ item: ImportedTimelineSegment?,
        @ViewBuilder preview: () -> Preview
    ) -> some View {
        if let item {
            draggable(item, preview: preview)
        } else {
            self
        }
    }

    @ViewBuilder
    func matchedPreviewIfPresent(_ id: String?, in namespace: Namespace.ID?) -> some View {
        if let id, let namespace {
            matchedGeometryEffect(id: id, in: namespace)
        } else {
            self
        }
    }
}
