internal import Combine
import Foundation
import SwiftUI

@MainActor
final class CaptionsFlowController: ObservableObject {
    enum Phase: Equatable {
        case idle
        case chooseScope
        case pickingStart
        case pickingEnd
        case processing
        case editingStyle(groupId: String)
    }

    @Published var phase: Phase = .idle
    @Published var rangeStartUs: Int64?
    @Published var rangeEndUs: Int64?
    @Published var validationMessage: String?
    @Published var selectedCaptionCueId: String?

    weak var timelineController: TimelineController?
    private let captionsService = CaptionsService()

    var isCaptionsChromeActive: Bool {
        if case .idle = phase { return false }
        return true
    }

    var playheadUsesAccentTint: Bool {
        switch phase {
        case .pickingStart, .pickingEnd: return true
        default: return false
        }
    }

    func highlightRangeUs(playheadUs: Int64) -> ClosedRange<Int64>? {
        switch phase {
        case .pickingEnd:
            guard let s = rangeStartUs else { return nil }
            let e = max(playheadUs, s + 1)
            return s...e
        case .processing, .editingStyle, .chooseScope, .pickingStart, .idle:
            if let s = rangeStartUs, let e = rangeEndUs, e > s { return s...e }
            return nil
        }
    }

    func attach(_ controller: TimelineController) {
        timelineController = controller
    }

    func beginCaptionsFlow() {
        validationMessage = nil
        rangeStartUs = nil
        rangeEndUs = nil
        selectedCaptionCueId = nil
        phase = .chooseScope
    }

    func chooseCaptionWholeTimeline() {
        guard let controller = timelineController else { return }
        let end = max(controller.state.calculatedTimelineDurationUs, 1)
        rangeStartUs = 0
        rangeEndUs = end
        phase = .processing
        Task {
            await runProcessing(controller: controller)
        }
    }

    func chooseDefineCaptionRange() {
        phase = .pickingStart
    }

    func confirmRangeStartAtPlayhead(_ playheadUs: Int64) {
        rangeStartUs = playheadUs
        validationMessage = nil
        phase = .pickingEnd
    }

    func confirmRangeEndAtPlayhead(_ playheadUs: Int64) {
        guard rangeStartUs != nil else { return }
        guard let start = rangeStartUs else { return }
        if playheadUs <= start {
            validationMessage = "End must be after start."
            return
        }
        validationMessage = nil
        rangeEndUs = playheadUs
        phase = .processing
        guard let controller = timelineController else { return }
        Task { await runProcessing(controller: controller) }
    }

    func cancelFlow() {
        phase = .idle
        rangeStartUs = nil
        rangeEndUs = nil
        validationMessage = nil
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
    }

    private func runProcessing(controller: TimelineController) async {
        guard let start = rangeStartUs, let end = rangeEndUs, end > start else {
            validationMessage = "Invalid caption range."
            phase = .idle
            return
        }

        let backendProjectId = controller.state.timeline?.projectId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !backendProjectId.isEmpty else {
            validationMessage = "Project is not linked for transcripts yet."
            phase = .idle
            return
        }

        guard let videoTrack = controller.state.tracks.first(where: { $0.kind == .video }) else {
            validationMessage = "Add a video clip first."
            phase = .idle
            return
        }

        let clips = controller.state.clips.filter { $0.trackId == videoTrack.trackId }
        let overlapping: [(Clip, Media)] = clips.compactMap { clip in
            guard clip.timelineRange.end > start, clip.timelineRange.start < end else { return nil }
            guard let media = controller.state.mediaById[clip.mediaId] else { return nil }
            return (clip, media)
        }

        var inputs: [CaptionsStitcher.ClipTranscriptInput] = []
        var seenKeys = Set<String>()

        for (clip, media) in overlapping {
            guard let key = media.spec.clipUploadLocalKey, !key.isEmpty else { continue }
            guard seenKeys.insert(key).inserted else { continue }
            do {
                let remote = try await captionsService.fetchCaptions(projectId: backendProjectId, localKey: key)
                inputs.append(CaptionsStitcher.ClipTranscriptInput(clip: clip, media: media, captions: remote))
            } catch {
                print("[CaptionsFlow] skip local_key=\(key) error=\(error)")
            }
        }

        let cues = CaptionsStitcher.stitch(inputs: inputs, rangeStartUs: start, rangeEndUs: end)
        guard !cues.isEmpty else {
            validationMessage = "No captions found for this range."
            phase = .chooseScope
            return
        }

        do {
            let groupId = try controller.finalizeCaptionGeneration(
                rangeStartUs: start,
                rangeEndUs: end,
                cues: cues,
                style: CaptionStyle.modern
            )
            rangeStartUs = nil
            rangeEndUs = nil
            phase = .editingStyle(groupId: groupId)
        } catch {
            validationMessage = "Could not save captions."
            phase = .idle
            print("[CaptionsFlow] persist error: \(error)")
        }
    }
}
