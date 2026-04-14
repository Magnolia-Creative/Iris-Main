import Foundation

struct SelectedVideoAsset: Identifiable, Equatable, Sendable {
    let localKey: String
    let assetLocalIdentifier: String?
    let localMediaID: String?
    let originalURL: URL
    let displayName: String
    let fileSize: Int64?
    var remoteClipID: String?

    var id: String { localKey }
}
