import Foundation
import OSLog

extension AgentViewModel {
    func buildSourceClipLookup(
        from videos: [SelectedVideoAsset],
        response: IngestResponse
    ) async -> [String: AgentSourceClip] {
        let localDescriptors = await makeLocalVideoDescriptors(from: videos)
        var lookup: [String: AgentSourceClip] = [:]
        var usedLocalOrders: Set<Int> = []
        let remoteSummary = response.videos.map { self.describeResponseVideo($0) }.joined(separator: " | ")
        let localSummary = localDescriptors.map { self.describeLocalDescriptor($0) }.joined(separator: " | ")

        logger.info(
            """
            Building clip lookup. localVideos=\(localDescriptors.count) remoteVideos=\(response.videos.count) remoteSummary=\(remoteSummary, privacy: .public)
            """
        )

        for (position, responseVideo) in response.videos.enumerated() {
            guard let match = matchLocalDescriptor(
                for: responseVideo,
                fallbackPosition: position,
                descriptors: localDescriptors,
                usedOrders: &usedLocalOrders
            ) else {
                logger.error(
                    "No local video match found for remote clip \(self.describeResponseVideo(responseVideo), privacy: .public). localSummary=\(localSummary, privacy: .public)"
                )
                continue
            }

            let identifiers = makeRemoteIdentifiers(for: responseVideo, fallbackOrder: match.descriptor.order)

            let sourceClip = AgentSourceClip(
                id: match.descriptor.video.id,
                localKey: match.descriptor.localKey,
                displayName: match.descriptor.video.displayName,
                videoURL: match.descriptor.video.originalURL,
                durationSeconds: match.descriptor.durationSeconds,
                order: match.descriptor.order,
                remoteIdentifiers: identifiers
            )

            for identifier in identifiers {
                lookup[identifier] = sourceClip
            }

            logger.info(
                "Mapped remote clip ids [\(identifiers.joined(separator: ", "), privacy: .public)] to local video \(match.descriptor.video.displayName, privacy: .public) using \(match.strategy.rawValue, privacy: .public)"
            )
        }

        logger.info(
            "Completed clip lookup. registeredKeys=\(lookup.keys.sorted().joined(separator: ", "), privacy: .public)"
        )

        return lookup
    }

    func makeRemoteIdentifiers(
        for responseVideo: IngestVideoResponse?,
        fallbackOrder: Int
    ) -> [String] {
        var identifiers: [String] = []

        func appendUnique(_ value: String?) {
            guard let value, !value.isEmpty, !identifiers.contains(value) else { return }
            identifiers.append(value)
        }

        appendUnique(responseVideo?.localKey)
        appendUnique(responseVideo?.clipID.rawValue)

        if identifiers.isEmpty {
            identifiers.append("local-\(fallbackOrder)")
        }

        return identifiers
    }

    func makeLocalVideoDescriptors(
        from videos: [SelectedVideoAsset]
    ) async -> [LocalVideoDescriptor] {
        var descriptors: [LocalVideoDescriptor] = []

        for (order, video) in videos.enumerated() {
            let durationSeconds = await VideoAssetPreviewLoader.loadDuration(for: video.originalURL)
            descriptors.append(
                LocalVideoDescriptor(
                    video: video,
                    order: order,
                    localKey: video.localKey,
                    normalizedStem: normalizedStem(for: video.displayName),
                    durationSeconds: durationSeconds
                )
            )
        }

        return descriptors
    }

    func matchLocalDescriptor(
        for responseVideo: IngestVideoResponse,
        fallbackPosition: Int,
        descriptors: [LocalVideoDescriptor],
        usedOrders: inout Set<Int>
    ) -> LocalVideoMatch? {
        if let responseLocalKey = responseVideo.localKey,
           let localKeyMatch = descriptors.first(where: {
               $0.localKey == responseLocalKey && !usedOrders.contains($0.order)
           }) {
            usedOrders.insert(localKeyMatch.order)
            return LocalVideoMatch(descriptor: localKeyMatch, strategy: .localKey)
        }

        let responseStem = normalizedStem(for: responseVideo.fileName)

        if let exactIndexMatch = descriptors.first(where: {
            $0.order == responseVideo.index && !usedOrders.contains($0.order)
        }) {
            usedOrders.insert(exactIndexMatch.order)
            return LocalVideoMatch(descriptor: exactIndexMatch, strategy: .exactIndex)
        }

        if responseVideo.index > 0,
           let oneBasedIndexMatch = descriptors.first(where: {
               $0.order == (responseVideo.index - 1) && !usedOrders.contains($0.order)
           }) {
            usedOrders.insert(oneBasedIndexMatch.order)
            return LocalVideoMatch(descriptor: oneBasedIndexMatch, strategy: .oneBasedIndex)
        }

        if let fileNameMatch = descriptors.first(where: {
            $0.normalizedStem == responseStem && !usedOrders.contains($0.order)
        }) {
            usedOrders.insert(fileNameMatch.order)
            return LocalVideoMatch(descriptor: fileNameMatch, strategy: .fileNameStem)
        }

        if let positionalMatch = descriptors[safe: fallbackPosition], !usedOrders.contains(positionalMatch.order) {
            usedOrders.insert(positionalMatch.order)
            return LocalVideoMatch(descriptor: positionalMatch, strategy: .fallbackPosition)
        }

        if let firstUnused = descriptors.first(where: { !usedOrders.contains($0.order) }) {
            usedOrders.insert(firstUnused.order)
            return LocalVideoMatch(descriptor: firstUnused, strategy: .firstUnused)
        }

        return nil
    }

    func normalizedStem(for fileName: String) -> String {
        URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
    }

    func describeResponseVideo(_ responseVideo: IngestVideoResponse) -> String {
        let identifiers = makeRemoteIdentifiers(for: responseVideo, fallbackOrder: responseVideo.index)
        return "file=\(responseVideo.fileName) index=\(responseVideo.index) localKey=\(responseVideo.localKey ?? "nil") ids=[\(identifiers.joined(separator: ", "))]"
    }

    func describeLocalDescriptor(_ descriptor: LocalVideoDescriptor) -> String {
        "file=\(descriptor.video.displayName) order=\(descriptor.order) localKey=\(descriptor.localKey) remoteClipID=\(descriptor.video.remoteClipID ?? "nil") stem=\(descriptor.normalizedStem)"
    }

    func openSocket(at url: URL) async throws {
        closeSocket(sendDoneMessage: false)

        let task = urlSession.webSocketTask(with: url)
        webSocketTask = task
        task.resume()

        model.isConnected = true
        logger.info("Websocket resumed at \(url.absoluteString, privacy: .public)")
        receiveTask = Task { [weak self] in
            await self?.receiveMessages()
        }
    }

    func closeSocket(sendDoneMessage: Bool) {
        let task = webSocketTask
        let shouldSendDone = sendDoneMessage && model.isConnected
        let sessionID = model.sessionID ?? "nil"

        logger.info(
            "Closing websocket. shouldSendDone=\(shouldSendDone) currentSessionID=\(sessionID, privacy: .public)"
        )

        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask = nil

        if shouldSendDone, let task {
            Task {
                let payload = try? encoder.encode(AgentClientMessage.done)
                if let payload, let text = String(data: payload, encoding: .utf8) {
                    try? await task.send(.string(text))
                }
                task.cancel(with: .normalClosure, reason: nil)
            }
        } else {
            task?.cancel(with: .goingAway, reason: nil)
        }

        model.isConnected = false
        model.isSendingFeedback = false
        model.isAwaitingUserInput = false
    }

    func sendMessage(_ message: AgentClientMessage) async throws {
        guard let webSocketTask else {
            throw AgentSessionError.disconnected
        }

        let data = try encoder.encode(message)
        guard let stringPayload = String(data: data, encoding: .utf8) else {
            throw AgentSessionError.encodingFailed
        }

        logger.info("Sending websocket message: \(stringPayload, privacy: .public)")
        try await webSocketTask.send(.string(stringPayload))
    }

    func receiveMessages() async {
        guard let webSocketTask else { return }

        do {
            while !Task.isCancelled {
                let message = try await webSocketTask.receive()

                switch message {
                case .string(let text):
                    logger.info("Received websocket text payload: \(text, privacy: .public)")
                    try handleMessageData(Data(text.utf8))
                case .data(let data):
                    logger.info("Received websocket binary payload of \(data.count) bytes")
                    try handleMessageData(data)
                @unknown default:
                    logger.warning("Received unknown websocket message container.")
                    break
                }
            }
        } catch {
            guard !Task.isCancelled else { return }
            applyError(error)
        }
    }

    func handleMessageData(_ data: Data) throws {
        let event = try AgentSocketEvent.decode(from: data, using: decoder)
        let eventDescription = event.logDescription

        switch event {
        case .sessionStarted(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue
            model.stage = .connecting
            model.errorMessage = nil
            clearReasoningNotes()
            setStatusMessage("Reviewing your imported clips.")

        case .sessionResumed(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.stage = .assemblingTimeline
            model.errorMessage = nil
            model.isSendingFeedback = false
            clearReasoningNotes()
            setStatusMessage("Updating the edit with your latest feedback.")

        case .timelineUpdate(let payload):
            model.timelineClips = makeTimelineClips(from: payload.timeline)
            model.pendingEditorSeed = makeEditorSeed(from: payload.timeline)
            model.timelineNotes = payload.timelineNotes
            model.stage = .assemblingTimeline
            model.errorMessage = nil
            model.isSendingFeedback = false

            if model.statusMessage.trimmedForTransport.isEmpty {
                setStatusMessage("Your first edit is ready to review.")
            }

        case .waitingForUser(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue ?? model.projectID
            model.stage = .waitingForFeedback
            model.errorMessage = nil
            model.isAwaitingUserInput = true
            model.isSendingFeedback = false
            setStatusMessage("Your first edit is ready. Approve it or ask for changes.")

        case .sessionComplete(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue ?? model.projectID
            model.timelineClips = makeTimelineClips(from: payload.timeline)
            model.pendingEditorSeed = makeEditorSeed(from: payload.timeline)
            model.stage = .completed
            model.errorMessage = nil
            model.isAwaitingUserInput = false
            model.isSendingFeedback = false
            setStatusMessage("Your edit is ready.")

        case .nodeStart(let payload):
            handleNodeStart(payload)

        case .nodeComplete(let payload):
            handleNodeComplete(payload)

        case .statusUpdate(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.errorMessage = nil
            setStatusMessage(payload.statusMessage)
            applyReasoningNotes(
                payload.statusDetails?.reasoningNotes,
                forNode: payload.statusDetails?.node ?? payload.node
            )

            if !handleClipCleanupStatusUpdate(payload), model.isAwaitingUserInput {
                model.stage = .waitingForFeedback
            }

        case .sessionClosed(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.isConnected = false
            model.isAwaitingUserInput = false
            model.isSendingFeedback = false

            if model.stage != .completed {
                model.stage = .closed
                setStatusMessage("The editing session has ended.")
            }

        case .error(let payload):
            applyErrorMessage(payload.detail)

        case .unknown(let type):
            logger.warning("Ignoring unknown websocket event type: \(type, privacy: .public)")
        }

        logInterpretedState(after: eventDescription)
    }

    func handleNodeStart(_ event: AgentNodeLifecycleEvent) {
        if event.node == "decision_agent" {
            model.reasoningNotes = [
                AgentReasoningNote(text: "Let me take a look at what you've provided so far.")
            ]
        }

        guard event.node == "clip_cleanup", let payload = event.payload else { return }
        applyClipCleanupStart(payload, fallbackStatusMessage: payload.statusMessage)
    }

    func handleClipCleanupStatusUpdate(_ event: AgentStatusUpdateEvent) -> Bool {
        let nodeName = event.statusDetails?.node ?? event.node
        guard nodeName == "clip_cleanup" else { return false }

        guard let details = event.statusDetails else {
            model.stage = .extractingClips

            if !event.statusMessage.trimmedForTransport.isEmpty {
                setStatusMessage(event.statusMessage)
            }

            return true
        }

        if details.containsCompletionDetails {
            applyClipCleanupCompletion(details, fallbackStatusMessage: event.statusMessage)
        } else if details.containsInputClipReferences {
            applyClipCleanupStart(details, fallbackStatusMessage: event.statusMessage)
        } else {
            model.stage = .extractingClips

            if !event.statusMessage.trimmedForTransport.isEmpty {
                setStatusMessage(event.statusMessage)
            }
        }

        return true
    }

    func applyClipCleanupStart(
        _ payload: AgentNodePayload,
        fallbackStatusMessage: String?
    ) {
        let inputClipIDs = orderedUniqueClipIDs(
            from: [
                (payload.inputClips ?? []).map(\.clipID),
                payload.inputClipIDs ?? []
            ]
        )
        let knownKeys = sourceClipsByRemoteID.keys.sorted().joined(separator: ", ")
        let existingClips = Dictionary(uniqueKeysWithValues: model.extractionClips.map { ($0.remoteClipID, $0) })
        let summariesByClipID = (payload.inputClips ?? []).reduce(into: [String: String]()) { result, inputClip in
            guard let summary = inputClip.summary?.trimmedForTransport, !summary.isEmpty else { return }
            result[inputClip.clipID.rawValue] = summary
        }

        var nextClips: [AgentExtractionClip] = []

        for (index, clipID) in inputClipIDs.enumerated() {
            guard let sourceClip = sourceClipsByRemoteID[clipID] else {
                logger.error(
                    "clip_cleanup start could not map remote clip id \(clipID, privacy: .public). knownKeys=\(knownKeys, privacy: .public)"
                )
                continue
            }

            let existingClip = existingClips[clipID]
            nextClips.append(
                makeExtractionClip(
                    for: sourceClip,
                    remoteClipID: clipID,
                    order: index,
                    summary: summariesByClipID[clipID] ?? existingClip?.summary,
                    ranges: [],
                    usesFullClip: false,
                    isAnalyzing: true,
                    isDropped: false
                )
            )
        }

        model.extractionClips = nextClips
        model.stage = .extractingClips

        if let statusMessage = (payload.statusMessage ?? fallbackStatusMessage),
           !statusMessage.trimmedForTransport.isEmpty {
            setStatusMessage(statusMessage)
        }
    }

    func handleNodeComplete(_ event: AgentNodeLifecycleEvent) {
        applyReasoningNotes(event.payload?.reasoningNotes, forNode: event.node)

        guard event.node == "clip_cleanup", let payload = event.payload else { return }
        applyClipCleanupCompletion(payload, fallbackStatusMessage: payload.statusMessage)
    }

    func applyClipCleanupCompletion(
        _ payload: AgentNodePayload,
        fallbackStatusMessage: String?
    ) {
        let selectedClipIDs = Set((payload.selectedClipIDs ?? []).map(\.rawValue))
        let droppedClipIDs = Set((payload.droppedClipIDs ?? []).map(\.rawValue))
        let hasExplicitSelectionState = payload.selectedClipIDs != nil || payload.droppedClipIDs != nil
        let knownKeys = sourceClipsByRemoteID.keys.sorted().joined(separator: ", ")
        let existingClips = Dictionary(uniqueKeysWithValues: model.extractionClips.map { ($0.remoteClipID, $0) })
        let orderedClipIDs = {
            let clipIDs = orderedUniqueClipIDs(
                from: [
                    payload.clipIDs ?? [],
                    payload.selectedClipIDs ?? [],
                    payload.droppedClipIDs ?? [],
                    (payload.clipRanges ?? []).map(\.clipID)
                ]
            )

            if !clipIDs.isEmpty {
                return clipIDs
            }

            return model.extractionClips.map(\.remoteClipID)
        }()

        let rangeLookup = (payload.clipRanges ?? []).reduce(
            into: [String: (changed: Bool?, ranges: [AgentClipRange])]()
        ) { result, clipRange in
            result[clipRange.clipID.rawValue] = (
                changed: clipRange.changed,
                ranges: clipRange.ranges
                    .map { AgentClipRange(inSec: $0.inSec, outSec: $0.outSec, reason: $0.reason) }
                    .sorted(by: { $0.inSec < $1.inSec })
            )
        }

        var nextClips: [AgentExtractionClip] = []

        for (index, clipID) in orderedClipIDs.enumerated() {
            guard let sourceClip = sourceClipsByRemoteID[clipID] else {
                logger.error(
                    "clip_cleanup complete could not map remote clip id \(clipID, privacy: .public). knownKeys=\(knownKeys, privacy: .public)"
                )
                continue
            }

            let clipSelection = rangeLookup[clipID]
            let ranges = clipSelection?.ranges ?? []
            let isDropped: Bool
            let usesFullClip: Bool

            if droppedClipIDs.contains(clipID) {
                isDropped = true
                usesFullClip = false
            } else if selectedClipIDs.contains(clipID) {
                if clipSelection?.changed == true {
                    isDropped = ranges.isEmpty
                    usesFullClip = false
                } else {
                    isDropped = false
                    usesFullClip = ranges.isEmpty
                }
            } else if clipSelection?.changed == false {
                isDropped = false
                usesFullClip = true
            } else if clipSelection?.changed == true {
                isDropped = ranges.isEmpty
                usesFullClip = false
            } else if hasExplicitSelectionState || payload.clipIDs != nil || payload.clipRanges != nil {
                isDropped = ranges.isEmpty
                usesFullClip = false
            } else {
                isDropped = existingClips[clipID]?.isDropped ?? ranges.isEmpty
                usesFullClip = existingClips[clipID]?.usesFullClip ?? false
            }

            nextClips.append(
                makeExtractionClip(
                    for: sourceClip,
                    remoteClipID: clipID,
                    order: index,
                    summary: existingClips[clipID]?.summary,
                    ranges: ranges,
                    usesFullClip: usesFullClip,
                    isAnalyzing: false,
                    isDropped: isDropped
                )
            )
        }

        model.extractionClips = nextClips
        model.stage = .assemblingTimeline

        if let statusMessage = (payload.statusMessage ?? fallbackStatusMessage),
           !statusMessage.trimmedForTransport.isEmpty {
            setStatusMessage(statusMessage)
        }
    }

    func makeTimelineClips(from payload: [AgentTimelineEntry]) -> [AgentTimelineClip] {
        payload.enumerated().map { index, entry in
            guard let sourceClip = sourceClip(for: entry) else {
                let knownKeys = sourceClipsByRemoteID.keys.sorted().joined(separator: ", ")
                let remoteResponseDescription = ingestResponse?.videos.map(describeResponseVideo).joined(separator: " | ") ?? "nil"
                logger.error(
                    "Unable to map timeline clip id \(entry.clipID.rawValue, privacy: .public) localKey=\(entry.localKey ?? "nil", privacy: .public). knownKeys=\(knownKeys, privacy: .public) remoteResponse=\(remoteResponseDescription, privacy: .public)"
                )

                return AgentTimelineClip(
                    id: "placeholder-\(entry.clipID.rawValue)-\(index)",
                    displayName: "Clip \(entry.clipID.rawValue)",
                    videoURL: nil,
                    remoteClipID: entry.clipID.rawValue,
                    inSec: entry.inSec,
                    outSec: entry.outSec,
                    rationale: entry.rationale,
                    segmentDurationSeconds: max(entry.outSec - entry.inSec, 0.1),
                    usesPlaceholderAsset: true
                )
            }

            let segmentDurationSeconds = max(entry.outSec - entry.inSec, 0.1)
            let id = "\(sourceClip.id)-\(index)-\(entry.inSec)-\(entry.outSec)"

            return AgentTimelineClip(
                id: id,
                displayName: sourceClip.displayName,
                videoURL: sourceClip.videoURL,
                remoteClipID: entry.clipID.rawValue,
                inSec: entry.inSec,
                outSec: entry.outSec,
                rationale: entry.rationale,
                segmentDurationSeconds: segmentDurationSeconds,
                usesPlaceholderAsset: false
            )
        }
    }

    func makeEditorSeed(from payload: [AgentTimelineEntry]) -> ImportedTimelineSeed? {
        let segments = payload.compactMap { entry -> ImportedTimelineSeedSegment? in
            guard let sourceClip = sourceClip(for: entry) else {
                return nil
            }

            let startTimeUs = microseconds(for: entry.inSec)
            let endTimeUs = max(microseconds(for: entry.outSec), startTimeUs + 1)

            return ImportedTimelineSeedSegment(
                sourceLocalKey: sourceClip.localKey,
                startTimeUs: startTimeUs,
                endTimeUs: endTimeUs
            )
        }

        guard !segments.isEmpty else { return nil }
        return ImportedTimelineSeed(sourceVideos: sourceVideos, segments: segments)
    }

    func sourceClip(for entry: AgentTimelineEntry) -> AgentSourceClip? {
        if let localKey = entry.localKey,
           let localKeyMatch = sourceClipsByRemoteID[localKey] {
            return localKeyMatch
        }

        return sourceClipsByRemoteID[entry.clipID.rawValue]
    }

    func makeExtractionClip(
        for sourceClip: AgentSourceClip,
        remoteClipID: String,
        order: Int,
        summary: String?,
        ranges: [AgentClipRange],
        usesFullClip: Bool,
        isAnalyzing: Bool,
        isDropped: Bool
    ) -> AgentExtractionClip {
        AgentExtractionClip(
            id: sourceClip.id,
            displayName: sourceClip.displayName,
            videoURL: sourceClip.videoURL,
            durationSeconds: sourceClip.durationSeconds,
            order: order,
            remoteClipID: remoteClipID,
            summary: summary,
            ranges: ranges,
            usesFullClip: usesFullClip,
            isAnalyzing: isAnalyzing,
            isDropped: isDropped
        )
    }

    func orderedUniqueClipIDs(from groups: [[FlexibleIdentifier]]) -> [String] {
        var orderedClipIDs: [String] = []
        var seenClipIDs: Set<String> = []

        for group in groups {
            for identifier in group {
                if seenClipIDs.insert(identifier.rawValue).inserted {
                    orderedClipIDs.append(identifier.rawValue)
                }
            }
        }

        return orderedClipIDs
    }

    func microseconds(for seconds: Double) -> Int64 {
        Int64((max(seconds, 0) * 1_000_000).rounded())
    }

    func setStatusMessage(_ message: String?) {
        guard let message else { return }
        let trimmedMessage = message.trimmedForTransport
        guard !trimmedMessage.isEmpty else { return }
        model.statusMessage = userFacingStatusMessage(from: trimmedMessage)
    }

    func applyReasoningNotes(_ notes: [String]?, forNode node: String?) {
        guard node == "decision_agent" else { return }

        let sanitizedNotes = (notes ?? [])
            .map(\.trimmedForTransport)
            .filter { !$0.isEmpty }
        let currentNotes = model.reasoningNotes.map(\.text)

        guard sanitizedNotes != currentNotes else { return }

        model.reasoningNotes = sanitizedNotes.map { AgentReasoningNote(text: $0) }
    }

    func clearReasoningNotes() {
        guard !model.reasoningNotes.isEmpty else { return }
        model.reasoningNotes = []
    }

    func userFacingStatusMessage(from message: String) -> String {
        let normalized = message
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")

        switch normalized {
        case "session started",
             "starting session",
             "start session",
             "connecting to the editing session",
             "preparing clips and opening the live session",
             "starting the editing process":
            return "Starting the editing process."
        case "reviewing uploaded clips",
             "reviewing your imported clips":
            return "Reviewing your imported clips."
        case "sending your timeline changes back to iris",
             "updating the edit with your feedback":
            return "Updating the edit with your feedback."
        case "submitting approval and finalizing the session",
             "finalizing your edit":
            return "Finalizing your edit."
        case "draft timeline ready for review":
            return "Your first edit is ready to review."
        case "draft timeline ready approve it or request changes":
            return "Your first edit is ready. Approve it or ask for changes."
        case "timeline approved session complete",
             "session complete":
            return "Your edit is ready."
        case "session closed":
            return "The editing session has ended."
        default:
            break
        }

        if normalized.contains("timeline refinement resumed") {
            return "Updating the edit with your latest feedback."
        }

        if normalized.contains("clip cleanup")
            || normalized.contains("reviewing clips")
            || normalized.contains("extracting clips") {
            return "Picking the strongest moments from your clips."
        }

        if normalized.contains("waiting for user") {
            return "Your first edit is ready. Approve it or ask for changes."
        }

        if normalized.contains("building timeline")
            || normalized.contains("assembling timeline")
            || normalized.contains("timeline update") {
            return "Building your first edit."
        }

        return message
    }

    func applyError(_ error: Error) {
        applyErrorMessage(error.localizedDescription)
    }

    func logInterpretedState(after eventDescription: String) {
        let stageDescription = String(describing: self.model.stage)
        let statusMessage = self.model.statusMessage
        let timelineCount = self.model.timelineClips.count
        let extractionCount = self.model.extractionClips.count
        let awaitingUser = self.model.isAwaitingUserInput
        let isConnected = self.model.isConnected
        let sessionID = self.model.sessionID ?? "nil"

        logger.info(
            """
            Interpreted \(eventDescription, privacy: .public) -> stage=\(stageDescription, privacy: .public) status=\(statusMessage, privacy: .public) timelineCount=\(timelineCount) extractionCount=\(extractionCount) awaitingUser=\(awaitingUser) connected=\(isConnected) currentSessionID=\(sessionID, privacy: .public)
            """
        )
    }

    func applyErrorMessage(_ message: String) {
        receiveTask?.cancel()
        receiveTask = nil
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil

        model.stage = .error
        model.errorMessage = message
        model.statusMessage = message
        model.isConnected = false
        model.isAwaitingUserInput = false
        model.isSendingFeedback = false

        let sessionID = self.model.sessionID ?? "nil"
        logger.error(
            "Agent state entered error. message=\(message, privacy: .public) sessionID=\(sessionID, privacy: .public)"
        )
    }
}
