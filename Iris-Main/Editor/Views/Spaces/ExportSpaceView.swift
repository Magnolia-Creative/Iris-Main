import SwiftUI
import AVFoundation
internal import Combine

struct ExportSpaceView: View {
    @ObservedObject var controller: TimelineController
    let playbackController: PlaybackController?
    let renderBridge: TimelineRenderBridge
    var namespace: Namespace.ID

    @State private var selectedResolution: ResolutionOption = .hd1080
    @State private var selectedFrameRate: FrameRateOption = .fps30
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?

    enum ResolutionOption: String, CaseIterable, Identifiable {
        case hd1080 = "1080p"
        case uhd4k = "4K"
        var id: String { rawValue }
        var width: Int { self == .hd1080 ? 1920 : 3840 }
        var height: Int { self == .hd1080 ? 1080 : 2160 }
    }

    enum FrameRateOption: Int, CaseIterable, Identifiable {
        case fps24 = 24
        case fps30 = 30
        case fps60 = 60
        var id: Int { rawValue }
        var label: String { "\(rawValue) fps" }
    }

    var body: some View {
        let state = controller.state

        VStack(spacing: .spacing(.sp4)) {
            // Large preview
            PreviewSection(
                controller: playbackController ?? PlaybackController(
                    statePublisher: controller.$state.eraseToAnyPublisher(),
                    actions: controller
                ),
                renderBridge: renderBridge
            )
            .matchedGeometryEffect(id: "preview", in: namespace)
            .padding(.horizontal, .sp3)

            if let pc = playbackController {
                PlaybackControls(controller: pc)
                    .padding(.horizontal, .sp4)
            }

            // Fixed timeline (full width, playhead moves)
            exportTimeline(state: state)
                .frame(height: 60)
                .matchedGeometryEffect(id: "timeline", in: namespace)
                .padding(.horizontal, .sp3)

            // Render settings
            VStack(spacing: .spacing(.sp4)) {
                Text("Export Settings")
                    .typography(.heading)
                    .foregroundColor(Color.ds.text)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: .spacing(.sp4)) {
                    VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                        Text("Resolution").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                        Picker("Resolution", selection: $selectedResolution) {
                            ForEach(ResolutionOption.allCases) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                        Text("Frame Rate").typography(.bodySmall).foregroundColor(Color.ds.textMuted)
                        Picker("Frame Rate", selection: $selectedFrameRate) {
                            ForEach(FrameRateOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }

                if isExporting {
                    VStack(spacing: .spacing(.sp2)) {
                        ProgressView(value: exportProgress)
                            .tint(Color.ds.accentFg)
                        Text("Exporting... \(Int(exportProgress * 100))%")
                            .typography(.bodySmall)
                            .foregroundColor(Color.ds.textMuted)
                    }
                } else {
                    Button { startExport() } label: {
                        HStack(spacing: .spacing(.sp2)) {
                            Image(systemName: "square.and.arrow.up")
                            Text("Export")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.primary)
                }
            }
            .padding(.sp4)
            .background(Color.ds.surface)
            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp4)))
            .overlay(RoundedRectangle(cornerRadius: .spacing(.sp4)).stroke(Color.ds.border, lineWidth: 1))
            .padding(.horizontal, .sp3)

            Spacer()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func exportTimeline(state: TimelineState) -> some View {
        GeometryReader { geometry in
            let totalWidth = geometry.size.width
            let durationUs = max(1, state.calculatedTimelineDurationUs)
            let pxPerUs = totalWidth / CGFloat(durationUs)

            ZStack(alignment: .leading) {
                // Track clips (compressed)
                ForEach(state.clips) { clip in
                    let startX = CGFloat(clip.timelineRange.start) * pxPerUs
                    let clipWidth = CGFloat(clip.duration) * pxPerUs

                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.ds.accentBg)
                        .frame(width: max(clipWidth, 2), height: 24)
                        .offset(x: startX)
                }
                .frame(height: 24)
                .offset(y: 20)

                // Moving playhead
                let playheadX = CGFloat(state.currentTimeAtCenter) * pxPerUs
                Rectangle()
                    .fill(Color.ds.text)
                    .frame(width: 1, height: geometry.size.height)
                    .offset(x: playheadX)

                // Ruler marks
                HStack(spacing: 0) {
                    ForEach(0..<5, id: \.self) { i in
                        let timeUs = Int64(Double(i) / 4.0 * Double(durationUs))
                        VStack {
                            Rectangle().fill(Color.ds.border).frame(width: 1, height: 8)
                            Text(TimeFormatter.formatTime(timeUs))
                                .typography(.bodySmall)
                                .foregroundColor(Color.ds.textMuted)
                                .fixedSize()
                        }
                        if i < 4 { Spacer() }
                    }
                }
            }
        }
    }

    private func startExport() {
        isExporting = true
        exportProgress = 0

        Task {
            for i in 1...100 {
                try? await Task.sleep(nanoseconds: 30_000_000)
                await MainActor.run { exportProgress = Double(i) / 100.0 }
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("iris_export_\(UUID().uuidString).mp4")

            await MainActor.run {
                isExporting = false
                exportedFileURL = tempURL
                showShareSheet = true
            }
        }
    }
}
