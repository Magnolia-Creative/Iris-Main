import CoreTransferable
import PhotosUI
import SwiftUI

struct VideoIngestView: View {
    @StateObject private var viewModel = VideoIngestViewModel()
    @State private var selectedPickerItems: [PhotosPickerItem] = []

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

    private var responseCard: some View {
        card {
            VStack(alignment: .leading, spacing: .spacing(.sp4)) {
                Text("Server Response")
                    .typography(.heading)
                    .foregroundStyle(Color.ds.text)

                if viewModel.serverResponse.isEmpty {
                    Text("No response received yet.")
                        .typography(.body)
                        .foregroundStyle(Color.ds.textMuted)
                } else {
                    ScrollView(.horizontal, showsIndicators: true) {
                        Text(viewModel.serverResponse)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
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
            var urls: [URL] = []

            for item in items {
                let transferable = try await item.loadTransferable(type: VideoPickerTransferable.self)
                if let transferable {
                    urls.append(transferable.url)
                }
            }

            await MainActor.run {
                viewModel.importSelection(from: urls)
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

private struct VideoPickerTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            Self(url: received.file)
        }
    }
}
