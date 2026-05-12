import Foundation

struct IntentActionValidator {
    func validatedResult(
        _ result: IntentCompileResult,
        context: IntentCompilerContext
    ) -> IntentCompileResult {
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

        return IntentCompileResult(
            actions: validActions,
            confidence: validActions.isEmpty ? 0 : result.confidence,
            source: result.source,
            unresolvedText: validActions.isEmpty ? (result.unresolvedText ?? "Invalid timeline action") : result.unresolvedText,
            warnings: uniqueWarnings(warnings),
            needsClarification: result.needsClarification || validActions.isEmpty,
            experimentalEffectOperations: result.experimentalEffectOperations
        )
    }

    func isExecutable(_ result: IntentCompileResult, context: IntentCompilerContext) -> Bool {
        guard result.actions.isEmpty == false, result.needsClarification == false else {
            return false
        }

        return result.actions.allSatisfy { validate($0, context: context).isEmpty }
    }
}

private extension IntentActionValidator {
    func validate(_ action: Action, context: IntentCompilerContext) -> [IntentCompileWarning] {
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
        case .trimClip(let clipId, let sourceRange):
            return validateTrim(
                clipId: clipId,
                sourceRange: sourceRange,
                context: context
            )
        case .removeClipRanges(let clipId, let sourceRanges):
            return validateRemoveClipRanges(
                clipId: clipId,
                sourceRanges: sourceRanges,
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
        context: IntentCompilerContext
    ) -> [IntentCompileWarning] {
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
        context: IntentCompilerContext
    ) -> [IntentCompileWarning] {
        guard context.clipsById[clipId] != nil else {
            return [.clipNotFound]
        }

        guard sourceRange.duration > 0 else {
            return [.invalidTrimRange]
        }

        return []
    }

    func validateRemoveClipRanges(
        clipId: String,
        sourceRanges: [TimeRange],
        context: IntentCompilerContext
    ) -> [IntentCompileWarning] {
        guard let clip = context.clipsById[clipId] else {
            return [.clipNotFound]
        }

        guard sourceRanges.isEmpty == false else {
            return [.invalidRemoveRange]
        }

        var previousEnd: Int64?
        for range in sourceRanges.sorted(by: { $0.start == $1.start ? $0.end < $1.end : $0.start < $1.start }) {
            guard range.duration > 0,
                  range.start >= clip.sourceRange.start,
                  range.end <= clip.sourceRange.end else {
                return [.invalidRemoveRange]
            }
            if let previousEnd, range.start < previousEnd {
                return [.invalidRemoveRange]
            }
            previousEnd = range.end
        }

        return []
    }

    func validateMove(
        clipId: String,
        orderedClipIds: [String],
        context: IntentCompilerContext
    ) -> [IntentCompileWarning] {
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
        context: IntentCompilerContext
    ) -> [IntentCompileWarning] {
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

    func uniqueWarnings(_ warnings: [IntentCompileWarning]) -> [IntentCompileWarning] {
        var seen = Set<IntentCompileWarning>()
        return warnings.filter { seen.insert($0).inserted }
    }
}
