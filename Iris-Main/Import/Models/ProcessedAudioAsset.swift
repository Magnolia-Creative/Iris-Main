import Foundation

struct ProcessedAudioAsset: Sendable {
    let source: SelectedVideoAsset
    let localKey: String
    let audioURL: URL
    let mimeType: String
    let fileName: String
}
