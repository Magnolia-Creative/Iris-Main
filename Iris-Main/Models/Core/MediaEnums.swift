import Foundation

enum MediaKind: String, Codable {
    case photo
    case video
    case audio
}

enum ProxyStatus: String, Codable {
    case none
    case pending
    case processing
    case ready
    case failed
}

enum ProxyPolicy: String, Codable {
    case none
    case auto
    case always
}

enum CleanupPolicy: String, Codable {
    case never
    case onProjectDelete = "on_project_delete"
    case onRemove = "on_remove"
}
