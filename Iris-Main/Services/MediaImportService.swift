import Foundation
import Photos
import UIKit
import AVFoundation

class MediaImportService {
    static let shared = MediaImportService()
    private let db = DatabaseManager.shared

    private init() {}

    // MARK: - Authorization

    func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    func authorizationStatus() -> PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    // MARK: - Fetch Assets

    func fetchPhotos(limit: Int? = nil) -> [PHAsset] {
        fetchAssets(mediaType: .image, limit: limit)
    }

    func fetchVideos(limit: Int? = nil) -> [PHAsset] {
        fetchAssets(mediaType: .video, limit: limit)
    }

    func fetchAllMedia(limit: Int? = nil) -> [PHAsset] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit = limit { options.fetchLimit = limit }
        let results = PHAsset.fetchAssets(with: options)
        return convertFetchResultToArray(results)
    }

    private func fetchAssets(mediaType: PHAssetMediaType, limit: Int?) -> [PHAsset] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", mediaType.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        if let limit = limit { options.fetchLimit = limit }
        let results = PHAsset.fetchAssets(with: options)
        return convertFetchResultToArray(results)
    }

    private func convertFetchResultToArray(_ results: PHFetchResult<PHAsset>) -> [PHAsset] {
        var assets: [PHAsset] = []
        results.enumerateObjects { asset, _, _ in
            assets.append(asset)
        }
        return assets
    }

    // MARK: - Import Media

    func importAsset(_ asset: PHAsset, to mediaLibraryId: String) async throws -> Media {
        let assetRef = try createAssetReference(from: asset)
        var spec = extractMediaSpec(from: asset)
        let kind: MediaKind = switch asset.mediaType {
        case .image: .photo
        case .video: .video
        case .audio: .audio
        default: .photo
        }

        var media = Media(
            mediaLibraryId: mediaLibraryId,
            kind: kind,
            assetRefId: assetRef.assetRefId,
            spec: spec
        )

        if kind == .video {
            if let url = try await ThumbnailService.shared.loadVideoURL(for: assetRef.assetRefId) {
                if let stripInfo = try await ThumbnailService.shared.generateThumbnailStripIfNeeded(
                    for: media, videoURL: url
                ) {
                    spec.thumbnailStripPath = stripInfo.path
                    spec.thumbnailStripHeight = stripInfo.height
                    spec.thumbnailStripFrameCount = stripInfo.frameCount
                    media = Media(
                        mediaId: media.mediaId, mediaLibraryId: media.mediaLibraryId,
                        kind: media.kind, assetRefId: media.assetRefId,
                        spec: spec, createdAt: media.createdAt, updatedAt: Date()
                    )
                }
            }
        }

        try db.create(media)
        return media
    }

    func importAssets(_ assets: [PHAsset], to mediaLibraryId: String) async throws -> [Media] {
        var importedMedia: [Media] = []
        for asset in assets {
            do {
                let media = try await importAsset(asset, to: mediaLibraryId)
                importedMedia.append(media)
            } catch {
                print("Failed to import asset \(asset.localIdentifier): \(error)")
            }
        }
        return importedMedia
    }

    func importFileURLs(_ urls: [URL], to mediaLibraryId: String, preferredKind: MediaKind) async throws -> [Media] {
        var importedMedia: [Media] = []
        for url in urls {
            do {
                let media = try await importFileURL(url, to: mediaLibraryId, preferredKind: preferredKind)
                importedMedia.append(media)
            } catch {
                print("Failed to import file \(url.lastPathComponent): \(error)")
            }
        }
        return importedMedia
    }

    // MARK: - Private Helpers

    private func createAssetReference(from asset: PHAsset) throws -> AssetReference {
        let uri = asset.localIdentifier
        if let existing = try db.assetReferenceExists(uri: uri) {
            return existing
        }
        let assetRef = AssetReference(locationType: .local, uri: uri)
        try db.create(assetRef)
        return assetRef
    }

    private func createAssetReference(from fileURL: URL) throws -> AssetReference {
        let uri = fileURL.path
        if let existing = try db.assetReferenceExists(uri: uri) {
            return existing
        }
        let assetRef = AssetReference(locationType: .local, uri: uri)
        try db.create(assetRef)
        return assetRef
    }

    private func extractMediaSpec(from asset: PHAsset) -> MediaSpec {
        MediaSpec(
            duration: asset.mediaType == .video ? asset.duration : nil,
            width: asset.pixelWidth,
            height: asset.pixelHeight
        )
    }

    private func extractMediaSpec(from fileURL: URL, kind: MediaKind) async throws -> MediaSpec {
        switch kind {
        case .photo:
            if let image = UIImage(contentsOfFile: fileURL.path) {
                return MediaSpec(duration: nil, width: Int(image.size.width), height: Int(image.size.height))
            }
            return MediaSpec()
        case .video:
            let asset = AVURLAsset(url: fileURL)
            let duration = try await asset.load(.duration)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            let size: CGSize
            if let track = tracks.first {
                let naturalSize = try await track.load(.naturalSize)
                let preferredTransform = try await track.load(.preferredTransform)
                size = naturalSize.applying(preferredTransform)
            } else {
                size = .zero
            }
            let durationSeconds = duration.seconds
            return MediaSpec(
                duration: durationSeconds.isFinite ? durationSeconds : nil,
                width: Int(abs(size.width)) > 0 ? Int(abs(size.width)) : nil,
                height: Int(abs(size.height)) > 0 ? Int(abs(size.height)) : nil
            )
        case .audio:
            let asset = AVURLAsset(url: fileURL)
            let duration = try await asset.load(.duration)
            let durationSeconds = duration.seconds
            return MediaSpec(duration: durationSeconds.isFinite ? durationSeconds : nil)
        }
    }

    private func importFileURL(_ url: URL, to mediaLibraryId: String, preferredKind: MediaKind) async throws -> Media {
        let localURL = try copyFileToLibrary(url)
        let assetRef = try createAssetReference(from: localURL)
        let spec = try await extractMediaSpec(from: localURL, kind: preferredKind)

        var finalMedia = Media(
            mediaLibraryId: mediaLibraryId,
            kind: preferredKind,
            assetRefId: assetRef.assetRefId,
            spec: spec
        )

        if preferredKind == .video {
            var updatedSpec = spec
            if let stripInfo = try await ThumbnailService.shared.generateThumbnailStripIfNeeded(
                for: finalMedia, videoURL: localURL
            ) {
                updatedSpec.thumbnailStripPath = stripInfo.path
                updatedSpec.thumbnailStripHeight = stripInfo.height
                updatedSpec.thumbnailStripFrameCount = stripInfo.frameCount
            }
            if updatedSpec.thumbnailStripPath != nil {
                finalMedia = Media(
                    mediaId: finalMedia.mediaId, mediaLibraryId: finalMedia.mediaLibraryId,
                    kind: finalMedia.kind, assetRefId: finalMedia.assetRefId,
                    spec: updatedSpec, createdAt: finalMedia.createdAt, updatedAt: Date()
                )
            }
        }

        try db.create(finalMedia)
        return finalMedia
    }

    private func copyFileToLibrary(_ url: URL) throws -> URL {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let importsURL = documentsURL.appendingPathComponent("Imports", isDirectory: true)
        try fileManager.createDirectory(at: importsURL, withIntermediateDirectories: true)

        let destinationURL = uniqueDestinationURL(for: url.lastPathComponent, in: importsURL)
        if fileManager.fileExists(atPath: destinationURL.path) {
            return destinationURL
        }
        try fileManager.copyItem(at: url, to: destinationURL)
        return destinationURL
    }

    private func uniqueDestinationURL(for fileName: String, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseURL = directory.appendingPathComponent(fileName)
        if !fileManager.fileExists(atPath: baseURL.path) {
            return baseURL
        }
        let fileExtension = baseURL.pathExtension
        let baseName = baseURL.deletingPathExtension().lastPathComponent
        var counter = 1
        while true {
            let candidateURL = directory
                .appendingPathComponent("\(baseName)-\(counter)")
                .appendingPathExtension(fileExtension)
            if !fileManager.fileExists(atPath: candidateURL.path) {
                return candidateURL
            }
            counter += 1
        }
    }
}
