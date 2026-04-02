import CoreTransferable
import PhotosUI
import SwiftUI

struct SemanticView: View {
    @StateObject private var viewModel = SemanticSearchViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []

    private let gridColumns = Array(
        repeating: GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: .spacing(.sp2)),
        count: 3
    )

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: .spacing(.sp7)) {
                    heroSection
                    importSection
                    querySection
                    resultsSection
                }
                .padding(.horizontal, .sp4)
                .padding(.vertical, .sp5)
            }
        }
        .navigationTitle("Semantic")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: selectedItems) { _, newValue in
            Task {
                await importSelection(from: newValue)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp2)) {
            Text("Semantic Video Search")
                .typography(.title)
                .foregroundStyle(Color.ds.text)

            Text("Build a coarse index at 1 frame every 2 seconds, then refine at 5 fps around nearest chunks to return the best ranges.")
                .typography(.body)
                .foregroundStyle(Color.ds.textMuted)
        }
    }

    private var importSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Imported clips")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if let importError = viewModel.model.importErrorMessage {
                Text(importError)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            } else if viewModel.model.isImportingVideos {
                ProgressView("Loading videos...")
                    .tint(Color.ds.accentFg)
            } else {
                Text(viewModel.model.statusMessage)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: .spacing(.sp2)) {
                ForEach(viewModel.model.videos) { video in
                    SemanticVideoTile(video: video)
                }

                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 20,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    AddSemanticVideoTile()
                }
            }

            HStack(spacing: .spacing(.sp3)) {
                Button(action: {
                    Task { await viewModel.buildIndex() }
                }) {
                    Label(viewModel.model.isBuildingIndex ? "Indexing..." : "Build index", systemImage: "bolt.horizontal.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.primary)
                .disabled(!viewModel.model.canBuildIndex)
            }
        }
        .padding(.sp4)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Semantic query")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            TextField(
                "e.g. person holding a phone near a whiteboard",
                text: Binding(
                    get: { viewModel.model.queryText },
                    set: { viewModel.updateQuery($0) }
                ),
                axis: .vertical
            )
            .textFieldStyle(.plain)
            .typographyStyle(.body)
            .foregroundStyle(Color.ds.text)
            .padding(.sp3)
            .background(Color.ds.bg)
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp2))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))

            HStack(spacing: .spacing(.sp3)) {
                Button(action: {
                    Task { await viewModel.runSearch() }
                }) {
                    Label(viewModel.model.isSearching ? "Searching..." : "Find ranges", systemImage: "magnifyingglass")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.secondary)
                .disabled(!viewModel.model.canSearch)
            }

            if let searchError = viewModel.model.searchErrorMessage {
                Text(searchError)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.danger)
            }
        }
        .padding(.sp4)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Best ranges")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if viewModel.model.results.isEmpty {
                Text("No ranges yet. Build index, enter query, then run search.")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.sp3)
                    .background(Color.ds.bg)
                    .overlay(
                        RoundedRectangle(cornerRadius: .spacing(.sp2))
                            .stroke(Color.ds.border, lineWidth: 1)
                    )
            } else {
                VStack(spacing: .spacing(.sp2)) {
                    ForEach(viewModel.model.results) { result in
                        SemanticRangeRow(result: result)
                    }
                }
            }
        }
        .padding(.sp4)
        .background(Color.ds.surface)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
    }

    private func importSelection(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            await MainActor.run { viewModel.importSelection(from: []) }
            return
        }

        await MainActor.run {
            viewModel.beginVideoImport()
        }

        do {
            var importedVideos: [ImportedSemanticVideo] = []
            for item in items.prefix(20) {
                let transferable = try await item.loadTransferable(type: SemanticVideoPickerTransferable.self)
                guard let transferable else { continue }

                importedVideos.append(
                    ImportedSemanticVideo(
                        localURL: transferable.localURL,
                        displayName: transferable.originalFilename,
                        localKey: UUID().uuidString
                    )
                )
            }

            await MainActor.run {
                viewModel.importSelection(from: importedVideos)
            }
        } catch {
            await MainActor.run {
                viewModel.importSelection(from: [])
            }
        }
    }
}

private struct SemanticVideoTile: View {
    let video: SemanticImportedVideo

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Image(systemName: "video")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.ds.accentFg)

            Text(video.displayName)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.text)
                .lineLimit(2)

            Text(formatTime(video.durationSeconds))
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
        }
        .padding(.sp3)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 120)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

private struct AddSemanticVideoTile: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.ds.accentFg)

            Text("Add videos")
                .typography(.body)
                .foregroundStyle(Color.ds.accentFg)
        }
        .padding(.sp3)
        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .frame(height: 120)
        .background(Color.ds.surface.opacity(0.45))
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.accentFg, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }
}

private struct SemanticRangeRow: View {
    let result: SemanticMatchRange

    var body: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(result.videoName)
                .typography(.body)
                .foregroundStyle(Color.ds.text)
                .lineLimit(1)

            Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)

            Text("Confidence \(String(format: "%.3f", result.confidence))")
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.accentFg)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.sp3)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(Color.ds.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

private struct SemanticVideoPickerTransferable: Transferable {
    let localURL: URL
    let originalFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .mpeg4Movie) { received in
            try await importReceivedVideo(received)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try await importReceivedVideo(received)
        }
    }

    private static func importReceivedVideo(_ received: ReceivedTransferredFile) async throws -> Self {
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

struct SemanticView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            SemanticView()
                .preferredColorScheme(.dark)
        }
    }
}
