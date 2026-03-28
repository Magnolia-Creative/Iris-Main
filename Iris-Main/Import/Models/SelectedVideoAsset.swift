import Foundation

struct SelectedVideoAsset: Identifiable, Equatable {
    let id = UUID()
    let localKey: String
    let originalURL: URL
    let displayName: String
    let fileSize: Int64?
    var remoteClipID: String?
}
