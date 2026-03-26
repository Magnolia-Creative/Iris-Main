import CoreTransferable
import PhotosUI
import SwiftUI

struct VideoIngestView: View {
    @StateObject private var viewModel = VideoIngestViewModel()
    @State private var selectedPickerItems: [PhotosPickerItem] = []
    @State private var showTranscript = true
    @State private var showWordDetails = false

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color.ds.bg,
                    Color.ds.surface.opacity(0.9),
                    Color.ds.accentBg.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: .spacing(.sp6)) {
                    introCard
                    selectionCard
                    transcriptOverviewCard
                    queuedFilesCard
                    responseCard
                }
                .padding(.horizontal, .sp6)
                .padding(.vertical, .sp7)
            }
        }
        .navigationTitle("Video Ingest")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedPickerItems) { _, newValue in
            Task {
                await importSelection(from: newValue)
            }
        }
    }

    private var introCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                Text("Camera Roll to Speech Audio")
                    .typography(.title)
                    .foregroundStyle(Color.ds.text)

                Text("Pick one or more videos, strip out the audio locally, compress it to 48 kbps AAC mono for faster transfer, then upload each result to the ingest endpoint using the `videos` multipart field.")
                    .typography(.body)
                    .foregroundStyle(Color.ds.textMuted)

                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Endpoint")
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.textMuted)

                    Text(viewModel.endpoint.absoluteString)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var selectionCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                HStack {
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text("Select Videos")
                            .typography(.heading)
                            .foregroundStyle(Color.ds.text)

                        Text(viewModel.statusMessage)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                    }

                    Spacer()
                }

                HStack(spacing: .spacing(.sp3)) {
                    PhotosPicker(
                        selection: $selectedPickerItems,
                        maxSelectionCount: 10,
                        matching: .videos,
                        photoLibrary: .shared()
                    ) {
                        Label("Choose from Camera Roll", systemImage: "film.stack")
                    }
                    .buttonStyle(.primary)
                    .disabled(viewModel.isLoadingSelection || viewModel.isUploading)

                    Button(action: {
                        Task {
                            await viewModel.uploadSelection()
                        }
                    }) {
                        if viewModel.isUploading {
                            Label("Uploading...", systemImage: "arrow.up.circle")
                        } else {
                            Label("Process and Upload", systemImage: "arrow.up.doc")
                        }
                    }
                    .buttonStyle(.secondary)
                    .disabled(viewModel.selectedVideos.isEmpty || viewModel.isLoadingSelection || viewModel.isUploading)
                }

                if viewModel.isLoadingSelection || viewModel.isUploading {
                    ProgressView()
                        .tint(Color.ds.accentFg)
                }
            }
        }
    }

    private var queuedFilesCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                Text("Queued Files")
                    .typography(.heading)
                    .foregroundStyle(Color.ds.text)

                if viewModel.selectedVideos.isEmpty {
                    Text("No videos selected.")
                        .typography(.body)
                        .foregroundStyle(Color.ds.textMuted)
                } else {
                    ForEach(viewModel.selectedVideos) { video in
                        HStack(alignment: .center, spacing: .spacing(.sp3)) {
                            RoundedRectangle(cornerRadius: .spacing(.sp2))
                                .fill(Color.ds.accentBg.opacity(0.12))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Image(systemName: "video")
                                        .foregroundStyle(Color.ds.accentFg)
                                }

                            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                                Text(video.displayName)
                                    .typography(.body)
                                    .foregroundStyle(Color.ds.text)
                                    .lineLimit(1)

                                Text(detailText(for: video))
                                    .typography(.bodySmall)
                                    .foregroundStyle(Color.ds.textMuted)
                            }

                            Spacer()

                            Button("Remove") {
                                viewModel.removeVideo(id: video.id)
                            }
                            .buttonStyle(.tertiary)
                            .disabled(viewModel.isUploading)
                        }
                        .padding(.sp4)
                        .background(Color.ds.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                .stroke(Color.ds.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                    }
                }
            }
        }
    }

    private var transcriptOverviewCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                HStack {
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text("Transcript")
                            .typography(.heading)
                            .foregroundStyle(Color.ds.text)

                        if let response = viewModel.parsedResponse {
                            Text(summaryText(for: response))
                                .typography(.bodySmall)
                                .foregroundStyle(Color.ds.textMuted)
                        } else {
                            Text("Upload a file to see the parsed transcript.")
                                .typography(.bodySmall)
                                .foregroundStyle(Color.ds.textMuted)
                        }
                    }

                    Spacer()
                }

                if viewModel.parsedResponse != nil {
                    Toggle("Show high-level transcription", isOn: $showTranscript)
                        .tint(Color.ds.accentFg)
                    Toggle("Show per-word transcription", isOn: $showWordDetails)
                        .tint(Color.ds.accentFg)
                }

                if let response = viewModel.parsedResponse {
                    if let duration = viewModel.processingDuration {
                        metricRow(title: "Total time", value: String(format: "%.2f seconds", duration))
                    }

                    if let extraction = viewModel.audioExtractionDuration {
                        metricRow(title: "Audio extraction", value: String(format: "%.2f seconds", extraction))
                    }

                    if let server = viewModel.serverProcessingDuration {
                        metricRow(title: "Server processing", value: String(format: "%.2f seconds", server))
                    }

                    metricRow(title: "Project", value: response.projectName)
                    metricRow(title: "Uploaded files", value: "\(response.uploadedCount)")

                    ForEach(response.videos) { video in
                        VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                            Text(video.fileName)
                                .typography(.body)
                                .foregroundStyle(Color.ds.text)

                            if let report = video.videoReport {
                                videoReportSection(report, for: video)
                            }

                            if showTranscript {
                                VStack(alignment: .leading, spacing: .spacing(.sp3)) {
                                    ForEach(video.transcriptSegments) { segment in
                                        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                                            Text(timeRangeText(start: segment.start, end: segment.end))
                                                .typography(.bodySmall)
                                                .foregroundStyle(Color.ds.accentFg)

                                            Text(segment.cleanedText)
                                                .typography(.body)
                                                .foregroundStyle(Color.ds.text)

                                            if showWordDetails, !segment.words.isEmpty {
                                                wordFlow(for: segment.words)
                                            }
                                        }
                                        .padding(.sp4)
                                        .background(Color.ds.bg)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                                .stroke(Color.ds.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private var responseCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                DisclosureGroup("Raw Server Response") {
                    if viewModel.serverResponse.isEmpty {
                        Text("No response received yet.")
                            .typography(.body)
                            .foregroundStyle(Color.ds.textMuted)
                            .padding(.top, .sp3)
                    } else {
                        ScrollView(.horizontal, showsIndicators: true) {
                            Text(viewModel.serverResponse)
                                .typography(.bodySmall)
                                .foregroundStyle(Color.ds.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.top, .sp3)
                        .padding(.sp4)
                        .background(Color.ds.bg)
                        .overlay(
                            RoundedRectangle(cornerRadius: .spacing(.sp3))
                                .stroke(Color.ds.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                    }
                }
                .typographyStyle(.body)
                .foregroundStyle(Color.ds.text)
            }
        }
    }

    private func detailText(for video: SelectedVideoAsset) -> String {
        let originalSize = video.fileSize.map(Self.byteFormatter.string(fromByteCount:)) ?? "Unknown size"
        return "Original video: \(originalSize). Upload target: compressed AAC speech audio."
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.sp6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.ds.surface)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp4))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
    }

    @ViewBuilder
    private func videoReportSection(_ report: VideoReport, for video: IngestVideoResponse) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Video Report")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            if let clipType = report.candidateClipType {
                metricRow(
                    title: "Clip type",
                    value: clipTypeLabel(clipType, confidence: report.clipTypeConfidence)
                )
            }

            if let stats = report.transcriptStats {
                metricRow(title: "Duration", value: String(format: "%.2f seconds", stats.durationSec))
                metricRow(title: "Words", value: "\(stats.wordCount)")
                metricRow(title: "Segments", value: "\(stats.segmentCount)")
                metricRow(title: "Speakers", value: "\(stats.speakerCount)")
                metricRow(title: "Pace", value: String(format: "%.2f wpm", stats.wordsPerMinute))
            } else if let duration = video.clipMeta?.durationSeconds {
                metricRow(title: "Duration", value: String(format: "%.2f seconds", duration))
            }

            if !report.keywords.isEmpty {
                tokenSection(title: "Keywords", values: report.keywords)
            }

            if !report.namedEntities.isEmpty {
                tokenSection(
                    title: "Named entities",
                    values: report.namedEntities.map { "\($0.text) (\($0.label), \($0.count))" }
                )
            }

            if !report.representativeSegments.isEmpty {
                transcriptExcerptSection(
                    title: "Representative segments",
                    segments: report.representativeSegments.map {
                        TranscriptExcerpt(
                            id: $0.id,
                            start: $0.start,
                            end: $0.end,
                            text: $0.text,
                            score: nil
                        )
                    }
                )
            }

            if !report.salientSpans.isEmpty {
                transcriptExcerptSection(
                    title: "Salient spans",
                    segments: report.salientSpans.map {
                        TranscriptExcerpt(
                            id: $0.id,
                            start: $0.start,
                            end: $0.end,
                            text: $0.text,
                            score: $0.score
                        )
                    }
                )
            }

            if !report.ambiguityIndicators.isEmpty {
                tokenSection(title: "Ambiguity indicators", values: report.ambiguityIndicators)
            }
        }
        .padding(.sp4)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func metricRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Spacer()

            Text(value)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
        }
    }

    private func tokenSection(title: String, values: [String]) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: .spacing(.sp2))], alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(values, id: \.self) { value in
                    Text(value)
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.text)
                        .padding(.horizontal, .sp3)
                        .padding(.vertical, .sp2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.ds.surface)
                        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
                }
            }
        }
    }

    private func transcriptExcerptSection(title: String, segments: [TranscriptExcerpt]) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text(title)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            ForEach(segments) { segment in
                VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                    HStack {
                        Text(timeRangeText(start: segment.start, end: segment.end))
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.accentFg)

                        Spacer()

                        if let score = segment.score {
                            Text(String(format: "%.2f", score))
                                .typography(.bodySmall)
                                .foregroundStyle(Color.ds.textMuted)
                        }
                    }

                    Text(segment.text.trimmingCharacters(in: .whitespacesAndNewlines))
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)
                }
                .padding(.sp3)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
        }
    }

    private func wordFlow(for words: [TranscriptWord]) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Per-word timing")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: .spacing(.sp2))], alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(words) { word in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(word.word)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.text)

                        Text(wordMetadata(for: word))
                            .font(.system(size: 10, weight: .regular))
                            .foregroundStyle(Color.ds.textMuted)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, .sp2)
                    .padding(.vertical, .sp1)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
                }
            }
        }
    }

    private func wordMetadata(for word: TranscriptWord) -> String {
        let start = word.start.map(formatTimestamp) ?? "--"
        let end = word.end.map(formatTimestamp) ?? "--"
        let score = word.score.map { String(format: "%.2f", $0) } ?? "--"
        return "\(start)-\(end) • \(score)"
    }

    private func summaryText(for response: IngestResponse) -> String {
        let stats = response.videos.compactMap(\.videoReport?.transcriptStats)
        let segmentCount = stats.isEmpty
            ? response.videos.flatMap(\.transcriptSegments).count
            : stats.reduce(0) { $0 + $1.segmentCount }
        let wordCount = stats.isEmpty
            ? response.videos
                .flatMap(\.transcriptSegments)
                .reduce(0) { $0 + $1.words.count }
            : stats.reduce(0) { $0 + $1.wordCount }
        return "\(segmentCount) transcript segments and \(wordCount) words parsed from \(response.uploadedCount) uploaded audio file\(response.uploadedCount == 1 ? "" : "s")."
    }

    private func clipTypeLabel(_ clipType: String, confidence: Double?) -> String {
        let title = clipType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
        guard let confidence else { return title }
        return "\(title) (\(String(format: "%.0f", confidence * 100))%)"
    }

    private func timeRangeText(start: Double, end: Double) -> String {
        "\(formatTimestamp(start)) - \(formatTimestamp(end))"
    }

    private func formatTimestamp(_ time: Double) -> String {
        let minutes = Int(time) / 60
        let seconds = time.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%05.2f", minutes, seconds)
    }

    private func importSelection(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            await MainActor.run {
                viewModel.importSelection(from: [])
            }
            return
        }

        await MainActor.run {
            viewModel.beginSelectionImport()
        }

        do {
            var importedVideos: [ImportedVideo] = []

            for item in items {
                let transferable = try await item.loadTransferable(type: VideoPickerTransferable.self)
                if let transferable {
                    importedVideos.append(
                        ImportedVideo(
                            localURL: transferable.localURL,
                            displayName: transferable.originalFilename
                        )
                    )
                }
            }

            await MainActor.run {
                viewModel.importSelection(from: importedVideos)
            }
        } catch {
            await MainActor.run {
                viewModel.completeSelectionImport(with: error)
            }
        }
    }

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
}

private struct TranscriptExcerpt: Identifiable {
    let id: String
    let start: Double
    let end: Double
    let text: String
    let score: Double?
}

private struct VideoPickerTransferable: Transferable {
    let localURL: URL
    let originalFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .mpeg4Movie, importing: importReceivedVideo)
        FileRepresentation(importedContentType: .movie, importing: importReceivedVideo)
    }

    private static func importReceivedVideo(_ received: ReceivedTransferredFile) throws -> Self {
        let fileManager = FileManager.default
        let sourceURL = received.file
        let fileExtension = sourceURL.pathExtension.isEmpty ? "mov" : sourceURL.pathExtension
        let destinationURL = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)

        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }

        try fileManager.copyItem(at: sourceURL, to: destinationURL)

        return Self(
            localURL: destinationURL,
            originalFilename: sourceURL.lastPathComponent
        )
    }
}
