internal import Combine
import Foundation
import OSLog
import SwiftUI

@MainActor
final class CaptionsFlowController: ObservableObject {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "CaptionsFlow"
    )
    private static let transcriptSyncLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "CaptionsTranscriptSync"
    )

    enum Phase: Equatable {
        case idle
        case processing
        case editingStyle(groupId: String)
    }

    @Published var phase: Phase = .idle
    @Published var rangeStartUs: Int64?
    @Published var rangeEndUs: Int64?
    @Published var validationMessage: String?
    /// Shown in an alert when the flow returns to `idle` (e.g. generation failed).
    @Published var captionsAlert: String?
    @Published var selectedCaptionCueId: String?
    /// Identifier of the currently expanded caption style tool (e.g. "style", "background").
    /// `nil` when the editor row is showing the collapsed tool icons.
    @Published var expandedStyleTool: String?

    weak var timelineController: TimelineController?
    private let captionsService = CaptionsService()

    var isCaptionsChromeActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    var playheadUsesAccentTint: Bool { false }

    func highlightRangeUs(playheadUs: Int64) -> ClosedRange<Int64>? {
        _ = playheadUs
        if let s = rangeStartUs, let e = rangeEndUs, e > s { return s...e }
        return nil
    }

    func attach(_ controller: TimelineController) {
        timelineController = controller
    }

    /// Starts transcript-based captions for the full timeline (no scope sheet).
    func startAutoCaptionsForWholeTimeline() {
        validationMessage = nil
        captionsAlert = nil
        rangeStartUs = nil
        rangeEndUs = nil
        selectedCaptionCueId = nil
        guard let controller = timelineController else { return }
        let end = max(controller.state.calculatedTimelineDurationUs, 1)
        rangeStartUs = 0
        rangeEndUs = end
        phase = .processing
        Task { @MainActor in
            await runProcessing(controller: controller)
        }
    }

    func cancelFlow() {
        phase = .idle
        rangeStartUs = nil
        rangeEndUs = nil
        validationMessage = nil
        captionsAlert = nil
        expandedStyleTool = nil
    }

    func openStyleEditor(forGroupId groupId: String) {
        phase = .editingStyle(groupId: groupId)
    }

    func openStyleEditor(forCueId cueId: String) {
        guard let controller = timelineController else { return }
        guard let cue = controller.state.captionCues.first(where: { $0.cueId == cueId }) else { return }
        openStyleEditor(forGroupId: cue.groupId)
    }

    func updateEditingGroup(style: CaptionStyle, hasBackground: Bool) {
        guard case let .editingStyle(groupId) = phase else { return }
        guard let controller = timelineController else { return }
        guard var g = controller.captionGroup(withId: groupId) else { return }
        g.style = style
        g.hasBackground = hasBackground
        g.updatedAt = Date()
        do {
            try controller.applyCaptionGroupStyleUpdate(g)
        } catch {
            print("Failed to update caption group: \(error)")
        }
    }

    func finishStyleEditing() {
        phase = .idle
        expandedStyleTool = nil
    }

    /// Clears caption cue selection and dismisses the style chrome (e.g. when the user selects a clip).
    func cancelStyleEditing() {
        selectedCaptionCueId = nil
        expandedStyleTool = nil
        if case .editingStyle = phase {
            phase = .idle
        }
    }

    private func failToIdle(_ message: String) {
        validationMessage = nil
        captionsAlert = message
        phase = .idle
        expandedStyleTool = nil
    }

    private func runProcessing(controller: TimelineController) async {
        guard let start = rangeStartUs, let end = rangeEndUs, end > start else {
            Self.logger.error("[CaptionsFlow] invalid range start=\(self.rangeStartUs ?? -1, privacy: .public) end=\(self.rangeEndUs ?? -1, privacy: .public)")
            failToIdle("Invalid caption range.")
            return
        }

        await controller.refreshBackendProjectMappingFromStoreIfNeeded()

        let backendProjectId = controller.state.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let timelineId = controller.state.timelineId
        let localProjectId = controller.state.timeline?.projectId ?? "nil"
        let mediaWithUploadKeys = controller.state.mediaById.values.reduce(into: [String]()) { result, media in
            let key = media.spec.clipUploadLocalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !key.isEmpty {
                result.append(key)
            }
        }
        let mediaWithUploadKeysSummary = mediaWithUploadKeys.joined(separator: ",")
        Self.logger.notice(
            """
            [CaptionsFlow] start timeline=\(timelineId, privacy: .public) \
            localProject=\(localProjectId, privacy: .public) \
            backendProject=\(backendProjectId.isEmpty ? "nil" : backendProjectId, privacy: .public) \
            totalTracks=\(controller.state.tracks.count, privacy: .public) \
            totalClips=\(controller.state.clips.count, privacy: .public) \
            mediaCount=\(controller.state.mediaById.count, privacy: .public) \
            mediaUploadKeys=\(mediaWithUploadKeysSummary, privacy: .public) \
            rangeUs=\(start, privacy: .public)...\(end, privacy: .public)
            """
        )
        guard !backendProjectId.isEmpty else {
            Self.logger.error(
                """
                [CaptionsFlow] missing backend project mapping timeline=\(timelineId, privacy: .public) \
                localProject=\(localProjectId, privacy: .public) \
                overlappingClipCandidates=\(controller.state.clips.count, privacy: .public) \
                mediaUploadKeys=\(mediaWithUploadKeysSummary, privacy: .public)
                """
            )
            failToIdle("This project is not linked to the cloud yet. Open it from import or wait until processing finishes so captions can load.")
            return
        }

        guard let videoTrack = controller.state.tracks.first(where: { $0.kind == .video }) else {
            Self.logger.error("[CaptionsFlow] no video track timeline=\(timelineId, privacy: .public)")
            failToIdle("Add a video clip first.")
            return
        }

        let clips = controller.state.clips.filter { $0.trackId == videoTrack.trackId }
        let overlapping: [(Clip, Media)] = clips.compactMap { clip in
            guard clip.timelineRange.end > start, clip.timelineRange.start < end else { return nil }
            guard let media = controller.state.mediaById[clip.mediaId] else { return nil }
            return (clip, media)
        }

        guard !overlapping.isEmpty else {
            Self.logger.error(
                "[CaptionsFlow] no overlapping video clips timeline=\(timelineId, privacy: .public) videoTrack=\(videoTrack.trackId, privacy: .public) rangeUs=\(start, privacy: .public)...\(end, privacy: .public)"
            )
            failToIdle("No video clips in this range.")
            return
        }

        let clipsWithUploadKeys = overlapping.filter { pair in
            guard let key = pair.1.spec.clipUploadLocalKey else { return false }
            return !key.isEmpty
        }
        let overlappingSummary = overlapping.map { clip, media in
            "\(clip.clipId):\(media.mediaId):\(media.spec.clipUploadLocalKey ?? "nil")"
        }.joined(separator: ",")
        Self.logger.notice(
            "[CaptionsFlow] overlapping clips timeline=\(timelineId, privacy: .public) clips=\(overlappingSummary, privacy: .public)"
        )
        guard !clipsWithUploadKeys.isEmpty else {
            Self.logger.error(
                "[CaptionsFlow] overlapping clips missing upload keys timeline=\(timelineId, privacy: .public) clips=\(overlappingSummary, privacy: .public)"
            )
            failToIdle("These clips are not linked to processed uploads yet. Re-import the video or finish backend processing before adding captions.")
            return
        }

        var inputs: [CaptionsStitcher.ClipTranscriptInput] = []
        var remoteByKey: [String: RemoteClipCaptions] = [:]
        var sawTranscriptNotReady = false
        var hadFetchFailure = false

        for (clip, media) in clipsWithUploadKeys {
            guard let key = media.spec.clipUploadLocalKey, !key.isEmpty else { continue }
            do {
                let remote: RemoteClipCaptions
                if let cached = remoteByKey[key] {
                    remote = cached
                } else {
                    Self.logger.notice(
                        """
                        [CaptionsFlow] requesting captions timeline=\(timelineId, privacy: .public) \
                        backendProject=\(backendProjectId, privacy: .public) \
                        localKey=\(key, privacy: .public) \
                        clipId=\(clip.clipId, privacy: .public) \
                        mediaId=\(media.mediaId, privacy: .public) \
                        clipRangeUs=\(clip.timelineRange.start, privacy: .public)...\(clip.timelineRange.end, privacy: .public)
                        """
                    )
                    remote = try await captionsService.fetchCaptions(projectId: backendProjectId, localKey: key)
                    remoteByKey[key] = remote
                    Self.logger.notice(
                        """
                        [CaptionsFlow] captions loaded timeline=\(timelineId, privacy: .public) \
                        localKey=\(key, privacy: .public) \
                        clipId=\(remote.clipId, privacy: .public) \
                        transcriptId=\(remote.transcriptId ?? -1, privacy: .public) \
                        status=\(remote.processingStatus, privacy: .public) \
                        sentenceCount=\(remote.sentences.count, privacy: .public)
                        """
                    )
                }

                syncRemoteTranscriptMetadata(remote, media: media)
                inputs.append(CaptionsStitcher.ClipTranscriptInput(clip: clip, media: media, captions: remote))
            } catch let captionsError as CaptionsServiceError {
                hadFetchFailure = true
                if case .transcriptNotReady = captionsError {
                    sawTranscriptNotReady = true
                }
                Self.logger.error(
                    "[CaptionsFlow] captions request failed localKey=\(key, privacy: .public) error=\(String(describing: captionsError), privacy: .public)"
                )
                print("[CaptionsFlow] skip local_key=\(key) error=\(captionsError)")
            } catch {
                hadFetchFailure = true
                Self.logger.error(
                    "[CaptionsFlow] captions request failed localKey=\(key, privacy: .public) error=\(String(describing: error), privacy: .public)"
                )
                print("[CaptionsFlow] skip local_key=\(key) error=\(error)")
            }
        }

        let cues = CaptionsStitcher.stitch(inputs: inputs, rangeStartUs: start, rangeEndUs: end)
        guard !cues.isEmpty else {
            Self.logger.error(
                """
                [CaptionsFlow] produced no cues timeline=\(timelineId, privacy: .public) \
                transcriptInputs=\(inputs.count, privacy: .public) \
                hadFetchFailure=\(hadFetchFailure, privacy: .public) \
                sawTranscriptNotReady=\(sawTranscriptNotReady, privacy: .public)
                """
            )
            if sawTranscriptNotReady {
                failToIdle("Transcript is still processing. Try adding captions again in a few moments.")
            } else if hadFetchFailure {
                failToIdle("Could not load transcripts for your clips. Check that the project is linked and clips finished processing, then try again.")
            } else {
                failToIdle("No captions found for this range.")
            }
            return
        }

        do {
            let groupId = try controller.finalizeCaptionGeneration(
                rangeStartUs: start,
                rangeEndUs: end,
                cues: cues,
                style: CaptionStyle.modern
            )
            Self.logger.notice(
                "[CaptionsFlow] finalized captions timeline=\(timelineId, privacy: .public) groupId=\(groupId, privacy: .public) cueCount=\(cues.count, privacy: .public)"
            )
            rangeStartUs = nil
            rangeEndUs = nil
            phase = .editingStyle(groupId: groupId)
        } catch {
            Self.logger.error(
                "[CaptionsFlow] persist failed timeline=\(timelineId, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
            failToIdle("Could not save captions.")
            print("[CaptionsFlow] persist error: \(error)")
        }
    }

    private func syncRemoteTranscriptMetadata(_ remote: RemoteClipCaptions, media: Media) {
        guard let transcriptId = remote.transcriptId else { return }
        let transcriptID = String(transcriptId)
        do {
            guard let updated = try DatabaseManager.shared.updateMediaSpec(mediaId: media.mediaId, mutate: { spec in
                let existing = spec.transcriptID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existing.isEmpty {
                    spec.transcriptID = transcriptID
                }
                if spec.transcriptFullText?.isEmpty ?? true {
                    spec.transcriptFullText = remote.fullText
                }
                if spec.transcriptSentences?.isEmpty ?? true {
                    spec.transcriptSentences = remote.sentences.map {
                        MediaTranscriptSentence(
                            text: $0.text,
                            startTimeSeconds: $0.start,
                            endTimeSeconds: $0.end,
                            confidence: $0.confidence,
                            speaker: nil,
                            channel: nil
                        )
                    }
                }
                let existingKey = spec.clipUploadLocalKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                if existingKey.isEmpty {
                    spec.clipUploadLocalKey = remote.localKey
                }
            }) else {
                Self.transcriptSyncLogger.error(
                    "[CaptionsFlow] transcript sync skipped missing media mediaId=\(media.mediaId, privacy: .public) transcriptID=\(transcriptID, privacy: .public)"
                )
                return
            }
            NotificationCenter.default.post(
                name: .irisMediaTranscriptDidPersist,
                object: nil,
                userInfo: ["mediaId": media.mediaId]
            )
            Self.transcriptSyncLogger.notice(
                "[CaptionsFlow] transcript synced mediaId=\(media.mediaId, privacy: .public) transcriptID=\(updated.spec.transcriptID ?? "nil", privacy: .public) sentences=\(updated.spec.transcriptSentences?.count ?? 0, privacy: .public)"
            )
        } catch {
            Self.transcriptSyncLogger.error(
                "[CaptionsFlow] transcript sync failed mediaId=\(media.mediaId, privacy: .public) transcriptID=\(transcriptID, privacy: .public) error=\(String(describing: error), privacy: .public)"
            )
        }
    }
}
