import Foundation

struct SelectedVideoAsset: Identifiable, Equatable {
    let localKey: String
    let assetLocalIdentifier: String?
    let originalURL: URL
    let displayName: String
    let fileSize: Int64?
    var remoteClipID: String?

    var id: String { localKey }
}
