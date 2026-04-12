import Foundation
import GRDB

final class DatabaseManager {
    static let shared = DatabaseManager()
    let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    private convenience init() {
        do {
            let fileURL = try FileManager.default
                .url(for: .applicationSupportDirectory,
                     in: .userDomainMask,
                     appropriateFor: nil,
                     create: true)
                .appendingPathComponent("iris.sqlite")

            let queue = try DatabaseQueue(path: fileURL.path)
            try DatabaseManager.prepareDatabase(queue)
            self.init(dbQueue: queue)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    // MARK: - Generic CRUD

    func create<T: FetchableRecord & PersistableRecord>(_ model: T) throws {
        try dbQueue.write { db in
            try model.insert(db)
        }
    }

    func get<T: FetchableRecord & PersistableRecord>(_ type: T.Type, id: String, keyColumn: String) throws -> T? {
        try dbQueue.read { db in
            try T.filter(Column(keyColumn) == id).fetchOne(db)
        }
    }

    func getAll<T: FetchableRecord & PersistableRecord>(_ type: T.Type, orderedBy column: String = "updated_at") throws -> [T] {
        try dbQueue.read { db in
            try T.order(Column(column).desc).fetchAll(db)
        }
    }

    func update<T: FetchableRecord & PersistableRecord>(_ model: T) throws {
        try dbQueue.write { db in
            try model.update(db)
        }
    }

    func delete<T: FetchableRecord & PersistableRecord>(_ type: T.Type, id: String, keyColumn: String) throws {
        _ = try dbQueue.write { db in
            try T.filter(Column(keyColumn) == id).deleteAll(db)
        }
    }
}

// MARK: - Migrations
extension DatabaseManager {
    static func makeInMemory() throws -> DatabaseManager {
        let queue = try DatabaseQueue()
        try prepareDatabase(queue)
        return DatabaseManager(dbQueue: queue)
    }

    private static func prepareDatabase(_ dbQueue: DatabaseQueue) throws {
        try dbQueue.write { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        try DatabaseManager.migrator.migrate(dbQueue)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_createProjects") { db in
            try db.create(table: "projects") { t in
                t.column("project_id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("description", .text)
                t.column("schema_version", .text).notNull()
                t.column("resolution_width", .integer).notNull().defaults(to: 1920)
                t.column("resolution_height", .integer).notNull().defaults(to: 1080)
                t.column("frame_rate", .integer).notNull().defaults(to: 30)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        migrator.registerMigration("v1_createMediaLibraries") { db in
            try db.create(table: "media_libraries") { t in
                t.column("media_library_id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", column: "project_id", onDelete: .cascade)
                t.column("schema_version", .text).notNull()
                t.column("settings", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
        }

        migrator.registerMigration("v1_createAssetReferences") { db in
            try db.create(table: "asset_references") { t in
                t.column("asset_ref_id", .text).primaryKey()
                t.column("location_type", .text).notNull()
                t.column("uri", .text).notNull()
                t.column("variants", .text)
                t.column("checksum", .text)
            }
        }

        migrator.registerMigration("v1_createMedia") { db in
            try db.create(table: "media") { t in
                t.column("media_id", .text).primaryKey()
                t.column("media_library_id", .text).notNull()
                    .references("media_libraries", column: "media_library_id", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("asset_ref_id", .text).notNull()
                    .references("asset_references", column: "asset_ref_id", onDelete: .cascade)
                t.column("spec", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "index_media_on_media_library_id",
                         on: "media", columns: ["media_library_id"])
        }

        migrator.registerMigration("v2_createTimelines") { db in
            try db.create(table: "timelines") { t in
                t.column("timeline_id", .text).primaryKey()
                t.column("project_id", .text).notNull()
                    .references("projects", column: "project_id", onDelete: .cascade)
                t.column("schema_version", .text).notNull()
                t.column("timebase", .text).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "index_timelines_on_project_id",
                         on: "timelines", columns: ["project_id"])
        }

        migrator.registerMigration("v2_createTracks") { db in
            try db.create(table: "tracks") { t in
                t.column("track_id", .text).primaryKey()
                t.column("timeline_id", .text).notNull()
                    .references("timelines", column: "timeline_id", onDelete: .cascade)
                t.column("kind", .text).notNull()
                t.column("ordering", .text).notNull()
                t.column("sort_index", .integer).notNull().defaults(to: 0)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "index_tracks_on_timeline_id",
                         on: "tracks", columns: ["timeline_id", "sort_index"])
        }

        migrator.registerMigration("v2_createClips") { db in
            try db.create(table: "clips") { t in
                t.column("clip_id", .text).primaryKey()
                t.column("track_id", .text).notNull()
                    .references("tracks", column: "track_id", onDelete: .cascade)
                t.column("media_id", .text).notNull()
                    .references("media", column: "media_id", onDelete: .cascade)
                t.column("source_start_us", .integer).notNull()
                t.column("source_end_us", .integer).notNull()
                t.column("timeline_start_us", .integer).notNull()
                t.column("timeline_end_us", .integer).notNull()
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "index_clips_on_track_id",
                         on: "clips", columns: ["track_id", "timeline_start_us"])
        }

        migrator.registerMigration("v2_createEffects") { db in
            try db.create(table: "effects") { t in
                t.column("effect_id", .text).primaryKey()
                t.column("timeline_id", .text).notNull()
                    .references("timelines", column: "timeline_id", onDelete: .cascade)
                t.column("applies_to", .text).notNull()
                t.column("target_id", .text).notNull()
                t.column("type", .text).notNull()
                t.column("parameters", .text).notNull()
                t.column("constraints", .text)
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
            }
            try db.create(index: "index_effects_on_timeline_id",
                         on: "effects", columns: ["timeline_id"])
        }

        migrator.registerMigration("v2_createTimelineActions") { db in
            try db.create(table: "timeline_actions") { t in
                t.column("action_id", .text).primaryKey()
                t.column("timeline_id", .text).notNull()
                    .references("timelines", column: "timeline_id", onDelete: .cascade)
                t.column("created_at", .datetime).notNull()
                t.column("type", .text).notNull()
                t.column("target_id", .text)
                t.column("parameters", .text)
                t.column("group_id", .text)
            }
            try db.create(index: "index_timeline_actions_on_timeline_id",
                         on: "timeline_actions", columns: ["timeline_id", "created_at"])
        }

        migrator.registerMigration("v3_addProjectPresentationMetadata") { db in
            try db.alter(table: "projects") { t in
                t.add(column: "cover_image_path", .text)
                t.add(column: "last_accessed_at", .datetime)
            }
        }

        return migrator
    }
}

// MARK: - Media Query Helpers
extension DatabaseManager {
    func getProject(forMediaLibraryId mediaLibraryId: String) throws -> Project? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT p.*
                FROM projects p
                INNER JOIN media_libraries ml ON ml.project_id = p.project_id
                WHERE ml.media_library_id = ?
                LIMIT 1
                """,
                arguments: [mediaLibraryId]
            ).map(Project.init(row:))
        }
    }

    func getMediaLibrary(forProjectId projectId: String) throws -> MediaLibrary? {
        try dbQueue.read { db in
            try MediaLibrary
                .filter(MediaLibrary.Columns.projectId == projectId)
                .order(MediaLibrary.Columns.createdAt.asc)
                .fetchOne(db)
        }
    }

    func getAllMedia(forLibraryId libraryId: String) throws -> [Media] {
        try dbQueue.read { db in
            try Media.filter(Media.Columns.mediaLibraryId == libraryId)
                .order(Media.Columns.createdAt.desc)
                .fetchAll(db)
        }
    }

    func getMedia(mediaId: String) throws -> Media? {
        try get(Media.self, id: mediaId, keyColumn: "media_id")
    }

    func deleteAllMedia(forLibraryId libraryId: String) throws {
        _ = try dbQueue.write { db in
            try Media.filter(Media.Columns.mediaLibraryId == libraryId).deleteAll(db)
        }
    }
}

// MARK: - AssetReference Query Helpers
extension DatabaseManager {
    func getAssetReference(assetRefId: String) throws -> AssetReference? {
        try get(AssetReference.self, id: assetRefId, keyColumn: "asset_ref_id")
    }

    func assetReferenceExists(uri: String) throws -> AssetReference? {
        try dbQueue.read { db in
            try AssetReference.filter(Column("uri") == uri).fetchOne(db)
        }
    }
}

// MARK: - Timeline Query Helpers
extension DatabaseManager {
    func getTimeline(forProjectId projectId: String) throws -> Timeline? {
        try dbQueue.read { db in
            try Timeline.filter(Timeline.Columns.projectId == projectId)
                .order(Timeline.Columns.createdAt.asc)
                .fetchOne(db)
        }
    }

    func createTimeline(forProjectId projectId: String, schemaVersion: String = "1.0", timebase: String = "microseconds") throws -> Timeline {
        let timeline = Timeline(projectId: projectId, schemaVersion: schemaVersion, timebase: timebase)
        try create(timeline)
        return timeline
    }

    func getTracks(forTimelineId timelineId: String) throws -> [Track] {
        try dbQueue.read { db in
            try Track.filter(Track.Columns.timelineId == timelineId)
                .order(Track.Columns.sortIndex.asc)
                .fetchAll(db)
        }
    }

    func ensureCoreTracks(forTimelineId timelineId: String) throws -> [Track] {
        var tracks = try getTracks(forTimelineId: timelineId)
        let requiredKinds: [TrackKind] = [.overlay, .video, .audio]

        for kind in requiredKinds where !tracks.contains(where: { $0.kind == kind }) {
            let sortIndex = tracks.count
            let track = Track(timelineId: timelineId, kind: kind, sortIndex: sortIndex)
            try create(track)
            tracks.append(track)
        }

        tracks.sort { lhs, rhs in
            Self.trackDisplayOrder(lhs.kind) == Self.trackDisplayOrder(rhs.kind)
                ? lhs.sortIndex < rhs.sortIndex
                : Self.trackDisplayOrder(lhs.kind) < Self.trackDisplayOrder(rhs.kind)
        }
        return tracks
    }

    func getClips(forTimelineId timelineId: String) throws -> [Clip] {
        try dbQueue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT c.*
                FROM clips c
                INNER JOIN tracks t ON c.track_id = t.track_id
                WHERE t.timeline_id = ?
                ORDER BY c.timeline_start_us ASC
                """,
                arguments: [timelineId]
            ).map(Clip.init(row:))
        }
    }

    func getEffects(forTimelineId timelineId: String) throws -> [Effect] {
        try dbQueue.read { db in
            try Effect.filter(Effect.Columns.timelineId == timelineId)
                .order(Effect.Columns.createdAt.asc)
                .fetchAll(db)
        }
    }

    func getFirstMedia(forProjectId projectId: String) throws -> Media? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT m.*
                FROM media m
                INNER JOIN media_libraries ml ON m.media_library_id = ml.media_library_id
                WHERE ml.project_id = ?
                ORDER BY m.created_at ASC
                LIMIT 1
                """,
                arguments: [projectId]
            ).map(Media.init(row:))
        }
    }

    func getPreferredCoverMedia(forProjectId projectId: String) throws -> Media? {
        try dbQueue.read { db in
            try Row.fetchOne(
                db,
                sql: """
                SELECT m.*
                FROM media m
                INNER JOIN media_libraries ml ON m.media_library_id = ml.media_library_id
                WHERE ml.project_id = ?
                  AND m.kind IN ('photo', 'video')
                ORDER BY m.created_at DESC
                LIMIT 1
                """,
                arguments: [projectId]
            ).map(Media.init(row:))
        }
    }

    func createTrack(_ track: Track) throws {
        try create(track)
    }

    private static func trackDisplayOrder(_ kind: TrackKind) -> Int {
        switch kind {
        case .overlay: return 0
        case .video: return 1
        case .audio: return 2
        }
    }
}
