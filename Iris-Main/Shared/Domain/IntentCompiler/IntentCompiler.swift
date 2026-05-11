import Foundation

struct IntentCompiler {
    func compile(
        _ plan: SemanticEditPlan,
        originalPrompt: String,
        context: IntentCompilerContext
    ) -> IntentCompileResult {
        if plan.needsClarification {
            return clarification(
                originalPrompt: originalPrompt,
                question: plan.clarificationQuestion,
                warnings: [.ambiguousTarget]
            )
        }

        var simulator = IntentTimelineSimulator(context: context)
        var previousClipId: String?
        var previousTrackId: String?
        var actions: [Action] = []
        var confidences: [Double] = []
        var warnings: [IntentCompileWarning] = []

        for operation in plan.operations {
            let resolved: IntentResolutionResult
            switch operation.type {
            case .splitClip:
                resolved = resolveSplit(operation, context: context, simulator: simulator, previousClipId: previousClipId)
            case .removeClip:
                resolved = resolveRemove(operation, context: context, simulator: simulator, previousClipId: previousClipId)
            case .trimClip:
                resolved = resolveTrim(operation, context: context, simulator: simulator, previousClipId: previousClipId)
            case .moveClip:
                resolved = resolveMove(operation, context: context, simulator: simulator, previousClipId: previousClipId)
            case .replaceTrackClips:
                resolved = resolveReplaceTrackClips(operation, context: context, simulator: simulator, previousTrackId: previousTrackId)
            case .unknown:
                warnings.append(.unsupportedIntent)
                continue
            }

            switch resolved {
            case .success(let resolvedOperation):
                guard let action = makeAction(from: resolvedOperation, context: context) else {
                    warnings.append(.unsupportedIntent)
                    continue
                }
                actions.append(action)
                confidences.append(operation.confidence)
                simulator.apply(resolvedOperation)
                previousClipId = resolvedOperation.targetClipId ?? previousClipId
                previousTrackId = resolvedOperation.targetTrackId ?? previousTrackId
            case .clarification(let warning, let question):
                return clarification(originalPrompt: originalPrompt, question: question, warnings: [warning])
            case .unsupported:
                warnings.append(.unsupportedIntent)
            }
        }

        if actions.isEmpty {
            return IntentCompileResult(
                actions: [],
                confidence: 0,
                source: .llm,
                unresolvedText: originalPrompt,
                warnings: warnings.isEmpty ? [.noActionProduced] : uniqueWarnings(warnings),
                needsClarification: false
            )
        }

        let confidence = confidences.reduce(0, +) / Double(confidences.count)
        return IntentCompileResult(
            actions: actions,
            confidence: confidence,
            source: .llm,
            unresolvedText: nil,
            warnings: uniqueWarnings(warnings),
            needsClarification: false
        )
    }
}

private enum IntentResolutionResult {
    case success(ResolvedIntentOperation)
    case clarification(IntentCompileWarning, String)
    case unsupported
}

private struct ResolvedIntentOperation {
    let type: IntentEditType
    let sourceText: String
    let targetClipId: String?
    let targetTrackId: String?
    let confidence: Double
    let parameters: ResolvedIntentParameters
}

private enum ResolvedIntentParameters {
    case splitClip(atTimeUs: Int64)
    case removeClip
    case trimClip(sourceRange: TimeRange, timelineRange: TimeRange)
    case moveClip(orderedClipIds: [String])
    case replaceTrackClips(clips: [Clip])
}

private extension IntentCompiler {
    func resolveSplit(
        _ operation: SemanticEditOperation,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousClipId: String?
    ) -> IntentResolutionResult {
        guard let clip = resolveClip(operation.target, context: context, simulator: simulator, previousClipId: previousClipId) else {
            return .clarification(.missingSelectedClip, "Which clip do you want to split?")
        }

        guard let positionValue = operation.parameters["position"],
              let position = timeExpression(from: positionValue) else {
            return .clarification(.missingPlayhead, "Where do you want to split the clip?")
        }

        guard let atTimeUs = resolveTimeUs(position, clip: clip, context: context) else {
            return .clarification(.missingPlayhead, "Where do you want to split the clip?")
        }

        guard atTimeUs > clip.timelineRange.start, atTimeUs < clip.timelineRange.end else {
            return .clarification(.splitTimeOutsideClip, "The split point is outside the clip. Where should I split it?")
        }

        return .success(
            ResolvedIntentOperation(
                type: .splitClip,
                sourceText: operation.sourceText,
                targetClipId: clip.clipId,
                targetTrackId: nil,
                confidence: operation.confidence,
                parameters: .splitClip(atTimeUs: atTimeUs)
            )
        )
    }

    func resolveRemove(
        _ operation: SemanticEditOperation,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousClipId: String?
    ) -> IntentResolutionResult {
        guard let clip = resolveClip(operation.target, context: context, simulator: simulator, previousClipId: previousClipId) else {
            return .clarification(.missingSelectedClip, "Which clip do you want to delete?")
        }

        return .success(
            ResolvedIntentOperation(
                type: .removeClip,
                sourceText: operation.sourceText,
                targetClipId: clip.clipId,
                targetTrackId: nil,
                confidence: operation.confidence,
                parameters: .removeClip
            )
        )
    }

    func resolveTrim(
        _ operation: SemanticEditOperation,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousClipId: String?
    ) -> IntentResolutionResult {
        guard let clip = resolveClip(operation.target, context: context, simulator: simulator, previousClipId: previousClipId) else {
            return .clarification(.missingSelectedClip, "Which clip do you want to trim?")
        }
        guard let edge = operation.parameters["edge"]?.stringValue?.lowercased() else {
            return .clarification(.invalidTrimRange, "Should I trim the start or end of the clip?")
        }
        guard let amountValue = operation.parameters["amount"],
              let duration = durationExpression(from: amountValue),
              let durationUs = resolveDurationUs(duration, clip: clip) else {
            return .clarification(.invalidTrimRange, "How much do you want to trim?")
        }
        guard durationUs > 0, durationUs < clip.timelineRange.duration else {
            return .clarification(.invalidTrimRange, "This trim would remove the whole clip. How much do you want to trim?")
        }

        let sourceRange: TimeRange
        let timelineRange: TimeRange
        if edge == "start" || edge == "beginning" {
            sourceRange = TimeRange(start: clip.sourceRange.start + durationUs, end: clip.sourceRange.end)
            timelineRange = TimeRange(start: clip.timelineRange.start + durationUs, end: clip.timelineRange.end)
        } else if edge == "end" || edge == "final" {
            sourceRange = TimeRange(start: clip.sourceRange.start, end: clip.sourceRange.end - durationUs)
            timelineRange = TimeRange(start: clip.timelineRange.start, end: clip.timelineRange.end - durationUs)
        } else {
            return .clarification(.invalidTrimRange, "Should I trim the start or end of the clip?")
        }

        return .success(
            ResolvedIntentOperation(
                type: .trimClip,
                sourceText: operation.sourceText,
                targetClipId: clip.clipId,
                targetTrackId: nil,
                confidence: operation.confidence,
                parameters: .trimClip(sourceRange: sourceRange, timelineRange: timelineRange)
            )
        )
    }

    func resolveMove(
        _ operation: SemanticEditOperation,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousClipId: String?
    ) -> IntentResolutionResult {
        guard let clip = resolveClip(operation.target, context: context, simulator: simulator, previousClipId: previousClipId) else {
            return .clarification(.missingSelectedClip, "Which clip do you want to move?")
        }
        let originalOrder = simulator.orderedClipIds(for: clip.trackId)
        guard originalOrder.contains(clip.clipId) else {
            return .clarification(.invalidMoveOrder, "Where should this clip move?")
        }

        let orderedClipIds: [String]
        if let orderedValue = operation.parameters["orderedClipIds"],
           case .array(let values) = orderedValue {
            orderedClipIds = values.compactMap(\.stringValue)
        } else if let placement = operation.parameters["placement"]?.stringValue?.lowercased() {
            var newOrder = originalOrder.filter { $0 != clip.clipId }
            if placement == "beginning" || placement == "start" || placement == "first" {
                newOrder.insert(clip.clipId, at: 0)
            } else if placement == "end" || placement == "last" {
                newOrder.append(clip.clipId)
            } else {
                return .clarification(.ambiguousTarget, "Where should this clip move?")
            }
            orderedClipIds = newOrder
        } else {
            return .clarification(.ambiguousTarget, "Where should this clip move?")
        }

        guard Set(originalOrder) == Set(orderedClipIds),
              originalOrder.count == orderedClipIds.count,
              Set(orderedClipIds).count == orderedClipIds.count else {
            return .clarification(.invalidMoveOrder, "The requested clip order is not valid.")
        }

        return .success(
            ResolvedIntentOperation(
                type: .moveClip,
                sourceText: operation.sourceText,
                targetClipId: clip.clipId,
                targetTrackId: nil,
                confidence: operation.confidence,
                parameters: .moveClip(orderedClipIds: orderedClipIds)
            )
        )
    }

    func resolveReplaceTrackClips(
        _ operation: SemanticEditOperation,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousTrackId: String?
    ) -> IntentResolutionResult {
        guard let trackId = resolveTrackId(operation.target, context: context, previousTrackId: previousTrackId) else {
            return .clarification(.missingSelectedTrack, "Which track do you want to reorder?")
        }
        guard let orderedValue = operation.parameters["orderedClipIds"],
              case .array(let values) = orderedValue else {
            return .clarification(.invalidMoveOrder, "What clip order should I use?")
        }

        let orderedClipIds = values.compactMap(\.stringValue)
        let existingOrder = simulator.orderedClipIds(for: trackId)
        guard Set(existingOrder) == Set(orderedClipIds),
              existingOrder.count == orderedClipIds.count,
              Set(orderedClipIds).count == orderedClipIds.count else {
            return .clarification(.invalidMoveOrder, "The requested clip order is not valid.")
        }

        let clips = orderedClipIds.compactMap { simulator.clip(withId: $0) }
        guard clips.count == orderedClipIds.count else {
            return .clarification(.clipNotFound, "One of those clips is not available.")
        }

        return .success(
            ResolvedIntentOperation(
                type: .replaceTrackClips,
                sourceText: operation.sourceText,
                targetClipId: nil,
                targetTrackId: trackId,
                confidence: operation.confidence,
                parameters: .replaceTrackClips(clips: clips)
            )
        )
    }

    func makeAction(from operation: ResolvedIntentOperation, context: IntentCompilerContext) -> Action? {
        switch operation.parameters {
        case .splitClip(let atTimeUs):
            guard let clipId = operation.targetClipId else { return nil }
            return Action.splitClip(timelineId: context.timelineId, clipId: clipId, atTimeUs: atTimeUs)
        case .removeClip:
            guard let clipId = operation.targetClipId else { return nil }
            return Action.removeClip(timelineId: context.timelineId, clipId: clipId)
        case .trimClip(let sourceRange, let timelineRange):
            guard let clipId = operation.targetClipId else { return nil }
            return Action.trimClip(timelineId: context.timelineId, clipId: clipId, sourceRange: sourceRange, timelineRange: timelineRange)
        case .moveClip(let orderedClipIds):
            guard let clipId = operation.targetClipId else { return nil }
            return Action.moveClip(timelineId: context.timelineId, clipId: clipId, orderedClipIds: orderedClipIds)
        case .replaceTrackClips(let clips):
            guard let trackId = operation.targetTrackId else { return nil }
            return Action.replaceTrackClips(timelineId: context.timelineId, trackId: trackId, clips: clips)
        }
    }

    func clarification(
        originalPrompt: String,
        question: String?,
        warnings: [IntentCompileWarning]
    ) -> IntentCompileResult {
        IntentCompileResult(
            actions: [],
            confidence: 0,
            source: .llm,
            unresolvedText: question ?? originalPrompt,
            warnings: warnings,
            needsClarification: true
        )
    }

    func uniqueWarnings(_ warnings: [IntentCompileWarning]) -> [IntentCompileWarning] {
        var seen = Set<IntentCompileWarning>()
        return warnings.filter { seen.insert($0).inserted }
    }
}

private extension IntentCompiler {
    func resolveClip(
        _ target: SemanticEditTarget?,
        context: IntentCompilerContext,
        simulator: IntentTimelineSimulator,
        previousClipId: String?
    ) -> Clip? {
        guard let target else {
            return context.selectedClipId.flatMap { simulator.clip(withId: $0) }
        }
        guard case .clip(let reference) = target else { return nil }

        switch reference.type {
        case .selectedClip:
            return context.selectedClipId.flatMap { simulator.clip(withId: $0) }
        case .clipId:
            return reference.clipId.flatMap { simulator.clip(withId: $0) }
        case .sameAsPrevious:
            return previousClipId.flatMap { simulator.clip(withId: $0) }
        case .ordinal:
            guard let trackId = resolveTrackId(reference.track, context: context) ?? context.selectedTrackId else { return nil }
            let ordered = simulator.orderedClipIds(for: trackId)
            let index: Int?
            switch reference.value?.lowercased() {
            case "first":
                index = 0
            case "second":
                index = 1
            case "third":
                index = 2
            case "last":
                index = ordered.indices.last
            default:
                index = nil
            }
            guard let index, ordered.indices.contains(index) else { return nil }
            return simulator.clip(withId: ordered[index])
        case .currentClipAtPlayhead:
            guard let playheadTimeUs = context.playheadTimeUs else { return nil }
            return simulator.clip(at: playheadTimeUs, preferredTrackId: context.selectedTrackId)
        }
    }

    func resolveTrackId(
        _ target: SemanticEditTarget?,
        context: IntentCompilerContext,
        previousTrackId: String? = nil
    ) -> String? {
        guard let target else {
            return context.selectedTrackId ?? previousTrackId
        }
        guard case .track(let reference) = target else { return nil }
        return resolveTrackId(reference, context: context) ?? previousTrackId
    }

    func resolveTrackId(_ reference: SemanticTrackReference?, context: IntentCompilerContext) -> String? {
        guard let reference else { return nil }
        switch reference.type {
        case .selectedTrack:
            return context.selectedTrackId
        case .trackId:
            return reference.trackId
        }
    }
}

private extension IntentCompiler {
    func durationExpression(from value: JSONValue) -> DurationExpression? {
        guard case .object(let object) = value,
              let type = object["type"]?.stringValue else { return nil }

        switch type {
        case "duration":
            guard let amount = object["value"]?.doubleValue,
                  let unitValue = object["unit"]?.stringValue,
                  let unit = DurationUnit(rawValue: unitValue) else { return nil }
            return .duration(value: amount, unit: unit)
        case "percentage":
            guard let amount = object["value"]?.doubleValue else { return nil }
            return .percentage(value: amount)
        case "vague":
            return .vague(phrase: object["phrase"]?.stringValue ?? "")
        default:
            return nil
        }
    }

    func timeExpression(from value: JSONValue) -> TimeExpression? {
        guard case .object(let object) = value,
              let type = object["type"]?.stringValue else { return nil }

        switch type {
        case "playhead":
            return .playhead
        case "absoluteTimelineTime":
            guard let amount = object["value"]?.doubleValue,
                  let unitValue = object["unit"]?.stringValue,
                  let unit = DurationUnit(rawValue: unitValue) else { return nil }
            return .absoluteTimelineTime(value: amount, unit: unit)
        case "fractionOfClip":
            guard let amount = object["value"]?.doubleValue else { return nil }
            let relativeTo = object["relativeTo"]?.stringValue.flatMap(ClipTimeReference.init(rawValue:)) ?? .postPreviousOperations
            return .fractionOfClip(value: amount, relativeTo: relativeTo)
        case "afterStart":
            guard let amountValue = object["amount"],
                  let amount = durationExpression(from: amountValue) else { return nil }
            return .afterStart(amount: amount)
        case "beforeEnd":
            guard let amountValue = object["amount"],
                  let amount = durationExpression(from: amountValue) else { return nil }
            return .beforeEnd(amount: amount)
        default:
            return nil
        }
    }

    func resolveDurationUs(_ expression: DurationExpression, clip: Clip) -> Int64? {
        switch expression {
        case .duration(let value, let unit):
            return microseconds(value: value, unit: unit)
        case .percentage(let value):
            return Int64((Double(clip.timelineRange.duration) * value / 100.0).rounded())
        case .vague:
            return nil
        }
    }

    func resolveTimeUs(_ expression: TimeExpression, clip: Clip, context: IntentCompilerContext) -> Int64? {
        switch expression {
        case .playhead:
            return context.playheadTimeUs
        case .absoluteTimelineTime(let value, let unit):
            return microseconds(value: value, unit: unit)
        case .fractionOfClip(let value, _):
            return clip.timelineRange.start + Int64((Double(clip.timelineRange.duration) * value).rounded())
        case .afterStart(let amount):
            guard let durationUs = resolveDurationUs(amount, clip: clip) else { return nil }
            return clip.timelineRange.start + durationUs
        case .beforeEnd(let amount):
            guard let durationUs = resolveDurationUs(amount, clip: clip) else { return nil }
            return clip.timelineRange.end - durationUs
        }
    }

    func microseconds(value: Double, unit: DurationUnit) -> Int64 {
        switch unit {
        case .microsecond:
            return Int64(value.rounded())
        case .millisecond:
            return Int64((value * 1_000).rounded())
        case .second:
            return Int64((value * 1_000_000).rounded())
        case .minute:
            return Int64((value * 60_000_000).rounded())
        }
    }
}

private struct IntentTimelineSimulator {
    private(set) var clipsById: [String: Clip]
    private(set) var orderedClipIdsByTrackId: [String: [String]]

    init(context: IntentCompilerContext) {
        self.clipsById = context.clipsById
        self.orderedClipIdsByTrackId = context.orderedClipIdsByTrackId
    }

    func clip(withId clipId: String) -> Clip? {
        clipsById[clipId]
    }

    func orderedClipIds(for trackId: String) -> [String] {
        orderedClipIdsByTrackId[trackId] ?? []
    }

    func clip(at timeUs: Int64, preferredTrackId: String?) -> Clip? {
        if let preferredTrackId {
            let preferred = orderedClipIds(for: preferredTrackId)
                .compactMap { clipsById[$0] }
                .first { $0.timelineRange.start <= timeUs && timeUs < $0.timelineRange.end }
            if let preferred { return preferred }
        }

        return orderedClipIdsByTrackId.keys.sorted()
            .flatMap { orderedClipIds(for: $0).compactMap { clipsById[$0] } }
            .first { $0.timelineRange.start <= timeUs && timeUs < $0.timelineRange.end }
    }

    mutating func apply(_ operation: ResolvedIntentOperation) {
        switch operation.parameters {
        case .splitClip(let atTimeUs):
            guard let clipId = operation.targetClipId else { return }
            applySplit(clipId: clipId, atTimeUs: atTimeUs)
        case .removeClip:
            guard let clipId = operation.targetClipId else { return }
            applyRemove(clipId: clipId)
        case .trimClip(let sourceRange, let timelineRange):
            guard let clipId = operation.targetClipId else { return }
            applyTrim(clipId: clipId, sourceRange: sourceRange, timelineRange: timelineRange)
        case .moveClip(let orderedClipIds):
            guard let clipId = operation.targetClipId,
                  let trackId = clipsById[clipId]?.trackId else { return }
            applyOrder(trackId: trackId, orderedClipIds: orderedClipIds)
        case .replaceTrackClips(let clips):
            guard let trackId = operation.targetTrackId else { return }
            for clip in clips {
                clipsById[clip.clipId] = clip
            }
            orderedClipIdsByTrackId[trackId] = clips.map(\.clipId)
        }
    }

    private mutating func applySplit(clipId: String, atTimeUs: Int64) {
        guard let clip = clipsById[clipId] else { return }
        let leftDuration = atTimeUs - clip.timelineRange.start
        let sourceMid = clip.sourceRange.start + leftDuration
        var leftClip = clip
        leftClip.sourceRange = TimeRange(start: clip.sourceRange.start, end: sourceMid)
        leftClip.timelineRange = TimeRange(start: clip.timelineRange.start, end: atTimeUs)

        let rightClipId = "\(clipId)-split-right"
        let rightClip = Clip(
            clipId: rightClipId,
            trackId: clip.trackId,
            mediaId: clip.mediaId,
            sourceRange: TimeRange(start: sourceMid, end: clip.sourceRange.end),
            timelineRange: TimeRange(start: atTimeUs, end: clip.timelineRange.end),
            createdAt: clip.createdAt,
            updatedAt: clip.updatedAt
        )

        clipsById[clipId] = leftClip
        clipsById[rightClipId] = rightClip
        var order = orderedClipIdsByTrackId[clip.trackId] ?? []
        if let index = order.firstIndex(of: clipId) {
            order.insert(rightClipId, at: order.index(after: index))
        }
        orderedClipIdsByTrackId[clip.trackId] = order
    }

    private mutating func applyRemove(clipId: String) {
        guard let clip = clipsById.removeValue(forKey: clipId) else { return }
        var order = orderedClipIdsByTrackId[clip.trackId] ?? []
        order.removeAll { $0 == clipId }
        orderedClipIdsByTrackId[clip.trackId] = order
        packTrack(trackId: clip.trackId)
    }

    private mutating func applyTrim(clipId: String, sourceRange: TimeRange, timelineRange: TimeRange) {
        guard var clip = clipsById[clipId] else { return }
        clip.sourceRange = sourceRange
        clip.timelineRange = timelineRange
        clipsById[clipId] = clip
    }

    private mutating func applyOrder(trackId: String, orderedClipIds: [String]) {
        orderedClipIdsByTrackId[trackId] = orderedClipIds
        packTrack(trackId: trackId)
    }

    private mutating func packTrack(trackId: String) {
        var cursor: Int64 = 0
        for clipId in orderedClipIdsByTrackId[trackId] ?? [] {
            guard var clip = clipsById[clipId] else { continue }
            let duration = clip.timelineRange.duration
            clip.timelineRange = TimeRange(start: cursor, end: cursor + duration)
            clipsById[clipId] = clip
            cursor += duration
        }
    }

}
