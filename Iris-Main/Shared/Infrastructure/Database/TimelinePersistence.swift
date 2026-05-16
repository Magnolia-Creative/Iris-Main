import Foundation
import OSLog

struct TimelinePersistence {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Magnolia-Creative.Iris-Main",
        category: "TimelinePersistence"
    )
    let db: DatabaseManager

    init(db: DatabaseManager = .shared) {
        self.db = db
    }

    struct LoadedData {
        let timeline: Timeline
        let tracks: [Track]
        let clips: [Clip]
        let effects: [Effect]
        let mediaLibrary: MediaLibrary?
        let mediaById: [String: Media]
        let projectTitle: String
        /// Full project row when present (resolution, manual aspect override, etc.).
        let project: Project?
        let backendProjectId: String?
        let captionGroups: [CaptionGroup]
        let captionCues: [CaptionCue]
    }

    enum PersistenceError: Error {
        case timelineNotFound(String)
    }

    func loadTimelineData(timelineId: String) throws -> LoadedData {
        guard let timeline = try db.get(Timeline.self, id: timelineId, keyColumn: "timeline_id") else {
            throw PersistenceError.timelineNotFound(timelineId)
        }

        let tracks = try db.ensureCoreTracks(forTimelineId: timeline.timelineId)
        let clips = try db.getClips(forTimelineId: timeline.timelineId)
        let effects = try db.getEffects(forTimelineId: timeline.timelineId)
        let captionGroups = try db.getCaptionGroups(forTimelineId: timeline.timelineId)
        let captionCues = try db.getCaptionCues(forTimelineId: timeline.timelineId)
        let mediaLibrary = try db.getMediaLibrary(forProjectId: timeline.projectId)
        let project = try db.get(Project.self, id: timeline.projectId, keyColumn: "project_id")

        var media: [Media] = []
        if let library = mediaLibrary {
            media = try db.getAllMedia(forLibraryId: library.id)
        }

        let trimmedBackendId = project?.backendProjectId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let backendProjectId: String? = trimmedBackendId.isEmpty ? nil : trimmedBackendId
        Self.logger.notice(
            """
            [TimelinePersistence] loaded timeline=\(timeline.timelineId, privacy: .public) \
            localProject=\(timeline.projectId, privacy: .public) \
            projectFound=\(project != nil, privacy: .public) \
            backendProjectRaw=\(project?.backendProjectId ?? "nil", privacy: .public) \
            backendProjectTrimmed=\(backendProjectId ?? "nil", privacy: .public) \
            mediaLibrary=\(mediaLibrary?.id ?? "nil", privacy: .public) \
            mediaCount=\(media.count, privacy: .public) \
            clipCount=\(clips.count, privacy: .public)
            """
        )

        return LoadedData(
            timeline: timeline,
            tracks: tracks,
            clips: clips,
            effects: effects,
            mediaLibrary: mediaLibrary,
            mediaById: Dictionary(uniqueKeysWithValues: media.map { ($0.mediaId, $0) }),
            projectTitle: project?.name ?? "Project",
            project: project,
            backendProjectId: backendProjectId,
            captionGroups: captionGroups,
            captionCues: captionCues
        )
    }

    // MARK: - Write Operations

    func createClip(_ clip: Clip) throws {
        try db.create(clip)
    }

    func updateClip(_ clip: Clip) throws {
        try db.update(clip)
    }

    func deleteClip(clipId: String) throws {
        try db.delete(Clip.self, id: clipId, keyColumn: "clip_id")
    }

    func createTrack(_ track: Track) throws {
        try db.createTrack(track)
    }

    func updateTrack(_ track: Track) throws {
        try db.update(track)
    }

    func updateTimeline(_ timeline: Timeline) throws {
        try db.update(timeline)
    }

    func createEffect(_ effect: Effect) throws {
        try db.create(effect)
    }

    func createCaptionGroup(_ group: CaptionGroup) throws {
        try db.create(group)
    }

    func updateCaptionGroup(_ group: CaptionGroup) throws {
        try db.update(group)
    }

    func createCaptionCue(_ cue: CaptionCue) throws {
        try db.create(cue)
    }

    func updateCaptionCue(_ cue: CaptionCue) throws {
        try db.update(cue)
    }

    func deleteCaptionCue(cueId: String) throws {
        try db.delete(CaptionCue.self, id: cueId, keyColumn: "cue_id")
    }

    /// Deletes a caption group; cues are removed via ON DELETE CASCADE on `caption_cues.group_id`.
    func deleteCaptionGroup(groupId: String) throws {
        try db.delete(CaptionGroup.self, id: groupId, keyColumn: "group_id")
    }

    func updateEffect(_ effect: Effect) throws {
        try db.update(effect)
    }

    func deleteEffect(effectId: String) throws {
        try db.delete(Effect.self, id: effectId, keyColumn: "effect_id")
    }
}
