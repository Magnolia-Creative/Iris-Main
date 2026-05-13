import Foundation
import Testing
@testable import Iris_Main

struct SemanticUploadFrameSamplingTests {
    @Test func chunkTimeWindowsMatchesShortClip() {
        let windows = SemanticUploadFrameSampling.chunkTimeWindows(durationSeconds: 2.0)
        #expect(windows.count == 1)
        #expect(windows[0].start == 0)
        #expect(windows[0].end == 2)
        #expect(windows[0].center == 1)
    }

    @Test func chunkTimeWindowsTenSecondsHasStride() {
        let windows = SemanticUploadFrameSampling.chunkTimeWindows(durationSeconds: 10.0)
        #expect(windows.count >= 2)
        #expect(windows[0].start == 0)
        if windows.count > 1 {
            #expect(abs(windows[1].start - SemanticSearchConstants.chunkStrideSeconds) < 0.001)
        }
    }

    @Test func safeFormFilenameTokenSanitizes() {
        let t = SemanticUploadFrameSampling.safeFormFilenameToken(from: "a/b:c")
        #expect(!t.contains("/"))
        #expect(!t.contains(":"))
    }
}
