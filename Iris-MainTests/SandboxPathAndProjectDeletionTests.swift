import Foundation
import Testing
@testable import Iris_Main

struct SandboxPathAndProjectDeletionTests {
    @Test func canonicalStoredPathUsesDocumentsRelativeForm() throws {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imports = docs.appendingPathComponent("Imports", isDirectory: true)
        try fm.createDirectory(at: imports, withIntermediateDirectories: true)
        let fileURL = imports.appendingPathComponent("sandbox-uri-test.txt")
        try Data("hi".utf8).write(to: fileURL, options: .atomic)

        let canonical = AppSandboxFileURI.canonicalStoredPath(forFileAt: fileURL)
        #expect(canonical.hasPrefix("Documents/"))
        #expect(canonical.contains("sandbox-uri-test.txt"))

        let resolved = AppSandboxFileURI.resolveFileURL(storedURI: canonical)
        #expect(resolved?.standardizedFileURL.path == fileURL.standardizedFileURL.path)
    }

    @Test func resolveFileURLRepairsLegacyAbsolutePath() throws {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let imports = docs.appendingPathComponent("Imports", isDirectory: true)
        try fm.createDirectory(at: imports, withIntermediateDirectories: true)
        let fileURL = imports.appendingPathComponent("legacy-path-test.mov")
        try Data("x".utf8).write(to: fileURL, options: .atomic)

        let canonical = AppSandboxFileURI.canonicalStoredPath(forFileAt: fileURL)
        let fakeLegacyAbsolute =
            "/var/mobile/Containers/Data/Application/00000000-0000-0000-0000-000000000000/" + canonical

        let resolved = AppSandboxFileURI.resolveFileURL(storedURI: fakeLegacyAbsolute)
        #expect(resolved?.standardizedFileURL.path == fileURL.standardizedFileURL.path)
    }

    @Test func deletingProjectCascadesTimelineRow() throws {
        let db = try DatabaseManager.makeInMemory()
        let projectId = "proj-delete-cascade"
        try db.create(Project(projectId: projectId, name: "To Delete"))
        try db.create(MediaLibrary(projectId: projectId))
        _ = try db.createTimeline(forProjectId: projectId)

        #expect(try db.getTimeline(forProjectId: projectId) != nil)

        try db.delete(Project.self, id: projectId, keyColumn: "project_id")

        #expect(try db.get(Project.self, id: projectId, keyColumn: "project_id") == nil)
        #expect(try db.getTimeline(forProjectId: projectId) == nil)
    }
}
