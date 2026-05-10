internal import Combine
import Foundation

@MainActor
final class TimelineCompilerTestViewModel: ObservableObject {
    @Published var prompt = "cut this clip in half"
    @Published var llmBackend: TimelineLLMBackend = .zeticGemma {
        didSet {
            if llmBackend != oldValue {
                outputText = ""
                errorMessage = nil
            }
        }
    }
    @Published private(set) var outputText = ""
    @Published private(set) var isCompiling = false
    @Published private(set) var errorMessage: String?

    private(set) var canConfigureLLMBackend: Bool

    let sampleContextSummary = """
    Selected clip: clip-b
    Track order: clip-a, clip-b, clip-c
    clip-b timeline range: 5s to 15s
    Playhead: 10s
    """

    private let injectedCompiler: TimelinePromptActionCompiler?
    private let context: TimelineCompilerContext
    private let encoder: JSONEncoder

    init(
        compiler: TimelinePromptActionCompiler? = nil,
        context: TimelineCompilerContext? = nil,
        llmBackend: TimelineLLMBackend = .zeticGemma
    ) {
        self.injectedCompiler = compiler
        self.canConfigureLLMBackend = compiler == nil
        self.llmBackend = llmBackend
        self.context = context ?? TimelineCompilerTestViewModel.makeSampleContext()
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    private func compilerForCurrentBackend() -> TimelinePromptActionCompiler {
        if let injectedCompiler {
            return injectedCompiler
        }
        return TimelinePromptActionCompiler(
            embeddingProvider: StubEmbeddingProvider(),
            llmProvider: llmBackend.makeProvider()
        )
    }

    func compilePrompt() async {
        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedPrompt.isEmpty == false else {
            outputText = ""
            errorMessage = "Enter a prompt to compile."
            return
        }

        isCompiling = true
        errorMessage = nil
        defer { isCompiling = false }

        do {
            let result = try await compilerForCurrentBackend().compilePromptToActions(
                prompt: trimmedPrompt,
                context: context
            )
            outputText = try formattedOutput(for: result)
        } catch {
            outputText = ""
            errorMessage = error.localizedDescription
        }
    }
}

private extension TimelineCompilerTestViewModel {
    static func makeSampleContext() -> TimelineCompilerContext {
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

        return TimelineCompilerContext(
            timelineId: "timeline-test",
            selectedClipId: "clip-b",
            selectedTrackId: "track-video",
            selectedRange: nil,
            playheadTimeUs: 10_000_000,
            clipsById: Dictionary(uniqueKeysWithValues: clips.map { ($0.clipId, $0) }),
            orderedClipIdsByTrackId: ["track-video": ["clip-a", "clip-b", "clip-c"]]
        )
    }

    func formattedOutput(for result: TimelineCompileResult) throws -> String {
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
