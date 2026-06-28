import Testing
@testable import Iris_Main

struct EditorImportDestinationTests {
    @Test func libraryDestinationUpdatesMediaOnly() {
        #expect(EditorImportRequest.Destination.library.applicationMode == .libraryOnly)
    }

    @Test func timelineDestinationIngestsMediaForSelectedTrackKind() {
        #expect(EditorImportRequest.Destination.timeline(kind: .video).applicationMode == .timeline(kind: .video))
        #expect(EditorImportRequest.Destination.timeline(kind: .audio).applicationMode == .timeline(kind: .audio))
    }
}
