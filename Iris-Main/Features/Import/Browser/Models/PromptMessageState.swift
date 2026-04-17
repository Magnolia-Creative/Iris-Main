import Foundation

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
