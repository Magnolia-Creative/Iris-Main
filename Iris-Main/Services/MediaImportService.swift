import Foundation
import Photos
import UIKit
import AVFoundation
import GRDB

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

    func fetchVideoAlbums() -> [PHAssetCollection] {
        var collections: [PHAssetCollection] = []
        let seenIdentifiers = NSMutableSet()

        func appendCollections(_ fetchResult: PHFetchResult<PHAssetCollection>) {
            fetchResult.enumerateObjects { collection, _, _ in
                guard !seenIdentifiers.contains(collection.localIdentifier) else { return }
                let assets = PHAsset.fetchAssets(in: collection, options: self.videoFetchOptions())
                guard assets.count > 0 else { return }
                seenIdentifiers.add(collection.localIdentifier)
                collections.append(collection)
            }
        }

        appendCollections(PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .any, options: nil))
        appendCollections(PHAssetCollection.fetchAssetCollections(with: .album, subtype: .any, options: nil))

        return collections.sorted {
            let lhsTitle = $0.localizedTitle ?? ""
            let rhsTitle = $1.localizedTitle ?? ""
            return lhsTitle.localizedCaseInsensitiveCompare(rhsTitle) == .orderedAscending
        }
    }

    func fetchVideos(in collectionLocalIdentifier: String?) -> [PHAsset] {
        let options = videoFetchOptions()
        if let collectionLocalIdentifier,
           let collection = PHAssetCollection.fetchAssetCollections(
               withLocalIdentifiers: [collectionLocalIdentifier],
               options: nil
           ).firstObject {
            return convertFetchResultToArray(PHAsset.fetchAssets(in: collection, options: options))
        }

        return convertFetchResultToArray(PHAsset.fetchAssets(with: .video, options: options))
    }

    func requestThumbnail(for asset: PHAsset, targetSize: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.resizeMode = .fast
            options.isSynchronous = false
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    func exportVideoAssetToTemporaryURL(_ asset: PHAsset) async throws -> URL {
        let sourceURL = try await requestVideoURL(for: asset)
        let fileManager = FileManager.default
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL
    }

    func fileSize(for url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        if let fileSize = values?.fileSize {
            return Int64(fileSize)
        }
        return nil
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

    private func videoFetchOptions() -> PHFetchOptions {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        return options
    }

    private func requestVideoURL(for asset: PHAsset) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let options = PHVideoRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true

            PHImageManager.default().requestAVAsset(forVideo: asset, options: options) { avAsset, _, info in
                if let info,
                   let error = info[PHImageErrorKey] as? Error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let urlAsset = avAsset as? AVURLAsset else {
                    continuation.resume(throwing: NSError(
                        domain: "MediaImportService",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "The selected video could not be loaded."]
                    ))
                    return
                }

                continuation.resume(returning: urlAsset.url)
            }
        }
    }

    // MARK: - Import Media

    func importAsset(_ asset: PHAsset, to mediaLibraryId: String) async throws -> Media {
        let assetRef = try createAssetReference(from: asset)
        let spec = extractMediaSpec(from: asset)
        let kind: MediaKind = switch asset.mediaType {
        case .image: .photo
        case .video: .video
        case .audio: .audio
        default: .photo
        }

        let media = Media(
            mediaLibraryId: mediaLibraryId,
            kind: kind,
            assetRefId: assetRef.assetRefId,
            spec: spec
        )

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

    func importFileURLsQuick(_ urls: [URL], to mediaLibraryId: String, preferredKind: MediaKind) async throws -> [Media] {
        var importedMedia: [Media] = []
        for url in urls {
            do {
                let media = try await importFileURLQuick(url, to: mediaLibraryId, preferredKind: preferredKind)
                importedMedia.append(media)
            } catch {
                print("Failed to import file \(url.lastPathComponent): \(error)")
            }
        }
        return importedMedia
    }

    func generateThumbnailStrip(for media: Media) async -> Media {
        guard media.kind == .video else { return media }
        do {
            guard let url = try await ThumbnailService.shared.loadVideoURL(for: media.assetRefId) else { return media }
            guard let stripInfo = try await ThumbnailService.shared.generateThumbnailStripIfNeeded(
                for: media, videoURL: url
            ) else { return media }
            var updated = media
            updated.spec.thumbnailStripPath = stripInfo.path
            updated.spec.thumbnailStripHeight = stripInfo.height
            updated.spec.thumbnailStripFrameCount = stripInfo.frameCount
            updated.updatedAt = Date()
            try db.update(updated)
            return updated
        } catch {
            return media
        }
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

    private func importFileURLQuick(_ url: URL, to mediaLibraryId: String, preferredKind: MediaKind) async throws -> Media {
        let localURL = try copyFileToLibrary(url)
        let assetRef = try createAssetReference(from: localURL)
        if let existingMedia = try existingMedia(in: mediaLibraryId, assetRefId: assetRef.assetRefId) {
            return existingMedia
        }
        let spec = try await extractMediaSpec(from: localURL, kind: preferredKind)
        let media = Media(
            mediaLibraryId: mediaLibraryId,
            kind: preferredKind,
            assetRefId: assetRef.assetRefId,
            spec: spec
        )
        try db.create(media)
        return media
    }

    private func importFileURL(_ url: URL, to mediaLibraryId: String, preferredKind: MediaKind) async throws -> Media {
        let localURL = try copyFileToLibrary(url)
        let assetRef = try createAssetReference(from: localURL)
        if let existingMedia = try existingMedia(in: mediaLibraryId, assetRefId: assetRef.assetRefId) {
            return existingMedia
        }
        let spec = try await extractMediaSpec(from: localURL, kind: preferredKind)
        let finalMedia = Media(
            mediaLibraryId: mediaLibraryId,
            kind: preferredKind,
            assetRefId: assetRef.assetRefId,
            spec: spec
        )

        try db.create(finalMedia)
        return finalMedia
    }

    private func existingMedia(in mediaLibraryId: String, assetRefId: String) throws -> Media? {
        try db.dbQueue.read { db in
            try Media
                .filter(Media.Columns.mediaLibraryId == mediaLibraryId)
                .filter(Media.Columns.assetRefId == assetRefId)
                .fetchOne(db)
        }
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
