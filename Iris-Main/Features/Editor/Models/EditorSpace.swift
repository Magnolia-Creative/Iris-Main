import Foundation

enum EditorSpace: String, CaseIterable, Identifiable {
    case importMedia = "Import"
    case edit = "Edit"
    case chat = "Chat"
    case export = "Export"

    var id: String { rawValue }

    var selectedIconName: String {
        switch self {
        case .importMedia: return "square.and.arrow.down.fill"
        case .edit: return "movieclapper.fill"
        case .chat: return "bubble.left.and.bubble.right.fill"
        case .export: return "square.and.arrow.up.fill"
        }
    }

    var unselectedIconName: String {
        switch self {
        case .importMedia: return "square.and.arrow.down"
        case .edit: return "movieclapper"
        case .chat: return "bubble.left.and.bubble.right"
        case .export: return "square.and.arrow.up"
        }
    }
}
