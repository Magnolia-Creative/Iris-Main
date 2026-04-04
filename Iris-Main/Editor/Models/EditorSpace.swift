import Foundation

enum EditorSpace: String, CaseIterable, Identifiable {
    case importMedia = "Import"
    case edit = "Edit"
    case chat = "Chat"
    case export = "Export"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .importMedia: return "square.and.arrow.down"
        case .edit: return "scissors"
        case .chat: return "bubble.left.and.bubble.right"
        case .export: return "square.and.arrow.up"
        }
    }
}
