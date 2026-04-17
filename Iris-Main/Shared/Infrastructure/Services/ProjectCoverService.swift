import Foundation
import UIKit

final class ProjectCoverService {
    static let shared = ProjectCoverService()

    private let db: DatabaseManager
    private let thumbnailService: ThumbnailService
    private let coverCache = NSCache<NSString, UIImage>()
    private let renderSize = CGSize(width: 640, height: 360)
    private let compressionQuality: CGFloat = 0.82

    init(
        db: DatabaseManager = .shared,
        thumbnailService: ThumbnailService = .shared
    ) {
        self.db = db
        self.thumbnailService = thumbnailService
        coverCache.countLimit = 128
    }

    func loadCover(for project: Project) async -> UIImage? {
        if let cached = cachedCover(for: project.projectId) {
            return cached
        }

        if let stored = storedCover(at: project.coverImagePath, projectId: project.projectId) {
            return stored
        }

        return await ensureCover(forProjectId: project.projectId)
    }

    @discardableResult
    func ensureCover(forProjectId projectId: String, preferredMedia: Media? = nil, overwrite: Bool = false) async -> UIImage? {
        guard let project = try? db.get(Project.self, id: projectId, keyColumn: "project_id") else {
            return nil
        }
        return await ensureCover(for: project, preferredMedia: preferredMedia, overwrite: overwrite)
    }

    @discardableResult
    func ensureCover(forMediaLibraryId mediaLibraryId: String, preferredMedia: Media? = nil, overwrite: Bool = false) async -> UIImage? {
        guard let project = try? db.getProject(forMediaLibraryId: mediaLibraryId) else {
            return nil
        }
        return await ensureCover(for: project, preferredMedia: preferredMedia, overwrite: overwrite)
    }

    @discardableResult
    private func ensureCover(for project: Project, preferredMedia: Media?, overwrite: Bool) async -> UIImage? {
        if !overwrite, let cached = cachedCover(for: project.projectId) {
            return cached
        }

        if !overwrite, let stored = storedCover(at: project.coverImagePath, projectId: project.projectId) {
            return stored
        }

        let resolvedMedia: Media?
        if let preferredMedia, preferredMedia.kind != .audio {
            resolvedMedia = preferredMedia
        } else {
            resolvedMedia = try? db.getPreferredCoverMedia(forProjectId: project.projectId)
        }

        guard let media = resolvedMedia else { return nil }

        guard let image = try? await thumbnailService.loadThumbnail(for: media.assetRefId, size: renderSize) else {
            return nil
        }

        let persistedPath = persist(image: image, forProjectId: project.projectId)
        let cacheKey = cacheKey(for: project.projectId)
        coverCache.setObject(image, forKey: cacheKey)

        if let persistedPath, persistedPath != project.coverImagePath {
            var updatedProject = project
            updatedProject.coverImagePath = persistedPath
            try? db.update(updatedProject)
        }

        return image
    }

    private func persist(image: UIImage, forProjectId projectId: String) -> String? {
        guard let data = image.jpegData(compressionQuality: compressionQuality),
              let url = try? projectCoverURL(for: projectId) else {
            return nil
        }

        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    private func projectCoverURL(for projectId: String) throws -> URL {
        let baseURL = try projectCoverDirectory()
        return baseURL.appendingPathComponent(projectId).appendingPathExtension("jpg")
    }

    private func projectCoverDirectory() throws -> URL {
        let applicationSupportURL = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let coversURL = applicationSupportURL.appendingPathComponent("ProjectCovers", isDirectory: true)
        if !FileManager.default.fileExists(atPath: coversURL.path) {
            try FileManager.default.createDirectory(at: coversURL, withIntermediateDirectories: true)
        }
        return coversURL
    }

    private func storedCover(at path: String?, projectId: String) -> UIImage? {
        guard let path,
              FileManager.default.fileExists(atPath: path),
              let image = UIImage(contentsOfFile: path) else {
            return nil
        }
        coverCache.setObject(image, forKey: cacheKey(for: projectId))
        return image
    }

    private func cachedCover(for projectId: String) -> UIImage? {
        coverCache.object(forKey: cacheKey(for: projectId))
    }

    private func cacheKey(for projectId: String) -> NSString {
        projectId as NSString
    }
}
