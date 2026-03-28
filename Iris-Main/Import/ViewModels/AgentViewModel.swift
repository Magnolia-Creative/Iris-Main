import Foundation
import SwiftUI
import Combine

@MainActor
final class AgentViewModel: ObservableObject {
    @Published private(set) var model = AgentModel()

    private var sourceVideos: [SelectedVideoAsset] = []

    func configure(promptText: String, videos: [SelectedVideoAsset]) {
        sourceVideos = videos
        model = AgentModel(
            promptText: promptText,
            stage: .idle,
            statusMessage: "Reviewing the prompt and planning the first sequence.",
            extractionLanes: [],
            timelineClips: [],
            hasStarted: false
        )
    }

    func startIfNeeded() async {
        guard !model.hasStarted else { return }

        model.hasStarted = true

        await transition(
            to: .reviewingPrompt,
            statusMessage: "Reading the prompt and deciding how the edit should open."
        )
        await pause(milliseconds: 800)

        await revealExtractionLanes()
        await pause(milliseconds: 300)

        await transition(
            to: .assemblingTimeline,
            statusMessage: "Pulling the strongest moments into a rough sequence."
        )
        await revealTimeline()
        await pause(milliseconds: 420)

        await transition(
            to: .refiningSequence,
            statusMessage: "Balancing pacing, transitions, and the overall rhythm of the cut."
        )
    }

    private func revealExtractionLanes() async {
        let baseLanes = makeExtractionLanes(from: sourceVideos)

        withAnimation(.spring(response: 0.7, dampingFraction: 0.9)) {
            model.stage = .extractingClips
            model.extractionLanes = baseLanes.map { lane in
                AgentExtractionLane(
                    segments: lane.segments.map {
                        AgentExtractionSegment(widthRatio: $0.widthRatio, isHighlighted: false)
                    },
                    highlightIndices: lane.highlightIndices
                )
            }
        }

        for index in model.extractionLanes.indices {
            await pause(milliseconds: 220)

            withAnimation(.spring(response: 0.55, dampingFraction: 0.9)) {
                highlightLane(at: index)
            }
        }
    }

    private func revealTimeline() async {
        let clips = makeTimelineClips(from: sourceVideos)

        for clip in clips {
            await pause(milliseconds: 180)

            withAnimation(.spring(response: 0.52, dampingFraction: 0.88)) {
                model.timelineClips.append(clip)
            }
        }
    }

    private func transition(to stage: AgentStage, statusMessage: String) async {
        withAnimation(.spring(response: 0.65, dampingFraction: 0.9)) {
            model.stage = stage
            model.statusMessage = statusMessage
        }
    }

    private func pause(milliseconds: UInt64) async {
        try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
    }

    private func highlightLane(at index: Int) {
        guard model.extractionLanes.indices.contains(index) else { return }

        for segmentIndex in model.extractionLanes[index].segments.indices {
            model.extractionLanes[index].segments[segmentIndex].isHighlighted =
                model.extractionLanes[index].highlightIndices.contains(segmentIndex)
        }
    }

    private func makeExtractionLanes(from videos: [SelectedVideoAsset]) -> [AgentExtractionLane] {
        let defaultPatterns: [([Double], Set<Int>)] = [
            ([0.16, 0.10, 0.18, 0.12, 0.17, 0.09, 0.18], [0, 2, 4, 6]),
            ([0.14, 0.11, 0.16, 0.15, 0.12, 0.14, 0.18], [1, 3, 5]),
            ([0.18, 0.09, 0.15, 0.10, 0.18, 0.13, 0.17], [0, 3, 4, 6]),
            ([0.12, 0.16, 0.10, 0.17, 0.13, 0.12, 0.20], [1, 2, 4, 6]),
        ]

        let sourceCount = max(videos.count, 3)

        return (0 ..< sourceCount).map { index in
            let pattern = defaultPatterns[index % defaultPatterns.count]
            return AgentExtractionLane(
                segments: pattern.0.map { AgentExtractionSegment(widthRatio: $0, isHighlighted: false) },
                highlightIndices: pattern.1
            )
        }
    }

    private func makeTimelineClips(from videos: [SelectedVideoAsset]) -> [AgentTimelineClip] {
        let basePattern: [(Double, Double)] = [
            (0.24, 0.55),
            (0.34, 0.92),
            (0.18, 0.7),
            (0.12, 0.46),
        ]

        let clipCount = min(max(videos.count + 1, 3), basePattern.count)
        return basePattern.prefix(clipCount).map { AgentTimelineClip(widthRatio: $0.0, emphasis: $0.1) }
    }
}
