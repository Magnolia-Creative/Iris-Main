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

    enum ResolutionOption: String, CaseIterable, Identifiable {
        case hd1080 = "1080p"
        case uhd4k = "4K"
        var id: String { rawValue }
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
                        ForEach(ResolutionOption.allCases) { option in
                            Text(option.rawValue).tag(option)
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
        .sheet(isPresented: $showShareSheet) {
            if let url = exportedFileURL {
                ShareSheet(activityItems: [url])
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
