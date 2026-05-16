import Testing
@testable import Iris_Main

struct CaptionSentenceChunkerTests {
    @Test func thirtyTimedWordsSplitIntoSixWordChunks() {
        let words = makeWords(count: 30)

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: words.map(\.word).joined(separator: " "),
            sentenceStart: 0,
            sentenceEnd: 30,
            words: words
        )

        #expect(chunks.count == 5)
        #expect(chunks.map { $0.text.split(separator: " ").count } == [6, 6, 6, 6, 6])
        assertMonotonic(chunks)
    }

    @Test func shortTimedSentenceStaysSingleChunk() {
        let words = makeWords(["one", "two", "three", "four"])

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: "one two three four",
            sentenceStart: 0,
            sentenceEnd: 1.6,
            words: words
        )

        #expect(chunks == [CaptionChunk(text: "one two three four", startSec: 0, endSec: 1.6)])
    }

    @Test func punctuationCanEndAChunk() {
        let words = makeWords(["Hello", "wide", "world.", "And", "then", "more"])

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: "Hello wide world. And then more",
            sentenceStart: 0,
            sentenceEnd: 2.4,
            words: words
        )

        #expect(chunks.map(\.text) == ["Hello wide world.", "And then more"])
    }

    @Test func pauseGapCanEndAChunk() {
        let words = [
            RemoteCaptionWord(word: "one", start: 0.0, end: 0.2),
            RemoteCaptionWord(word: "two", start: 0.3, end: 0.5),
            RemoteCaptionWord(word: "three", start: 0.6, end: 0.8),
            RemoteCaptionWord(word: "four", start: 1.3, end: 1.5),
            RemoteCaptionWord(word: "five", start: 1.6, end: 1.8),
        ]

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: "one two three four five",
            sentenceStart: 0,
            sentenceEnd: 1.8,
            words: words
        )

        #expect(chunks.map(\.text) == ["one two three", "four five"])
    }

    @Test func durationCapCanEndAChunkBeforeSixWords() {
        let words = [
            RemoteCaptionWord(word: "one", start: 0.0, end: 0.6),
            RemoteCaptionWord(word: "two", start: 0.7, end: 1.3),
            RemoteCaptionWord(word: "three", start: 1.4, end: 2.1),
            RemoteCaptionWord(word: "four", start: 2.2, end: 2.6),
            RemoteCaptionWord(word: "five", start: 2.7, end: 3.1),
        ]

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: "one two three four five",
            sentenceStart: 0,
            sentenceEnd: 3.1,
            words: words
        )

        #expect(chunks.map(\.text) == ["one two three", "four five"])
    }

    @Test func trailingSingleWordMergesIntoPreviousChunk() {
        let words = makeWords(["one", "two", "three", "four", "five", "six", "seven"])

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: "one two three four five six seven",
            sentenceStart: 0,
            sentenceEnd: 2.8,
            words: words
        )

        #expect(chunks.count == 1)
        #expect(chunks.first?.text == "one two three four five six seven")
    }

    @Test func missingWordsLinearlyInterpolatesChunks() {
        let sentence = "one two three four five six seven eight nine ten eleven twelve"

        let chunks = CaptionSentenceChunker.chunk(
            sentenceText: sentence,
            sentenceStart: 0,
            sentenceEnd: 6,
            words: nil
        )

        #expect(chunks.map(\.text) == [
            "one two three four five six",
            "seven eight nine ten eleven twelve",
        ])
        #expect(chunks.first?.startSec == 0)
        #expect(chunks.first?.endSec == 3)
        #expect(chunks.last?.startSec == 3)
        #expect(chunks.last?.endSec == 6)
    }
}

private func makeWords(count: Int) -> [RemoteCaptionWord] {
    (0 ..< count).map { index in
        RemoteCaptionWord(word: "w\(index + 1)", start: Double(index), end: Double(index) + 0.4)
    }
}

private func makeWords(_ tokens: [String]) -> [RemoteCaptionWord] {
    tokens.enumerated().map { index, token in
        let start = Double(index) * 0.4
        return RemoteCaptionWord(word: token, start: start, end: start + 0.2)
    }
}

private func assertMonotonic(_ chunks: [CaptionChunk]) {
    for pair in zip(chunks, chunks.dropFirst()) {
        #expect(pair.0.endSec <= pair.1.startSec)
        #expect(pair.0.endSec > pair.0.startSec)
        #expect(pair.1.endSec > pair.1.startSec)
    }
}
