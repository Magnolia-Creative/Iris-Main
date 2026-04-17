import Foundation

struct LocalVideoDescriptor {
    let video: SelectedVideoAsset
    let order: Int
    let localKey: String
    let normalizedStem: String
    let durationSeconds: Double
}

struct LocalVideoMatch {
    let descriptor: LocalVideoDescriptor
    let strategy: LocalVideoMatchStrategy
}

enum LocalVideoMatchStrategy: String {
    case localKey
    case exactIndex
    case oneBasedIndex
    case fileNameStem
    case fallbackPosition
    case firstUnused
}

extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
