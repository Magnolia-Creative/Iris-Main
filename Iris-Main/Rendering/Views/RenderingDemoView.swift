import CoreTransferable
import PhotosUI
import SwiftUI

struct RenderingDemoView: View {
    @StateObject private var viewModel = RenderingDemoViewModel()
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var overlayTrackItems: [PhotosPickerItem] = []
    @State private var captionText: String = ""

    var body: some View {
        ZStack {
            Color.ds.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: .spacing(.sp5)) {
                    previewSection
                    transportSection
                    clipsSection
                    if viewModel.selectedClip != nil {
                        transformSection
                        colorSection
                        opacitySection
                    }
                    captionSection
                    if viewModel.showMetrics {
                        metricsSection
                    }
                }
                .padding(.horizontal, .sp4)
                .padding(.vertical, .sp5)
            }
        }
        .navigationTitle("Rendering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.showMetrics.toggle()
                } label: {
                    Image(systemName: viewModel.showMetrics ? "chart.bar.fill" : "chart.bar")
                }
                .tint(Color.ds.accentFg)
            }
        }
        .onChange(of: selectedItems) { _, newValue in
            Task { await importClips(from: newValue, overlay: false) }
        }
        .onChange(of: overlayTrackItems) { _, newValue in
            Task { await importClips(from: newValue, overlay: true) }
        }
    }

    // MARK: - Preview

    private var previewSection: some View {
        MetalPreviewView(engine: viewModel.engine)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
            .overlay(
                RoundedRectangle(cornerRadius: .spacing(.sp3))
                    .stroke(Color.ds.border, lineWidth: 1)
            )
    }

    // MARK: - Transport

    private var transportSection: some View {
        VStack(spacing: .spacing(.sp2)) {
            Slider(
                value: Binding(
                    get: { viewModel.currentTime },
                    set: { viewModel.seek(to: $0) }
                ),
                in: 0 ... max(viewModel.duration, 0.01)
            )
            .tint(Color.ds.accentFg)

            HStack {
                Button(action: { viewModel.seek(to: 0) }) {
                    Image(systemName: "backward.end.fill")
                }
                .tint(Color.ds.accentFg)

                Button(action: { viewModel.togglePlayback() }) {
                    Image(systemName: viewModel.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20))
                }
                .tint(Color.ds.accentFg)

                Spacer()

                Text(formatTime(viewModel.currentTime))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .monospacedDigit()

                Text("/")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.border)

                Text(formatTime(viewModel.duration))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .monospacedDigit()
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

    // MARK: - Clips

    private var clipsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Tracks")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            if viewModel.tracks.isEmpty {
                Text("Add video clips to begin rendering.")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            ForEach(viewModel.tracks) { track in
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Track \(track.zOrder + 1)")
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.textMuted)

                    ForEach(track.clips) { clip in
                        clipRow(clip)
                    }
                }
            }

            HStack(spacing: .spacing(.sp3)) {
                PhotosPicker(
                    selection: $selectedItems,
                    maxSelectionCount: 5,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Add clip", systemImage: "plus")
                }
                .buttonStyle(.primary)

                PhotosPicker(
                    selection: $overlayTrackItems,
                    maxSelectionCount: 1,
                    matching: .videos,
                    photoLibrary: .shared()
                ) {
                    Label("Overlay track", systemImage: "square.stack.3d.up")
                }
                .buttonStyle(.secondary)
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

    private func clipRow(_ clip: RenderingDemoViewModel.DemoClip) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                Text(clip.displayName)
                    .typography(.body)
                    .foregroundStyle(Color.ds.text)
                    .lineLimit(1)

                Text("\(formatTime(clip.timelineStart)) - \(formatTime(clip.timelineStart + clip.timelineDuration))")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
            }

            Spacer()

            if viewModel.selectedClipID == clip.id {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.ds.accentFg)
            }

            Button {
                viewModel.removeClip(id: clip.id)
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(Color.ds.danger)
            }
        }
        .padding(.sp3)
        .background(viewModel.selectedClipID == clip.id ? Color.ds.accentBg.opacity(0.12) : Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp2))
                .stroke(
                    viewModel.selectedClipID == clip.id ? Color.ds.accentFg : Color.ds.border,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
        .onTapGesture {
            viewModel.selectedClipID = viewModel.selectedClipID == clip.id ? nil : clip.id
        }
    }

    // MARK: - Transform

    private var transformSection: some View {
        let clip = viewModel.selectedClip!
        let transform = clip.transform

        return VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            HStack {
                Text("Transform")
                    .typography(.heading)
                    .foregroundStyle(Color.ds.text)
                Spacer()
                Button("Reset") {
                    viewModel.updateTransform(.identity)
                }
                .buttonStyle(.tertiary)
            }

            labeledSlider("Position X", value: transform.position.x, range: -1 ... 1) { v in
                var t = transform; t.position.x = v; viewModel.updateTransform(t)
            }
            labeledSlider("Position Y", value: transform.position.y, range: -1 ... 1) { v in
                var t = transform; t.position.y = v; viewModel.updateTransform(t)
            }
            labeledSlider("Scale X", value: transform.scale.x, range: 0.1 ... 3) { v in
                var t = transform; t.scale.x = v; viewModel.updateTransform(t)
            }
            labeledSlider("Scale Y", value: transform.scale.y, range: 0.1 ... 3) { v in
                var t = transform; t.scale.y = v; viewModel.updateTransform(t)
            }
            labeledSlider("Rotation", value: transform.rotation, range: -.pi ... .pi) { v in
                var t = transform; t.rotation = v; viewModel.updateTransform(t)
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

    // MARK: - Color Adjustments

    private var colorSection: some View {
        let clip = viewModel.selectedClip!
        let adj = clip.colorAdjustments

        return VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            HStack {
                Text("Color")
                    .typography(.heading)
                    .foregroundStyle(Color.ds.text)
                Spacer()
                Button("Reset") {
                    viewModel.updateColorAdjustments(.neutral)
                }
                .buttonStyle(.tertiary)
            }

            labeledSlider("Exposure", value: adj.exposure, range: -2 ... 2) { v in
                var a = adj; a.exposure = v; viewModel.updateColorAdjustments(a)
            }
            labeledSlider("Contrast", value: adj.contrast, range: -1 ... 1) { v in
                var a = adj; a.contrast = v; viewModel.updateColorAdjustments(a)
            }
            labeledSlider("Saturation", value: adj.saturation, range: -1 ... 1) { v in
                var a = adj; a.saturation = v; viewModel.updateColorAdjustments(a)
            }
            labeledSlider("Highlights", value: adj.highlights, range: -1 ... 1) { v in
                var a = adj; a.highlights = v; viewModel.updateColorAdjustments(a)
            }
            labeledSlider("Shadows", value: adj.shadows, range: -1 ... 1) { v in
                var a = adj; a.shadows = v; viewModel.updateColorAdjustments(a)
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

    // MARK: - Opacity

    private var opacitySection: some View {
        let clip = viewModel.selectedClip!

        return VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Opacity")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            labeledSlider("Opacity", value: clip.opacity, range: 0 ... 1) { v in
                viewModel.updateOpacity(v)
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

    // MARK: - Captions

    private var captionSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Captions")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            ForEach(viewModel.captions) { caption in
                HStack {
                    VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                        Text(caption.text)
                            .typography(.body)
                            .foregroundStyle(Color.ds.text)
                            .lineLimit(1)

                        Text("\(formatTime(caption.startTime)) - \(formatTime(caption.endTime))")
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                    }

                    Spacer()

                    Button {
                        viewModel.removeCaption(id: caption.id)
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(Color.ds.danger)
                    }
                }
                .padding(.sp3)
                .background(Color.ds.bg)
                .overlay(
                    RoundedRectangle(cornerRadius: .spacing(.sp2))
                        .stroke(Color.ds.border, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }

            HStack(spacing: .spacing(.sp2)) {
                TextField("Caption text...", text: $captionText)
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

                Button {
                    guard !captionText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    viewModel.addCaption(text: captionText)
                    captionText = ""
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                }
                .tint(Color.ds.accentFg)
                .disabled(captionText.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Metrics

    private var metricsSection: some View {
        VStack(alignment: .leading, spacing: .spacing(.sp3)) {
            Text("Debug Metrics")
                .typography(.heading)
                .foregroundStyle(Color.ds.text)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: .spacing(.sp2)) {
                metricCard(label: "Frame", value: String(format: "%.1fms", viewModel.metrics.frameLatencyMs))
                metricCard(label: "Cache Hit", value: String(format: "%.0f%%", viewModel.metrics.cacheHitRatio * 100))
                metricCard(label: "Cached", value: "\(viewModel.metrics.cachedFrameCount)")
                metricCard(label: "Rendered", value: "\(viewModel.metrics.totalFramesRendered)")
                metricCard(label: "Dropped", value: "\(viewModel.metrics.droppedFrameCount)", tint: viewModel.metrics.droppedFrameCount > 0 ? Color.ds.danger : nil)
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

    private func metricCard(label: String, value: String, tint: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            Text(value)
                .typography(.heading)
                .foregroundStyle(tint ?? Color.ds.accentFg)
                .monospacedDigit()

            Text(label)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
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

    // MARK: - Helpers

    private func labeledSlider(
        _ label: String,
        value: Float,
        range: ClosedRange<Float>,
        onChange: @escaping (Float) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: .spacing(.sp1)) {
            HStack {
                Text(label)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                Spacer()
                Text(String(format: "%.2f", value))
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .monospacedDigit()
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: { onChange($0) }
                ),
                in: range
            )
            .tint(Color.ds.accentFg)
        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    // MARK: - Import

    private func importClips(from items: [PhotosPickerItem], overlay: Bool) async {
        for item in items {
            guard let transferable = try? await item.loadTransferable(type: RenderVideoTransferable.self) else { continue }
            if overlay {
                await viewModel.addClipToNewTrack(url: transferable.localURL, displayName: transferable.filename)
            } else {
                await viewModel.addClip(url: transferable.localURL, displayName: transferable.filename)
            }
        }
        selectedItems = []
        overlayTrackItems = []
    }
}

// MARK: - Video Transferable

private struct RenderVideoTransferable: Transferable {
    let localURL: URL
    let filename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .mpeg4Movie) { received in
            try Self.importFile(received)
        }
        FileRepresentation(importedContentType: .movie) { received in
            try Self.importFile(received)
        }
    }

    private static func importFile(_ received: ReceivedTransferredFile) throws -> Self {
        let source = received.file
        let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
        let dest = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        if FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: source, to: dest)
        return Self(localURL: dest, filename: source.lastPathComponent)
    }
}

// MARK: - Preview

struct RenderingDemoView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            RenderingDemoView()
                .preferredColorScheme(.dark)
        }
    }
}
