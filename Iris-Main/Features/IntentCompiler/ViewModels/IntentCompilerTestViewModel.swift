internal import Combine
import Foundation

@MainActor
final class IntentCompilerTestViewModel: ObservableObject {
    @Published var prompt = "cut this clip in half"
    @Published private(set) var outputText = ""
    @Published private(set) var isCompiling = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var statusMessage = "Backend intent compiler ready."

    let sampleContextSummary = """
    Selected clip: clip-b
    Track order: clip-a, clip-b, clip-c
    clip-b timeline range: 5s to 15s
    Playhead: 10s
    """

    private let injectedCompiler: IntentPromptActionCompiler?
    private let remoteCompiler: RemoteIntentCompilerClient
    private let context: IntentCompilerContext
    private let encoder: JSONEncoder

    init(
        compiler: IntentPromptActionCompiler? = nil,
        remoteCompiler: RemoteIntentCompilerClient = RemoteIntentCompilerClient(),
        context: IntentCompilerContext? = nil
    ) {
        self.injectedCompiler = compiler
        self.remoteCompiler = remoteCompiler
        self.context = context ?? IntentCompilerTestViewModel.makeSampleContext()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func compilePrompt() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            outputText = ""
            errorMessage = "Enter a prompt to compile."
            statusMessage = "Waiting for a prompt."
            return
        }

        isCompiling = true
        errorMessage = nil
        statusMessage = "Starting backend intent run."
        defer { isCompiling = false }

        do {
            let result: IntentCompileResult
            if let injectedCompiler {
                result = try await injectedCompiler.compilePromptToActions(
                    prompt: trimmedPrompt,
                    context: context
                )
            } else {
                result = try await remoteCompiler.compilePrompt(
                    prompt: trimmedPrompt,
                    context: context
                ) { [weak self] status in
                    self?.statusMessage = status
                }
            }
            outputText = try formattedOutput(for: result)
            statusMessage = "Compilation complete."
        } catch {
            outputText = ""
            errorMessage = error.localizedDescription
            statusMessage = "Compilation failed."
        }
    }
}

private extension IntentCompilerTestViewModel {
    static func makeSampleContext() -> IntentCompilerContext {
        let clips = [
            Clip(
                clipId: "clip-a",
                trackId: "track-video",
                mediaId: "media-a",
                sourceRange: TimeRange(start: 0, end: 5_000_000),
                timelineRange: TimeRange(start: 0, end: 5_000_000)
            ),
            Clip(
                clipId: "clip-b",
                trackId: "track-video",
                mediaId: "media-b",
                sourceRange: TimeRange(start: 0, end: 10_000_000),
                timelineRange: TimeRange(start: 5_000_000, end: 15_000_000)
            ),
            Clip(
                clipId: "clip-c",
                trackId: "track-video",
                mediaId: "media-c",
                sourceRange: TimeRange(start: 0, end: 5_000_000),
                timelineRange: TimeRange(start: 15_000_000, end: 20_000_000)
            )
        ]

        var state = TimelineState(timelineId: "timeline-test")
        state.tracks = [
            Track(trackId: "track-video", timelineId: "timeline-test", kind: .video)
        ]
        state.clips = clips
        state.selectedClipId = "clip-b"
        state.currentTimeAtCenter = 10_000_000
        return state.makeIntentCompilerContext()
    }

    func formattedOutput(for result: IntentCompileResult) throws -> String {
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
