import Foundation

enum Stage: String, Codable {
    case validatingInputs = "VALIDATING_INPUTS"
    case preparingMedia = "PREPARING_MEDIA"
    case analyzingAudio = "ANALYZING_AUDIO"
    case analyzingVideo = "ANALYZING_VIDEO"
    case planningEdits = "PLANNING_EDITS"
    case applyingActions = "APPLYING_ACTIONS"
    case renderingPreview = "RENDERING_PREVIEW"
    case renderingExport = "RENDERING_EXPORT"
    case finalizing = "FINALIZING"
    case uploading = "UPLOADING"
}
