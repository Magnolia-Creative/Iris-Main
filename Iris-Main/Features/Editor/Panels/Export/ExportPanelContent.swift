import SwiftUI
import AVFoundation

struct ExportPanelContent: View {
    @ObservedObject var controller: TimelineController

    @State private var selectedResolution: ResolutionOption = .hd1080
    @State private var selectedFrameRate: FrameRateOption = .fps30
    @State private var isExporting = false
    @State private var exportProgress: Double = 0
    @State private var showShareSheet = false
    @State private var exportedFileURL: URL?

    struct ResolutionOption: Identifiable, Hashable {
        let label: String
        let longSide: Int

        var id: Int { longSide }

        static let hd720 = ResolutionOption(label: "720p", longSide: 1280)
        static let hd1080 = ResolutionOption(label: "1080p", longSide: 1920)
        static let uhd4k = ResolutionOption(label: "4K", longSide: 3840)

        static let presets: [ResolutionOption] = [.hd720, .hd1080, .uhd4k]

        static func available(for outputSize: CGSize) -> [ResolutionOption] {
            let currentLongSide = max(Int(outputSize.width.rounded()), Int(outputSize.height.rounded()))
            let matchingPresets = presets.filter { $0.longSide <= currentLongSide }
            if matchingPresets.isEmpty {
                return [ResolutionOption(label: "\(currentLongSide)p", longSide: currentLongSide)]
            }
            return matchingPresets
        }
    }

    enum FrameRateOption: Int, CaseIterable, Identifiable {
        case fps24 = 24
        case fps30 = 30
        case fps60 = 60
        var id: Int { rawValue }
        var label: String { "\(rawValue) fps" }
    }

    var body: some View {
        VStack(spacing: .spacing(.sp3)) {
            Text("Export Settings")
                .typography(.heading)
                .foregroundColor(Color.ds.text)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: .spacing(.sp4)) {
                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Resolution")
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
                    Picker("Resolution", selection: $selectedResolution) {
                        ForEach(availableResolutions) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: .spacing(.sp2)) {
                    Text("Frame Rate")
                        .typography(.bodySmall)
                        .foregroundColor(Color.ds.textMuted)
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
        .padding(.horizontal, .sp2)
        .onChange(of: controller.state.effectiveOutputPixelSize) { _, _ in
            clampSelectedResolution()
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
            }
        }
        .onAppear {
            clampSelectedResolution()
        }
    }

    private var availableResolutions: [ResolutionOption] {
        ResolutionOption.available(for: controller.state.effectiveOutputPixelSize)
    }

    private func makeExportInput() -> RenderTimelineInput {
        var input = controller.state.makeRenderTimelineInput()
        let outputAspect = controller.state.effectiveOutputAspect ?? OutputAspectRatio(width: 16, height: 9)
        input.outputSize = outputAspect.pixelSize(longSide: selectedResolution.longSide)
        return input
    }

    private func clampSelectedResolution() {
        let available = availableResolutions
        if !available.contains(selectedResolution), let best = available.last {
            selectedResolution = best
        }
    }

    private func startExport() {
        isExporting = true
        exportProgress = 0

        let input = makeExportInput()
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("iris_export_\(UUID().uuidString).mp4")

        Task {
            do {
                try await VideoLabExportService.export(
                    input: input,
                    outputURL: tempURL,
                    frameRate: selectedFrameRate.rawValue,
                    progress: { p in
                        Task { @MainActor in
                            exportProgress = Double(p)
                        }
                    }
                )
                await MainActor.run {
                    isExporting = false
                    exportedFileURL = tempURL
                    showShareSheet = true
                }
            } catch {
                await MainActor.run {
                    isExporting = false
                    exportProgress = 0
                }
            }
        }
    }
}
