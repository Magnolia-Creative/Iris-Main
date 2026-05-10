import Foundation

struct TimelineDeterministicCompiler {
    func compile(
        prompt: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult? {
        let normalized = TimelinePromptNormalizer.normalize(prompt)

        if isRemoveSelectedClipCommand(normalized) {
            return removeSelectedClip(prompt: prompt, context: context)
        }

        if isSplitInHalfCommand(normalized) {
            return splitSelectedClipInHalf(prompt: prompt, context: context)
        }

        if isSplitAtPlayheadCommand(normalized) {
            return splitSelectedClipAtPlayhead(prompt: prompt, context: context)
        }

        if isSplitAtExplicitTimeCommand(normalized), let timeUs = parseExplicitTimeUs(from: normalized) {
            return splitSelectedClip(prompt: prompt, context: context, atTimeUs: timeUs, confidence: 0.97)
        }

        if isTrimStartCommand(normalized) {
            return trimSelectedClipStart(prompt: prompt, normalized: normalized, context: context)
        }

        if isTrimEndCommand(normalized) {
            return trimSelectedClipEnd(prompt: prompt, normalized: normalized, context: context)
        }

        if isMoveToBeginningCommand(normalized) {
            return moveSelectedClip(prompt: prompt, context: context, placement: .beginning)
        }

        if isMoveToEndCommand(normalized) {
            return moveSelectedClip(prompt: prompt, context: context, placement: .end)
        }

        if isMoveBeforeAfterCommand(normalized) {
            return TimelineCompileResult(
                actions: [],
                confidence: 0.6,
                source: .deterministic,
                unresolvedText: prompt,
                warnings: [.ambiguousTarget],
                needsClarification: true
            )
        }

        return nil
    }
}

enum TimelinePromptNormalizer {
    static func normalize(_ prompt: String) -> String {
        prompt
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9:% ]", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension TimelineDeterministicCompiler {
    enum MovePlacement {
        case beginning
        case end
    }

    func isRemoveSelectedClipCommand(_ prompt: String) -> Bool {
        [
            "delete this clip",
            "remove this clip",
            "delete selected clip",
            "remove selected clip"
        ].contains(prompt)
    }

    func isSplitAtPlayheadCommand(_ prompt: String) -> Bool {
        [
            "split this clip",
            "split this clip at the playhead",
            "cut this clip at the playhead",
            "split at playhead",
            "split at the playhead",
            "cut at playhead",
            "cut at the playhead"
        ].contains(prompt)
    }

    func isSplitInHalfCommand(_ prompt: String) -> Bool {
        [
            "cut this clip in half",
            "split this clip in half",
            "split the selected clip in half",
            "cut the clip in half"
        ].contains(prompt)
    }

    func isSplitAtExplicitTimeCommand(_ prompt: String) -> Bool {
        (prompt.hasPrefix("split at ") || prompt.hasPrefix("cut at ") || prompt.hasPrefix("split this clip at "))
            && !prompt.contains("playhead")
    }

    func isTrimStartCommand(_ prompt: String) -> Bool {
        prompt.hasPrefix("trim the start")
            || prompt.hasPrefix("cut the first")
            || prompt.hasPrefix("remove the first")
            || prompt == "clip off the beginning"
            || prompt == "clip off the start"
    }

    func isTrimEndCommand(_ prompt: String) -> Bool {
        prompt.hasPrefix("trim the end")
            || prompt.hasPrefix("cut the last")
            || prompt.hasPrefix("remove the final")
            || prompt.hasPrefix("clip out the final")
    }

    func isMoveToBeginningCommand(_ prompt: String) -> Bool {
        prompt == "move this clip to the beginning"
            || prompt == "move this clip to the start"
            || prompt == "put this clip first"
    }

    func isMoveToEndCommand(_ prompt: String) -> Bool {
        prompt == "move this clip to the end"
            || prompt == "put this clip last"
    }

    func isMoveBeforeAfterCommand(_ prompt: String) -> Bool {
        prompt.hasPrefix("move this clip before ")
            || prompt.hasPrefix("move this clip after ")
    }

    func removeSelectedClip(
        prompt: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard let selectedClipId = context.selectedClipId else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }
        guard context.clipsById[selectedClipId] != nil else {
            return clarification(prompt: prompt, warnings: [.clipNotFound])
        }

        return TimelineCompileResult(
            actions: [
                Action.removeClip(timelineId: context.timelineId, clipId: selectedClipId)
            ],
            confidence: 0.98,
            source: .deterministic,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func splitSelectedClipAtPlayhead(
        prompt: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard let playheadTimeUs = context.playheadTimeUs else {
            return clarification(prompt: prompt, warnings: [.missingPlayhead])
        }

        return splitSelectedClip(prompt: prompt, context: context, atTimeUs: playheadTimeUs, confidence: 0.98)
    }

    func splitSelectedClipInHalf(
        prompt: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard let clip = context.selectedClip else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }

        let midpoint = clip.timelineRange.start + (clip.timelineRange.duration / 2)
        return splitSelectedClip(prompt: prompt, context: context, atTimeUs: midpoint, confidence: 0.98)
    }

    func splitSelectedClip(
        prompt: String,
        context: TimelineCompilerContext,
        atTimeUs: Int64,
        confidence: Double
    ) -> TimelineCompileResult {
        guard let selectedClipId = context.selectedClipId else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }
        guard let clip = context.clipsById[selectedClipId] else {
            return clarification(prompt: prompt, warnings: [.clipNotFound])
        }
        guard atTimeUs > clip.timelineRange.start, atTimeUs < clip.timelineRange.end else {
            return clarification(prompt: prompt, warnings: [.splitTimeOutsideClip])
        }

        return TimelineCompileResult(
            actions: [
                Action.splitClip(timelineId: context.timelineId, clipId: selectedClipId, atTimeUs: atTimeUs)
            ],
            confidence: confidence,
            source: .deterministic,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func trimSelectedClipStart(
        prompt: String,
        normalized: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard let clip = context.selectedClip else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }
        guard let durationUs = parseDurationUs(from: normalized) else {
            return clarification(prompt: prompt, warnings: [.invalidTrimRange])
        }
        guard durationUs > 0, durationUs < clip.timelineRange.duration else {
            return clarification(prompt: prompt, warnings: [.invalidTrimRange])
        }

        let sourceRange = TimeRange(start: clip.sourceRange.start + durationUs, end: clip.sourceRange.end)
        let timelineRange = TimeRange(start: clip.timelineRange.start + durationUs, end: clip.timelineRange.end)

        return trimResult(
            prompt: prompt,
            context: context,
            clip: clip,
            sourceRange: sourceRange,
            timelineRange: timelineRange
        )
    }

    func trimSelectedClipEnd(
        prompt: String,
        normalized: String,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard let clip = context.selectedClip else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }
        guard let durationUs = parseDurationUs(from: normalized) else {
            return clarification(prompt: prompt, warnings: [.invalidTrimRange])
        }
        guard durationUs > 0, durationUs < clip.timelineRange.duration else {
            return clarification(prompt: prompt, warnings: [.invalidTrimRange])
        }

        let sourceRange = TimeRange(start: clip.sourceRange.start, end: clip.sourceRange.end - durationUs)
        let timelineRange = TimeRange(start: clip.timelineRange.start, end: clip.timelineRange.end - durationUs)

        return trimResult(
            prompt: prompt,
            context: context,
            clip: clip,
            sourceRange: sourceRange,
            timelineRange: timelineRange
        )
    }

    func trimResult(
        prompt: String,
        context: TimelineCompilerContext,
        clip: Clip,
        sourceRange: TimeRange,
        timelineRange: TimeRange
    ) -> TimelineCompileResult {
        TimelineCompileResult(
            actions: [
                Action.trimClip(
                    timelineId: context.timelineId,
                    clipId: clip.clipId,
                    sourceRange: sourceRange,
                    timelineRange: timelineRange
                )
            ],
            confidence: 0.97,
            source: .deterministic,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func moveSelectedClip(
        prompt: String,
        context: TimelineCompilerContext,
        placement: MovePlacement
    ) -> TimelineCompileResult {
        guard let clip = context.selectedClip else {
            return clarification(prompt: prompt, warnings: [.missingSelectedClip])
        }

        let originalOrder = context.orderedClipIds(for: clip)
        guard originalOrder.contains(clip.clipId), !originalOrder.isEmpty else {
            return clarification(prompt: prompt, warnings: [.invalidMoveOrder])
        }

        var newOrder = originalOrder.filter { $0 != clip.clipId }
        switch placement {
        case .beginning:
            newOrder.insert(clip.clipId, at: 0)
        case .end:
            newOrder.append(clip.clipId)
        }

        return TimelineCompileResult(
            actions: [
                Action.moveClip(
                    timelineId: context.timelineId,
                    clipId: clip.clipId,
                    orderedClipIds: newOrder
                )
            ],
            confidence: 0.97,
            source: .deterministic,
            unresolvedText: nil,
            warnings: [],
            needsClarification: false
        )
    }

    func clarification(
        prompt: String,
        warnings: [TimelineCompileWarning]
    ) -> TimelineCompileResult {
        TimelineCompileResult(
            actions: [],
            confidence: 0,
            source: .deterministic,
            unresolvedText: prompt,
            warnings: warnings,
            needsClarification: true
        )
    }

    func parseDurationUs(from prompt: String) -> Int64? {
        guard let match = firstMatch(in: prompt, pattern: #"(\d+(?:\.\d+)?)\s*(seconds?|secs?|s)"#),
              let seconds = Double(match) else {
            return nil
        }
        return Int64(seconds * 1_000_000)
    }

    func parseExplicitTimeUs(from prompt: String) -> Int64? {
        let pattern = #"(?:split|cut)(?: this clip)? at (\d+(?::\d{1,2}){0,2})(?:\s*(?:seconds?|secs?|s))?"#
        guard let value = firstMatch(in: prompt, pattern: pattern, groupIndex: 1) else {
            return nil
        }

        let parts = value.split(separator: ":").compactMap { Int64($0) }
        guard parts.count == value.split(separator: ":").count else { return nil }

        let totalSeconds: Int64
        switch parts.count {
        case 1:
            totalSeconds = parts[0]
        case 2:
            totalSeconds = (parts[0] * 60) + parts[1]
        case 3:
            totalSeconds = (parts[0] * 3_600) + (parts[1] * 60) + parts[2]
        default:
            return nil
        }

        return totalSeconds * 1_000_000
    }

    func firstMatch(in text: String, pattern: String, groupIndex: Int = 1) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > groupIndex,
              let matchRange = Range(match.range(at: groupIndex), in: text) else {
            return nil
        }
        return String(text[matchRange])
    }
}
