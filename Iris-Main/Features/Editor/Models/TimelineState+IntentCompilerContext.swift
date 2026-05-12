import Foundation

extension TimelineState {
    func makeIntentCompilerContext(forcingActiveClipId forcedClipId: String? = nil) -> IntentCompilerContext {
        let activeClip = resolvedIntentContextClip(forcingActiveClipId: forcedClipId)
        let projectId = timeline.flatMap { tid in
            let pid = tid.projectId
            return pid.isEmpty ? nil : pid
        }
        let transcriptRefs = transcriptContextRefsByClipId()

        return IntentCompilerContext(
            timelineId: timelineId,
            projectId: projectId,
            sessionId: nil,
            selectedClipId: activeClip?.clipId,
            selectedTrackId: activeClip?.trackId,
            selectedRange: activeClip?.timelineRange,
            playheadTimeUs: currentTimeAtCenter,
            clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) }),
            orderedClipIdsByTrackId: orderedClipIdsByTrackId(),
            transcriptContextsByClipId: transcriptRefs
        )
    }

    /// Lightweight transcript refs for backend hydration (transcript id only; no local transcript text).
    private func transcriptContextRefsByClipId() -> [String: ClipTranscriptContext] {
        var refs: [String: ClipTranscriptContext] = [:]
        for clip in clips {
            guard let media = mediaById[clip.mediaId],
                  let transcriptId = media.spec.transcriptID?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !transcriptId.isEmpty
            else { continue }
            refs[clip.clipId] = ClipTranscriptContext(clipId: clip.clipId, transcriptId: transcriptId)
        }
        return refs
    }

    private func resolvedIntentContextClip(forcingActiveClipId forcedClipId: String?) -> Clip? {
        if let forcedClipId, let clip = clips.first(where: { $0.clipId == forcedClipId }) {
            return clip
        }

        if let selectedClipId, let clip = clips.first(where: { $0.clipId == selectedClipId }) {
            return clip
        }

        return clipUnderPlayhead()
    }

    private func clipUnderPlayhead() -> Clip? {
        let timeUs = currentTimeAtCenter
        let clipsByTrack = clipsByTrackId

        if let videoClip = orderedTracks
            .filter({ $0.kind == .video })
            .compactMap({ track in
                clipsByTrack[track.trackId]?.first { clip in
                    clip.timelineRange.start <= timeUs && timeUs < clip.timelineRange.end
                }
            })
            .first {
            return videoClip
        }

        return orderedTracks
            .compactMap { track in
                clipsByTrack[track.trackId]?.first { clip in
                    clip.timelineRange.start <= timeUs && timeUs < clip.timelineRange.end
                }
            }
            .first
    }

    private func orderedClipIdsByTrackId() -> [String: [String]] {
        var result: [String: [String]] = [:]
        for track in orderedTracks {
            result[track.trackId] = orderedClips(for: track.trackId).map(\.clipId)
        }

        let knownTrackIds = Set(result.keys)
        for trackId in clipsByTrackId.keys where !knownTrackIds.contains(trackId) {
            result[trackId] = orderedClips(for: trackId).map(\.clipId)
        }

        return result
    }
}
