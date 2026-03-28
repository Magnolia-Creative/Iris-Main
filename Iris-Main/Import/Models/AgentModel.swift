import Foundation

struct AgentModel {
    var promptText = ""
    var stage: AgentStage = .idle
    var statusMessage = "Reviewing the prompt and planning the first sequence."
    var extractionLanes: [AgentExtractionLane] = []
    var timelineClips: [AgentTimelineClip] = []
    var hasStarted = false
}

enum AgentStage: Equatable {
    case idle
    case reviewingPrompt
    case extractingClips
    case assemblingTimeline
    case refiningSequence
}

struct AgentExtractionLane: Identifiable, Equatable {
    let id = UUID()
    var segments: [AgentExtractionSegment]
    let highlightIndices: Set<Int>
}

struct AgentExtractionSegment: Identifiable, Equatable {
    let id = UUID()
    let widthRatio: Double
    var isHighlighted: Bool
}

struct AgentTimelineClip: Identifiable, Equatable {
    let id = UUID()
    let widthRatio: Double
    let emphasis: Double
}
