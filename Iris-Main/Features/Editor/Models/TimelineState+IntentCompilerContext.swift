import Foundation
import OSLog

extension TimelineState {
    private static let intentTranscriptRefsLog = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "IntentTranscriptRefs"
    )

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
        var clipIdsMissingMedia: [String] = []
        var clipIdsMissingTranscriptID: [(clipId: String, mediaId: String)] = []

        for clip in clips {
            guard let media = mediaById[clip.mediaId] else {
                clipIdsMissingMedia.append(clip.clipId)
                continue
            }
            let trimmed = media.spec.transcriptID?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if trimmed.isEmpty {
                let sentenceCount = media.spec.transcriptSentences?.count ?? 0
                let hasFullText = !(media.spec.transcriptFullText?.isEmpty ?? true)
                clipIdsMissingTranscriptID.append((clip.clipId, clip.mediaId))
                Self.intentTranscriptRefsLog.debug(
                    "clip=\(clip.clipId, privacy: .public) media=\(clip.mediaId, privacy: .public) transcriptID=nil-or-empty sentences=\(sentenceCount, privacy: .public) hasFullText=\(hasFullText, privacy: .public)"
                )
                continue
            }
            refs[clip.clipId] = ClipTranscriptContext(clipId: clip.clipId, transcriptId: trimmed)
        }

        Self.intentTranscriptRefsLog.info(
            "makeIntentCompilerContext timeline=\(timelineId, privacy: .public) clipCount=\(clips.count, privacy: .public) mediaByIdCount=\(mediaById.count, privacy: .public) transcriptRefCount=\(refs.count, privacy: .public) missingMediaForClip=\(clipIdsMissingMedia.count, privacy: .public) missingTranscriptID=\(clipIdsMissingTranscriptID.count, privacy: .public)"
        )
        if !clipIdsMissingMedia.isEmpty {
            Self.intentTranscriptRefsLog.warning(
                "clips with mediaId not found in mediaById (first 8): \(clipIdsMissingMedia.prefix(8).joined(separator: ","), privacy: .public)"
            )
        }
        if !clipIdsMissingTranscriptID.isEmpty {
            let sample = clipIdsMissingTranscriptID.prefix(6).map { "\($0.clipId)->\($0.mediaId)" }.joined(separator: ", ")
            Self.intentTranscriptRefsLog.warning(
                "clips whose media has no transcriptID for intent refs (first 6 clip->media): \(sample, privacy: .public)"
            )
        }
        if !refs.isEmpty {
            let pairs = refs.map { "\($0.key):\($0.value.transcriptId ?? "?")" }.sorted().joined(separator: ", ")
            Self.intentTranscriptRefsLog.info("transcriptContextsByClipId keys->transcriptId: \(pairs, privacy: .public)")
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
