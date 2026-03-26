import Combine
import Foundation

@MainActor
final class ImportViewModel: ObservableObject {
    @Published private(set) var model = ImportModel()

    func beginVideoImport() {
        model.isImportingVideos = true
        model.importErrorMessage = nil
    }

    func importSelection(from importedVideos: [ImportedVideo]) {
        guard !importedVideos.isEmpty else {
            model.videos = []
            model.isImportingVideos = false
            model.importErrorMessage = nil
            return
        }

        do {
            model.videos = try importedVideos.map(makeSelectedVideo(from:))
            model.importErrorMessage = nil
        } catch {
            model.videos = []
            model.importErrorMessage = error.localizedDescription
        }

        model.isImportingVideos = false
    }

    func completeVideoImport(with error: Error) {
        model.videos = []
        model.isImportingVideos = false
        model.importErrorMessage = error.localizedDescription
    }

    func removeVideo(id: SelectedVideoAsset.ID) {
        model.videos.removeAll { $0.id == id }
    }

    func updatePromptMessage(_ text: String) {
        model.prompt.text = text
        model.prompt.validationMessage = validatePromptMessage(text)
    }

    func applyPromptSuggestion(_ suggestion: String) {
        updatePromptMessage(suggestion)
    }

    func clearPromptMessage() {
        updatePromptMessage("")
    }

    private func makeSelectedVideo(from importedVideo: ImportedVideo) throws -> SelectedVideoAsset {
        let fileValues = try importedVideo.localURL.resourceValues(forKeys: [.fileSizeKey])
        let size = Int64(fileValues.fileSize ?? 0)

        return SelectedVideoAsset(
            originalURL: importedVideo.localURL,
            displayName: importedVideo.displayName,
            fileSize: size > 0 ? size : nil
        )
    }

    private func validatePromptMessage(_ text: String) -> String? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmedText.isEmpty else {
            return nil
        }

        if trimmedText.count < 8 {
            return "Add a little more detail so Iris knows how to shape the edit."
        }

        return nil
    }
}
