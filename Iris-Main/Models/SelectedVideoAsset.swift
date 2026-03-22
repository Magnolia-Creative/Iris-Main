import Foundation

struct SelectedVideoAsset: Identifiable, Equatable {
    let id = UUID()
    let originalURL: URL
    let displayName: String
    let fileSize: Int64?
}

