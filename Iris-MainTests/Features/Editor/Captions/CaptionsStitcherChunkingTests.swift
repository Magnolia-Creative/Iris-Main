import Foundation
import Testing
@testable import Iris_Main

struct CaptionsStitcherChunkingTests {
    @Test func longSentenceEmitsChunkedAnchoredCues() throws {
        let clip = Clip(
            clipId: "clip-a",
            trackId: "track-video",
            mediaId: "media-a",
            sourceRange: TimeRange(start: 0, end: 3_000_000),
            timelineRange: TimeRange(start: 0, end: 3_000_000)
        )
        let media = media(id: "media-a", localKey: "upload-a")
        let words = (0 ..< 12).map { index in
            wordJSON("w\(index + 1)", start: Double(index) * 0.25, end: Double(index) * 0.25 + 0.15)
        }.joined(separator: ",")
        let captions = try remoteCaptions(localKey: "upload-a", sentenceJSON: """
        {
            "text": "w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12",
            "start": 0.0,
            "end": 3.0,
            "words": [\(words)]
        }
        """)

        let cues = CaptionsStitcher.stitch(
            inputs: [.init(clip: clip, media: media, captions: captions)],
            rangeStartUs: 0,
            rangeEndUs: 3_000_000
        )

        #expect(cues.map(\.text) == [
            "w1 w2 w3 w4 w5 w6",
            "w7 w8 w9 w10 w11 w12",
        ])
        #expect(cues.allSatisfy { $0.clipId == "clip-a" })
        #expect(cues.map(\.sourceStartUs) == [0, 1_500_000])
        #expect(cues.map(\.sourceEndUs) == [1_400_000, 2_900_000])
        #expect(cues.map(\.timelineStartUs) == [0, 1_500_000])
        #expect(cues.map(\.timelineEndUs) == [1_400_000, 2_900_000])
        assertNonOverlapping(cues)
    }

    @Test func partialClipUsesTrimmedWordsForAnchors() throws {
        let clip = Clip(
            clipId: "clip-b",
            trackId: "track-video",
            mediaId: "media-b",
            sourceRange: TimeRange(start: 1_000_000, end: 2_000_000),
            timelineRange: TimeRange(start: 10_000_000, end: 11_000_000)
        )
        let media = media(id: "media-b", localKey: "upload-b")
        let words = [
            wordJSON("before", start: 0.2, end: 0.5),
            wordJSON("inside", start: 1.1, end: 1.3),
            wordJSON("window", start: 1.5, end: 1.7),
            wordJSON("after", start: 2.2, end: 2.4),
        ].joined(separator: ",")
        let captions = try remoteCaptions(localKey: "upload-b", sentenceJSON: """
        {
            "text": "before inside window after",
            "start": 0.0,
            "end": 3.0,
            "words": [\(words)]
        }
        """)

        let cues = CaptionsStitcher.stitch(
            inputs: [.init(clip: clip, media: media, captions: captions)],
            rangeStartUs: 10_000_000,
            rangeEndUs: 11_000_000
        )

        let cue = try #require(cues.first)
        #expect(cues.count == 1)
        #expect(cue.text == "inside window")
        #expect(cue.clipId == "clip-b")
        #expect(cue.sourceStartUs == 1_100_000)
        #expect(cue.sourceEndUs == 1_700_000)
        #expect(cue.timelineStartUs == 10_100_000)
        #expect(cue.timelineEndUs == 10_700_000)
    }
}

private func media(id: String, localKey: String) -> Media {
    var spec = MediaSpec()
    spec.clipUploadLocalKey = localKey
    return Media(
        mediaId: id,
        mediaLibraryId: "library",
        kind: .video,
        assetRefId: "asset-\(id)",
        spec: spec
    )
}

private func remoteCaptions(localKey: String, sentenceJSON: String) throws -> RemoteClipCaptions {
    let json = """
    {
        "project_id": 1,
        "local_key": "\(localKey)",
        "clip_id": 1,
        "transcript_id": 2,
        "processing_status": "completed",
        "full_text": "",
        "sentences": [\(sentenceJSON)],
        "meta": null
    }
    """
    return try JSONDecoder().decode(RemoteClipCaptions.self, from: Data(json.utf8))
}

private func wordJSON(_ word: String, start: Double, end: Double) -> String {
    #"{"word":"\#(word)","start":\#(start),"end":\#(end)}"#
}

private func assertNonOverlapping(_ cues: [CaptionCue]) {
    for pair in zip(cues, cues.dropFirst()) {
        #expect(pair.0.timelineEndUs <= pair.1.timelineStartUs)
        #expect(pair.0.timelineEndUs > pair.0.timelineStartUs)
        #expect(pair.1.timelineEndUs > pair.1.timelineStartUs)
    }
}
