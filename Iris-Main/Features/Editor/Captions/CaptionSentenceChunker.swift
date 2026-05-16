import Foundation

struct CaptionChunk: Equatable {
    let text: String
    let startSec: Double
    let endSec: Double
}

enum CaptionSentenceChunker {
    static func chunk(
        sentenceText: String,
        sentenceStart: Double,
        sentenceEnd: Double,
        words: [RemoteCaptionWord]?,
        maxWords: Int = 6,
        maxDurationSec: Double = 2.0,
        pauseGapSec: Double = 0.35
    ) -> [CaptionChunk] {
        guard sentenceEnd > sentenceStart, maxWords > 0 else { return [] }

        if let words, !words.isEmpty, words.contains(where: { $0.start != 0 || $0.end != 0 }) {
            let chunks = chunkUsingWords(
                words: words,
                maxWords: maxWords,
                maxDurationSec: maxDurationSec,
                pauseGapSec: pauseGapSec
            )
            if !chunks.isEmpty {
                return chunks
            }
        }

        return chunkLinearly(
            sentenceText: sentenceText,
            sentenceStart: sentenceStart,
            sentenceEnd: sentenceEnd,
            maxWords: maxWords
        )
    }

    private static func chunkUsingWords(
        words: [RemoteCaptionWord],
        maxWords: Int,
        maxDurationSec: Double,
        pauseGapSec: Double
    ) -> [CaptionChunk] {
        let timedWords = words
            .filter { !$0.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.end > $0.start }
            .sorted { $0.start < $1.start }
        guard !timedWords.isEmpty else { return [] }

        var groups: [[RemoteCaptionWord]] = []
        var current: [RemoteCaptionWord] = []

        for index in timedWords.indices {
            let word = timedWords[index]
            current.append(word)

            let currentStart = current.first?.start ?? word.start
            let duration = word.end - currentStart
            let nextWord = timedWords.index(after: index) < timedWords.endIndex ? timedWords[timedWords.index(after: index)] : nil
            let nextGap = nextWord.map { $0.start - word.end } ?? 0
            let shouldBreak =
                current.count >= maxWords ||
                duration >= maxDurationSec ||
                (current.count >= 3 && endsSentence(word.word)) ||
                (nextWord != nil && nextGap > pauseGapSec)

            if shouldBreak {
                groups.append(current)
                current.removeAll(keepingCapacity: true)
            }
        }

        if !current.isEmpty {
            groups.append(current)
        }

        mergeTrailingSingleWordGroup(&groups)

        return groups.compactMap { group in
            guard let first = group.first, let last = group.last, last.end > first.start else { return nil }
            let text = group.map(\.word).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return CaptionChunk(text: text, startSec: first.start, endSec: last.end)
        }
    }

    private static func chunkLinearly(
        sentenceText: String,
        sentenceStart: Double,
        sentenceEnd: Double,
        maxWords: Int
    ) -> [CaptionChunk] {
        let tokens = sentenceText
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        guard !tokens.isEmpty else { return [] }

        let chunkCount = tokens.count <= maxWords + 1
            ? 1
            : Int(ceil(Double(tokens.count) / Double(maxWords)))
        let duration = sentenceEnd - sentenceStart

        var chunks: [CaptionChunk] = []
        var cursor = 0
        for chunkIndex in 0 ..< chunkCount {
            let remainingWords = tokens.count - cursor
            let remainingChunks = chunkCount - chunkIndex
            let count = Int(ceil(Double(remainingWords) / Double(remainingChunks)))
            let nextCursor = min(tokens.count, cursor + count)
            let text = tokens[cursor ..< nextCursor].joined(separator: " ")
            let start = sentenceStart + duration * Double(chunkIndex) / Double(chunkCount)
            let end = sentenceStart + duration * Double(chunkIndex + 1) / Double(chunkCount)
            if !text.isEmpty, end > start {
                chunks.append(CaptionChunk(text: text, startSec: start, endSec: end))
            }
            cursor = nextCursor
        }

        return chunks
    }

    private static func mergeTrailingSingleWordGroup(_ groups: inout [[RemoteCaptionWord]]) {
        guard groups.count >= 2, groups.last?.count == 1 else { return }
        let trailing = groups.removeLast()
        groups[groups.index(before: groups.endIndex)].append(contentsOf: trailing)
    }

    private static func endsSentence(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return false }
        return last == "." || last == "!" || last == "?"
    }
}
