import Foundation

/// Maps backend transcript sentences (source time in seconds) onto timeline µs for trimmed clips.
enum CaptionsStitcher {
    struct ClipTranscriptInput: Sendable {
        let clip: Clip
        let media: Media
        let captions: RemoteClipCaptions
    }

    /// Builds caption cues for the given timeline range from stitched remote transcripts.
    static func stitch(
        inputs: [ClipTranscriptInput],
        rangeStartUs: Int64,
        rangeEndUs: Int64
    ) -> [CaptionCue] {
        guard rangeEndUs > rangeStartUs else { return [] }

        var cues: [CaptionCue] = []

        for item in inputs {
            guard let localKey = item.media.spec.clipUploadLocalKey, !localKey.isEmpty else { continue }
            guard item.captions.localKey == localKey else { continue }

            let t0 = item.clip.timelineRange.start
            let t1 = item.clip.timelineRange.end
            let s0 = item.clip.sourceRange.start
            let s1 = item.clip.sourceRange.end
            let timelineDur = Double(t1 - t0)
            let sourceDur = Double(s1 - s0)
            guard timelineDur > 0, sourceDur > 0 else { continue }

            let intersectStart = max(rangeStartUs, t0)
            let intersectEnd = min(rangeEndUs, t1)
            guard intersectEnd > intersectStart else { continue }

            let srcStartUs = s0 + Int64(Double(intersectStart - t0) * sourceDur / timelineDur)
            let srcEndUs = s0 + Int64(Double(intersectEnd - t0) * sourceDur / timelineDur)
            let windowStartSec = Double(srcStartUs) / 1_000_000.0
            let windowEndSec = Double(srcEndUs) / 1_000_000.0

            for sentence in item.captions.sentences {
                let ss = sentence.start
                let se = sentence.end
                guard se > ss else { continue }

                let fullyInside = ss >= windowStartSec - 1e-6 && se <= windowEndSec + 1e-6
                let overlaps = ss < windowEndSec && se > windowStartSec
                guard overlaps else { continue }

                if fullyInside {
                    appendChunks(
                        sentenceText: sentence.text,
                        sourceStartSec: ss,
                        sourceEndSec: se,
                        words: sentence.words,
                        clip: item.clip,
                        t0: t0,
                        s0: s0,
                        timelineDur: timelineDur,
                        sourceDur: sourceDur,
                        clampRange: rangeStartUs...rangeEndUs,
                        cues: &cues
                    )
                    continue
                }

                if let words = sentence.words, !words.isEmpty {
                    let trimmed = wordsTrimmedToSourceWindow(words: words, windowStart: windowStartSec, windowEnd: windowEndSec)
                    guard !trimmed.isEmpty else { continue }
                    let wStart = trimmed.first!.start
                    let wEnd = trimmed.last!.end
                    appendChunks(
                        sentenceText: trimmed.map(\.word).joined(separator: " "),
                        sourceStartSec: wStart,
                        sourceEndSec: wEnd,
                        words: trimmed,
                        clip: item.clip,
                        t0: t0,
                        s0: s0,
                        timelineDur: timelineDur,
                        sourceDur: sourceDur,
                        clampRange: rangeStartUs...rangeEndUs,
                        cues: &cues
                    )
                } else {
                    let clampedStart = max(ss, windowStartSec)
                    let clampedEnd = min(se, windowEndSec)
                    guard clampedEnd > clampedStart else { continue }
                    appendChunks(
                        sentenceText: sentence.text,
                        sourceStartSec: clampedStart,
                        sourceEndSec: clampedEnd,
                        words: nil,
                        clip: item.clip,
                        t0: t0,
                        s0: s0,
                        timelineDur: timelineDur,
                        sourceDur: sourceDur,
                        clampRange: rangeStartUs...rangeEndUs,
                        cues: &cues
                    )
                }
            }
        }

        cues.sort { $0.timelineStartUs < $1.timelineStartUs }
        return cues
    }

    private static func wordsTrimmedToSourceWindow(
        words: [RemoteCaptionWord],
        windowStart: Double,
        windowEnd: Double
    ) -> [RemoteCaptionWord] {
        words.filter { $0.end > windowStart && $0.start < windowEnd }
    }

    private static func appendChunks(
        sentenceText: String,
        sourceStartSec: Double,
        sourceEndSec: Double,
        words: [RemoteCaptionWord]?,
        clip: Clip,
        t0: Int64,
        s0: Int64,
        timelineDur: Double,
        sourceDur: Double,
        clampRange: ClosedRange<Int64>,
        cues: inout [CaptionCue]
    ) {
        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: sentenceText,
            sentenceStart: sourceStartSec,
            sentenceEnd: sourceEndSec,
            words: words
        )

        for chunk in chunks {
            if let cue = cueForChunk(
                text: chunk.text,
                sourceStartSec: chunk.startSec,
                sourceEndSec: chunk.endSec,
                clip: clip,
                t0: t0,
                s0: s0,
                timelineDur: timelineDur,
                sourceDur: sourceDur,
                clampRange: clampRange
            ) {
                cues.append(cue)
            }
        }
    }

    private static func cueForChunk(
        text: String,
        sourceStartSec: Double,
        sourceEndSec: Double,
        clip: Clip,
        t0: Int64,
        s0: Int64,
        timelineDur: Double,
        sourceDur: Double,
        clampRange: ClosedRange<Int64>
    ) -> CaptionCue? {
        let srcStartUs = Int64(sourceStartSec * 1_000_000.0)
        let srcEndUs = Int64(sourceEndSec * 1_000_000.0)
        let timelineStart = t0 + Int64(Double(srcStartUs - s0) * timelineDur / sourceDur)
        let timelineEnd = t0 + Int64(Double(srcEndUs - s0) * timelineDur / sourceDur)
        guard timelineEnd > timelineStart else { return nil }

        let clippedStart = max(timelineStart, clampRange.lowerBound)
        let clippedEnd = min(timelineEnd, clampRange.upperBound)
        guard clippedEnd > clippedStart else { return nil }

        return CaptionCue(
            groupId: "",
            clipId: clip.clipId,
            text: text,
            timelineStartUs: clippedStart,
            timelineEndUs: clippedEnd,
            sourceStartUs: srcStartUs,
            sourceEndUs: srcEndUs
        )
    }
}
