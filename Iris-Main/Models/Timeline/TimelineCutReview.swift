import Foundation

struct TimelineCutReviewSession: Equatable {
    var items: [TimelineCutReviewItem]
    var currentIndex: Int = 0
    var isRepromptComposerPresented = false
    var repromptDraft = ""

    var currentItem: TimelineCutReviewItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    var focusedClipIds: Set<String> {
        guard let currentItem else { return [] }
        return [currentItem.leftClipId, currentItem.rightClipId]
    }

    var progressLabel: String {
        guard !items.isEmpty else { return "No cuts to review" }
        return "Cut \(currentIndex + 1) of \(items.count)"
    }
}

struct TimelineCutReviewItem: Identifiable, Equatable {
    let leftClipId: String
    let rightClipId: String
    let leftMediaId: String
    let rightMediaId: String
    let startTimeUs: Int64
    let cutTimeUs: Int64
    let endTimeUs: Int64

    var id: String {
        "\(leftClipId)-\(rightClipId)"
    }

    var canCancel: Bool {
        leftMediaId == rightMediaId
    }
}
