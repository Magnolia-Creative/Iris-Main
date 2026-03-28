import Foundation

enum AppConfiguration {
    static let ingestEndpoint = URL(string: "http://127.0.0.1:8000/sessions/upload")!
    static let uploadFieldName = "videos"
    static let simulateImportProcessing = true
}
