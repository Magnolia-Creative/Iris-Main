import Foundation

struct ImportModel {
    var videos: [SelectedVideoAsset] = []
    var isImportingVideos = false
    var importErrorMessage: String?
    var prompt = PromptMessageState()

    var importedVideoCount: Int {
        videos.count
    }

    var hasImportedVideos: Bool {
        !videos.isEmpty
    }

    var canStartEditing: Bool {
        hasImportedVideos && prompt.isReady
    }
}

struct PromptMessageState: Equatable {
    let hint: String
    let suggestions: [String]
    var text: String
    var validationMessage: String?

    init(
        text: String = "",
        validationMessage: String? = nil,
        hint: String = """
        Turn these clips into a tight 20-second event recap with quick cuts, one hero moment up front, subtle captions, and an energetic finish.
        """,
        suggestions: [String] = [
            "Event recap",
            "Interview clean-up",
            "Travel montage",
            "Product teaser",
        ]
    ) {
        self.text = text
        self.validationMessage = validationMessage
        self.hint = hint
        self.suggestions = suggestions
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isEmpty: Bool {
        trimmedText.isEmpty
    }

    var isReady: Bool {
        !isEmpty && validationMessage == nil
    }

    var status: PromptMessageStatus {
        if let validationMessage {
            return .invalid(validationMessage)
        }

        if isEmpty {
            return .empty(hint: hint)
        }

        return .ready
    }
}

enum PromptMessageStatus: Equatable {
    case empty(hint: String)
    case ready
    case invalid(String)
}

struct ImportedVideo: Equatable {
    let localURL: URL
    let displayName: String
}
