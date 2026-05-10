import Foundation

struct TimelineActionValidator {
    func validatedResult(
        _ result: TimelineCompileResult,
        context: TimelineCompilerContext
    ) -> TimelineCompileResult {
        guard result.actions.isEmpty == false else { return result }

        var validActions: [Action] = []
        var warnings = result.warnings

        for action in result.actions {
            let actionWarnings = validate(action, context: context)
            if actionWarnings.isEmpty {
                validActions.append(action)
            } else {
                warnings.append(contentsOf: actionWarnings)
            }
        }

        return TimelineCompileResult(
            actions: validActions,
            confidence: validActions.isEmpty ? 0 : result.confidence,
            source: result.source,
            unresolvedText: validActions.isEmpty ? (result.unresolvedText ?? "Invalid timeline action") : result.unresolvedText,
            warnings: uniqueWarnings(warnings),
            needsClarification: result.needsClarification || validActions.isEmpty
        )
    }

    func isExecutable(_ result: TimelineCompileResult, context: TimelineCompilerContext) -> Bool {
        guard result.actions.isEmpty == false, result.needsClarification == false else {
            return false
        }

        return result.actions.allSatisfy { validate($0, context: context).isEmpty }
    }
}

private extension TimelineActionValidator {
    func validate(_ action: Action, context: TimelineCompilerContext) -> [TimelineCompileWarning] {
        guard action.timelineId == context.timelineId else {
            return [.unsupportedAction]
        }

        switch action.payload {
        case .splitClip(let clipId, let atTimeUs):
            return validateSplit(clipId: clipId, atTimeUs: atTimeUs, context: context)
        case .removeClip(let clipId):
            return context.clipsById[clipId] == nil ? [.clipNotFound] : []
        case .addClip:
            return [.unsupportedAction]
        case .trimClip(let clipId, let sourceRange, let timelineRange):
            return validateTrim(
                clipId: clipId,
                sourceRange: sourceRange,
                timelineRange: timelineRange,
                context: context
            )
        case .moveClip(let clipId, let orderedClipIds):
            return validateMove(clipId: clipId, orderedClipIds: orderedClipIds, context: context)
        case .replaceTrackClips(let trackId, let clips):
            return validateReplaceTrackClips(trackId: trackId, clips: clips, context: context)
        }
    }

    func validateSplit(
        clipId: String,
        atTimeUs: Int64,
        context: TimelineCompilerContext
    ) -> [TimelineCompileWarning] {
        guard let clip = context.clipsById[clipId] else {
            return [.clipNotFound]
        }

        guard atTimeUs > clip.timelineRange.start, atTimeUs < clip.timelineRange.end else {
            return [.splitTimeOutsideClip]
        }

        return []
    }

    func validateTrim(
        clipId: String,
        sourceRange: TimeRange,
        timelineRange: TimeRange,
        context: TimelineCompilerContext
    ) -> [TimelineCompileWarning] {
        guard context.clipsById[clipId] != nil else {
            return [.clipNotFound]
        }

        guard sourceRange.duration > 0,
              timelineRange.duration > 0,
              sourceRange.duration == timelineRange.duration else {
            return [.invalidTrimRange]
        }

        return []
    }

    func validateMove(
        clipId: String,
        orderedClipIds: [String],
        context: TimelineCompilerContext
    ) -> [TimelineCompileWarning] {
        guard let clip = context.clipsById[clipId] else {
            return [.clipNotFound]
        }

        let existingOrder = context.orderedClipIds(for: clip)
        guard Set(existingOrder) == Set(orderedClipIds),
              existingOrder.count == orderedClipIds.count,
              Set(orderedClipIds).count == orderedClipIds.count else {
            return [.invalidMoveOrder]
        }

        return []
    }

    func validateReplaceTrackClips(
        trackId: String,
        clips: [Clip],
        context: TimelineCompilerContext
    ) -> [TimelineCompileWarning] {
        guard let existingClipIds = context.orderedClipIdsByTrackId[trackId] else {
            return [.trackNotFound]
        }

        let replacementClipIds = clips.map(\.clipId)
        guard Set(existingClipIds) == Set(replacementClipIds),
              existingClipIds.count == replacementClipIds.count,
              Set(replacementClipIds).count == replacementClipIds.count else {
            return [.invalidMoveOrder]
        }

        return []
    }

    func uniqueWarnings(_ warnings: [TimelineCompileWarning]) -> [TimelineCompileWarning] {
        var seen = Set<TimelineCompileWarning>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
