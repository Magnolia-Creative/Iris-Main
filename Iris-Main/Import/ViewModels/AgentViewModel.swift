internal import Combine
import Foundation
import OSLog

@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var model = AgentModel()

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "AgentView"
    )
    private let urlSession: URLSession
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()

    private var sourceVideos: [SelectedVideoAsset] = []
    private var ingestResponse: IngestResponse?
    private var ingestEndpoint: URL?
    private var sourceClipsByRemoteID: [String: AgentSourceClip] = [:]
    private var webSocketTask: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?

    init(urlSession: URLSession = .shared) {
        self.urlSession = urlSession
    }

    func configure(
        promptText: String,
        videos: [SelectedVideoAsset],
        ingestResponse: IngestResponse?,
        ingestEndpoint: URL
    ) {
        closeSocket(sendDoneMessage: false)

        sourceVideos = videos
        self.ingestResponse = ingestResponse
        self.ingestEndpoint = ingestEndpoint
        sourceClipsByRemoteID = [:]

        model = AgentModel(
            promptText: promptText,
            stage: .idle,
            statusMessage: "Connecting to the editing session.",
            extractionClips: [],
            timelineClips: [],
            pendingEditorSeed: nil,
            timelineNotes: [],
            feedbackDraft: "",
            sessionID: ingestResponse?.sessionID.rawValue,
            projectID: nil,
            errorMessage: nil,
            isAwaitingUserInput: false,
            isConnected: false,
            isSendingFeedback: false,
            hasStarted: false
        )

        logger.info(
            "Configured agent view. promptLength=\(promptText.count) localVideos=\(videos.count) sessionID=\(ingestResponse?.sessionID.rawValue ?? "nil", privacy: .public)"
        )
    }

    func startIfNeeded() async {
        guard !model.hasStarted else { return }

        model.hasStarted = true
        model.stage = .connecting
        model.errorMessage = nil
        model.statusMessage = "Preparing clips and opening the live session."

        do {
            let response = try requireIngestResponse()
            sourceClipsByRemoteID = await buildSourceClipLookup(from: sourceVideos, response: response)

            guard let ingestEndpoint,
                  let socketURL = AppConfiguration.agentWebSocketEndpoint(
                      sessionID: response.sessionID.rawValue,
                      basedOn: ingestEndpoint
                  ) else {
                throw AgentSessionError.invalidSessionEndpoint
            }

            logger.info(
                "Opening websocket session \(response.sessionID.rawValue, privacy: .public) at \(socketURL.absoluteString, privacy: .public)"
            )
            try await openSocket(at: socketURL)
            try await sendMessage(.startSession(prompt: model.promptText))
        } catch {
            applyError(error)
        }
    }

    func submitFeedback() async {
        guard model.canSubmitFeedback else { return }

        let prompt = model.feedbackDraft.trimmedForTransport
        model.feedbackDraft = ""
        model.isAwaitingUserInput = false
        model.isSendingFeedback = true
        model.errorMessage = nil
        model.stage = .assemblingTimeline
        model.statusMessage = "Sending your timeline changes back to Iris."

        do {
            try await sendMessage(.reprompt(prompt: prompt))
        } catch {
            applyError(error)
        }
    }

    func approveTimeline() async {
        guard model.canApproveTimeline else { return }

        model.isAwaitingUserInput = false
        model.isSendingFeedback = true
        model.errorMessage = nil
        model.stage = .assemblingTimeline
        model.statusMessage = "Submitting approval and finalizing the session."

        do {
            try await sendMessage(.reprompt(prompt: "approve"))
        } catch {
            applyError(error)
        }
    }

    func updateFeedbackDraft(_ text: String) {
        model.feedbackDraft = text
    }

    func closeIfNeeded() async {
        closeSocket(sendDoneMessage: true)
    }

    private func requireIngestResponse() throws -> IngestResponse {
        guard let ingestResponse else {
            throw AgentSessionError.missingSessionData
        }

        return ingestResponse
    }

    private func buildSourceClipLookup(
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

    private func makeRemoteIdentifiers(
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

    private func makeLocalVideoDescriptors(
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

    private func matchLocalDescriptor(
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

    private func normalizedStem(for fileName: String) -> String {
        URL(fileURLWithPath: fileName)
            .deletingPathExtension()
            .lastPathComponent
            .lowercased()
    }

    private func describeResponseVideo(_ responseVideo: IngestVideoResponse) -> String {
        let identifiers = makeRemoteIdentifiers(for: responseVideo, fallbackOrder: responseVideo.index)
        return "file=\(responseVideo.fileName) index=\(responseVideo.index) localKey=\(responseVideo.localKey ?? "nil") ids=[\(identifiers.joined(separator: ", "))]"
    }

    private func describeLocalDescriptor(_ descriptor: LocalVideoDescriptor) -> String {
        "file=\(descriptor.video.displayName) order=\(descriptor.order) localKey=\(descriptor.localKey) remoteClipID=\(descriptor.video.remoteClipID ?? "nil") stem=\(descriptor.normalizedStem)"
    }

    private func openSocket(at url: URL) async throws {
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

    private func closeSocket(sendDoneMessage: Bool) {
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

    private func sendMessage(_ message: AgentClientMessage) async throws {
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

    private func receiveMessages() async {
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

    private func handleMessageData(_ data: Data) throws {
        let event = try AgentSocketEvent.decode(from: data, using: decoder)
        let eventDescription = event.logDescription

        switch event {
        case .sessionStarted(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue
            model.stage = .connecting
            model.errorMessage = nil
            model.statusMessage = "Reviewing uploaded clips."

        case .sessionResumed(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.stage = .assemblingTimeline
            model.errorMessage = nil
            model.isSendingFeedback = false
            model.statusMessage = "Timeline refinement resumed for iteration \(payload.iterationCount)."

        case .timelineUpdate(let payload):
            model.timelineClips = makeTimelineClips(from: payload.timeline)
            model.pendingEditorSeed = makeEditorSeed(from: payload.timeline)
            model.timelineNotes = payload.timelineNotes
            model.stage = .assemblingTimeline
            model.errorMessage = nil
            model.isSendingFeedback = false

            if model.statusMessage.trimmedForTransport.isEmpty {
                model.statusMessage = "Draft timeline ready for review."
            }

        case .waitingForUser(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue ?? model.projectID
            model.stage = .waitingForFeedback
            model.errorMessage = nil
            model.isAwaitingUserInput = true
            model.isSendingFeedback = false
            model.statusMessage = "Draft timeline ready. Approve it or request changes."

        case .sessionComplete(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.projectID = payload.projectID?.rawValue ?? model.projectID
            model.timelineClips = makeTimelineClips(from: payload.timeline)
            model.pendingEditorSeed = makeEditorSeed(from: payload.timeline)
            model.stage = .completed
            model.errorMessage = nil
            model.isAwaitingUserInput = false
            model.isSendingFeedback = false
            model.statusMessage = "Timeline approved. Session complete."

        case .nodeStart(let payload):
            handleNodeStart(payload)

        case .nodeComplete(let payload):
            handleNodeComplete(payload)

        case .statusUpdate(let payload):
            model.sessionID = payload.sessionID.rawValue
            model.errorMessage = nil
            model.statusMessage = payload.statusMessage

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
                model.statusMessage = "Session closed."
            }

        case .error(let payload):
            applyErrorMessage(payload.detail)

        case .unknown(let type):
            logger.warning("Ignoring unknown websocket event type: \(type, privacy: .public)")
        }

        logInterpretedState(after: eventDescription)
    }

    private func handleNodeStart(_ event: AgentNodeLifecycleEvent) {
        guard event.node == "clip_cleanup", let payload = event.payload else { return }
        applyClipCleanupStart(payload, fallbackStatusMessage: payload.statusMessage)
    }

    private func handleClipCleanupStatusUpdate(_ event: AgentStatusUpdateEvent) -> Bool {
        let nodeName = event.statusDetails?.node ?? event.node
        guard nodeName == "clip_cleanup" else { return false }

        guard let details = event.statusDetails else {
            model.stage = .extractingClips

            if !event.statusMessage.trimmedForTransport.isEmpty {
                model.statusMessage = event.statusMessage
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
                model.statusMessage = event.statusMessage
            }
        }

        return true
    }

    private func applyClipCleanupStart(
        _ payload: AgentClipCleanupPayload,
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
            model.statusMessage = statusMessage
        }
    }

    private func handleNodeComplete(_ event: AgentNodeLifecycleEvent) {
        guard event.node == "clip_cleanup", let payload = event.payload else { return }
        applyClipCleanupCompletion(payload, fallbackStatusMessage: payload.statusMessage)
    }

    private func applyClipCleanupCompletion(
        _ payload: AgentClipCleanupPayload,
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
            model.statusMessage = statusMessage
        }
    }

    private func makeTimelineClips(from payload: [AgentTimelineEntry]) -> [AgentTimelineClip] {
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

    private func makeEditorSeed(from payload: [AgentTimelineEntry]) -> ImportedTimelineSeed? {
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

    private func sourceClip(for entry: AgentTimelineEntry) -> AgentSourceClip? {
        if let localKey = entry.localKey,
           let localKeyMatch = sourceClipsByRemoteID[localKey] {
            return localKeyMatch
        }

        return sourceClipsByRemoteID[entry.clipID.rawValue]
    }

    private func makeExtractionClip(
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

    private func orderedUniqueClipIDs(from groups: [[FlexibleIdentifier]]) -> [String] {
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

    private func microseconds(for seconds: Double) -> Int64 {
        Int64((max(seconds, 0) * 1_000_000).rounded())
    }

    private func applyError(_ error: Error) {
        applyErrorMessage(error.localizedDescription)
    }

    private func logInterpretedState(after eventDescription: String) {
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

    private func applyErrorMessage(_ message: String) {
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

private enum AgentSessionError: LocalizedError {
    case missingSessionData
    case invalidSessionEndpoint
    case disconnected
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .missingSessionData:
            return "The upload response did not include the session data required to open the agent view."
        case .invalidSessionEndpoint:
            return "The websocket session URL could not be created from the current app configuration."
        case .disconnected:
            return "The live agent session is not connected."
        case .encodingFailed:
            return "The websocket message could not be encoded."
        }
    }
}

private struct AgentSocketEnvelope: Decodable {
    let type: String
}

private enum AgentSocketEvent {
    case sessionStarted(AgentSessionStartedEvent)
    case sessionResumed(AgentSessionResumedEvent)
    case sessionComplete(AgentSessionCompleteEvent)
    case sessionClosed(AgentSessionClosedEvent)
    case timelineUpdate(AgentTimelineUpdateEvent)
    case waitingForUser(AgentWaitingForUserEvent)
    case nodeStart(AgentNodeLifecycleEvent)
    case nodeComplete(AgentNodeLifecycleEvent)
    case statusUpdate(AgentStatusUpdateEvent)
    case error(AgentErrorEvent)
    case unknown(String)

    static func decode(from data: Data, using decoder: JSONDecoder) throws -> AgentSocketEvent {
        let envelope = try decoder.decode(AgentSocketEnvelope.self, from: data)

        switch envelope.type {
        case "session_started":
            return .sessionStarted(try decoder.decode(AgentSessionStartedEvent.self, from: data))
        case "session_resumed":
            return .sessionResumed(try decoder.decode(AgentSessionResumedEvent.self, from: data))
        case "session_complete":
            return .sessionComplete(try decoder.decode(AgentSessionCompleteEvent.self, from: data))
        case "session_closed":
            return .sessionClosed(try decoder.decode(AgentSessionClosedEvent.self, from: data))
        case "timeline_update":
            return .timelineUpdate(try decoder.decode(AgentTimelineUpdateEvent.self, from: data))
        case "waiting_for_user":
            return .waitingForUser(try decoder.decode(AgentWaitingForUserEvent.self, from: data))
        case "node_start":
            return .nodeStart(try decoder.decode(AgentNodeLifecycleEvent.self, from: data))
        case "node_complete":
            return .nodeComplete(try decoder.decode(AgentNodeLifecycleEvent.self, from: data))
        case "status_update":
            return .statusUpdate(try decoder.decode(AgentStatusUpdateEvent.self, from: data))
        case "error":
            return .error(try decoder.decode(AgentErrorEvent.self, from: data))
        default:
            return .unknown(envelope.type)
        }
    }
}

private struct AgentSessionStartedEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let uploadedCount: Int?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case uploadedCount = "uploaded_count"
    }
}

private struct AgentSessionResumedEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let iterationCount: Int

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case iterationCount = "iteration_count"
    }
}

private struct AgentSessionCompleteEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?
    let timeline: [AgentTimelineEntry]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
        case timeline
    }
}

private struct AgentSessionClosedEvent: Decodable {
    let sessionID: FlexibleIdentifier

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
    }
}

private struct AgentTimelineUpdateEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let timeline: [AgentTimelineEntry]
    let timelineNotes: [String]

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case timeline
        case timelineNotes = "timeline_notes"
    }
}

private struct AgentWaitingForUserEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let projectID: FlexibleIdentifier?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case projectID = "project_id"
    }
}

private struct AgentNodeLifecycleEvent: Decodable {
    let node: String
    let payload: AgentClipCleanupPayload?
}

private struct AgentClipCleanupPayload: Decodable {
    let node: String?
    let statusMessage: String?
    let inputClips: [AgentInputClip]?
    let inputClipIDs: [FlexibleIdentifier]?
    let clipIDs: [FlexibleIdentifier]?
    let selectedClipIDs: [FlexibleIdentifier]?
    let droppedClipIDs: [FlexibleIdentifier]?
    let clipRanges: [AgentClipRangePayload]?

    enum CodingKeys: String, CodingKey {
        case node
        case statusMessage = "status_message"
        case inputClips = "input_clips"
        case inputClipIDs = "input_clip_ids"
        case clipIDs = "clip_ids"
        case selectedClipIDs = "selected_clip_ids"
        case droppedClipIDs = "dropped_clip_ids"
        case clipRanges = "clip_ranges"
    }
}

private struct AgentInputClip: Decodable {
    let clipID: FlexibleIdentifier
    let summary: String?

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case summary
    }
}

private struct AgentClipRangePayload: Decodable {
    let clipID: FlexibleIdentifier
    let changed: Bool?
    let ranges: [AgentClipRangeEntry]

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case changed
        case ranges
    }
}

private struct AgentClipRangeEntry: Decodable {
    let inSec: Double
    let outSec: Double
    let reason: String

    enum CodingKeys: String, CodingKey {
        case inSec = "in_sec"
        case outSec = "out_sec"
        case reason
    }
}

private struct AgentTimelineEntry: Decodable {
    let clipID: FlexibleIdentifier
    let localKey: String?
    let inSec: Double
    let outSec: Double
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case clipID = "clip_id"
        case localKey = "local_key"
        case inSec = "in_sec"
        case outSec = "out_sec"
        case rationale
    }
}

private struct AgentStatusUpdateEvent: Decodable {
    let sessionID: FlexibleIdentifier
    let node: String?
    let statusMessage: String
    let statusDetails: AgentClipCleanupPayload?

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case node
        case statusMessage = "status_message"
        case statusDetails = "status_details"
    }
}

private struct AgentErrorEvent: Decodable {
    let sessionID: FlexibleIdentifier?
    let detail: String

    enum CodingKeys: String, CodingKey {
        case sessionID = "session_id"
        case detail
    }
}

private struct AgentClientMessage: Encodable {
    let type: String
    let userPrompt: String?
    let prompt: String?

    static func startSession(prompt: String) -> AgentClientMessage {
        AgentClientMessage(type: "start_session", userPrompt: prompt, prompt: nil)
    }

    static func reprompt(prompt: String) -> AgentClientMessage {
        AgentClientMessage(type: "reprompt", userPrompt: nil, prompt: prompt)
    }

    static let done = AgentClientMessage(type: "done", userPrompt: nil, prompt: nil)

    enum CodingKeys: String, CodingKey {
        case type
        case userPrompt = "user_prompt"
        case prompt
    }
}

private struct LocalVideoDescriptor {
    let video: SelectedVideoAsset
    let order: Int
    let localKey: String
    let normalizedStem: String
    let durationSeconds: Double
}

private struct LocalVideoMatch {
    let descriptor: LocalVideoDescriptor
    let strategy: LocalVideoMatchStrategy
}

private enum LocalVideoMatchStrategy: String {
    case localKey
    case exactIndex
    case oneBasedIndex
    case fileNameStem
    case fallbackPosition
    case firstUnused
}

private extension AgentSocketEvent {
    var logDescription: String {
        switch self {
        case .sessionStarted(let payload):
            return "session_started(session_id=\(payload.sessionID.rawValue))"
        case .sessionResumed(let payload):
            return "session_resumed(session_id=\(payload.sessionID.rawValue), iteration=\(payload.iterationCount))"
        case .sessionComplete(let payload):
            return "session_complete(session_id=\(payload.sessionID.rawValue), timeline_count=\(payload.timeline.count))"
        case .sessionClosed(let payload):
            return "session_closed(session_id=\(payload.sessionID.rawValue))"
        case .timelineUpdate(let payload):
            return "timeline_update(session_id=\(payload.sessionID.rawValue), timeline_count=\(payload.timeline.count), notes_count=\(payload.timelineNotes.count))"
        case .waitingForUser(let payload):
            return "waiting_for_user(session_id=\(payload.sessionID.rawValue))"
        case .nodeStart(let payload):
            return "node_start(node=\(payload.node))"
        case .nodeComplete(let payload):
            return "node_complete(node=\(payload.node))"
        case .statusUpdate(let payload):
            return "status_update(session_id=\(payload.sessionID.rawValue), node=\(payload.node ?? "nil"))"
        case .error(let payload):
            return "error(session_id=\(payload.sessionID?.rawValue ?? "nil"))"
        case .unknown(let type):
            return "unknown(type=\(type))"
        }
    }
}

private extension AgentClipCleanupPayload {
    var containsInputClipReferences: Bool {
        inputClips != nil || inputClipIDs != nil
    }

    var containsCompletionDetails: Bool {
        clipIDs != nil || selectedClipIDs != nil || droppedClipIDs != nil || clipRanges != nil
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
