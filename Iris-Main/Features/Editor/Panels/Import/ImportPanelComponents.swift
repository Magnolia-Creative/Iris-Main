import AVKit
import SwiftUI

struct MediaThumbnailCell: View {
    let media: Media
    let dragItem: ImportedTimelineSegment?
    let previewHeroID: String?
    let previewNamespace: Namespace.ID?
    let isPreviewSourceHidden: Bool
    @State private var thumbnail: UIImage?

    init(
        media: Media,
        dragItem: ImportedTimelineSegment? = nil,
        previewHeroID: String? = nil,
        previewNamespace: Namespace.ID? = nil,
        isPreviewSourceHidden: Bool = false
    ) {
        self.media = media
        self.dragItem = dragItem
        self.previewHeroID = previewHeroID
        self.previewNamespace = previewNamespace
        self.isPreviewSourceHidden = isPreviewSourceHidden
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.ds.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: media.kind == .video ? "video.fill" : "photo.fill")
                        .foregroundColor(Color.ds.textMuted)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .matchedPreviewIfPresent(previewHeroID, in: previewNamespace)
            .opacity(isPreviewSourceHidden ? 0.001 : 1)
            .draggableIfPresent(dragItem) {
                HStack(spacing: .spacing(.sp2)) {
                    Image(systemName: media.kind == .video ? "video.fill" : "photo.fill")
                        .foregroundStyle(Color.ds.accentFg)
                    Text(media.kind == .video ? "Video clip" : "Photo clip")
                        .typography(.bodySmall)
                        .foregroundStyle(Color.ds.text)
                }
                .padding(.sp3)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
            .task {
                let loadStart = EditorDebugTrace.mark()
                thumbnail = try? await ThumbnailService.shared.loadThumbnail(
                    for: media.assetRefId,
                    size: CGSize(width: 160, height: 160)
                )
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - loadStart) * 1000
                if elapsedMs > 150 {
                    EditorDebugTrace.log(
                        "MediaThumbnailCell",
                        "slow thumbnail mediaId=\(media.mediaId) kind=\(media.kind.rawValue) elapsed=\(String(format: "%.1fms", elapsedMs))"
                    )
                }
            }
    }
}

struct ImportClipPreviewItem: Identifiable {
    let id = UUID()
    let media: Media
    let heroID: String
    let title: String
    let subtitle: String?
    let clipRangeSeconds: ClosedRange<Double>?

    init(media: Media, range: SemanticMatchRange? = nil, heroID: String) {
        self.media = media
        self.heroID = heroID
        self.title = "Clip Preview"
        if let range {
            self.subtitle = "\(Self.formatTime(range.startTimeSeconds)) - \(Self.formatTime(range.endTimeSeconds))"
            self.clipRangeSeconds = range.startTimeSeconds...range.endTimeSeconds
        } else {
            if let duration = media.spec.duration, duration > 0 {
                self.subtitle = "Duration \(Self.formatTime(duration))"
            } else {
                self.subtitle = nil
            }
            self.clipRangeSeconds = nil
        }
    }

    private static func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }
}

struct SemanticResultGroup: Identifiable {
    let id: String
    let source: SemanticSearchResultSource
    let segments: [SemanticMatchRange]
}

struct SemanticGroupSelection: Equatable {
    let source: SemanticSearchResultSource
    let videoID: String
}

struct SemanticVideoResultCell: View {
    let media: Media
    let matchCount: Int

    var body: some View {
        MediaThumbnailCell(media: media)
            .overlay(alignment: .topTrailing) {
                if matchCount > 1 {
                    Text("\(matchCount)")
                        .typography(.bodySmall)
                        .foregroundStyle(.white)
                        .padding(.horizontal, .sp2)
                        .padding(.vertical, 3)
                        .background(Color.ds.accentBg)
                        .clipShape(Capsule())
                        .padding(6)
                }
            }
    }
}

struct SemanticRangeThumbnailCell: View {
    let result: SemanticMatchRange
    let assetRefId: String
    let previewHeroID: String?
    let previewNamespace: Namespace.ID?
    let isPreviewSourceHidden: Bool
    @State private var thumbnail: UIImage?

    var body: some View {
        let transferItem = ImportedTimelineSegment(
            mediaId: result.videoID,
            startTimeUs: timeToMicroseconds(result.startTimeSeconds),
            endTimeUs: timeToMicroseconds(result.endTimeSeconds)
        )

        RoundedRectangle(cornerRadius: 4)
            .fill(Color.ds.surface)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    Image(systemName: "video.fill")
                        .foregroundColor(Color.ds.textMuted)
                }
            }
            .overlay(alignment: .bottomLeading) {
                VStack(alignment: .leading, spacing: 4) {
                    if let matchText = result.matchText, result.source == .audio {
                        Text(matchText)
                            .typography(.bodySmall)
                            .lineLimit(2)
                            .foregroundStyle(.white)
                    }

                    Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                        .typography(.bodySmall)
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, .sp2)
                .padding(.vertical, 3)
                .background(Color.black.opacity(0.72))
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
                .padding(6)
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .matchedPreviewIfPresent(previewHeroID, in: previewNamespace)
            .opacity(isPreviewSourceHidden ? 0.001 : 1)
            .draggable(transferItem) {
                Text("\(formatTime(result.startTimeSeconds)) - \(formatTime(result.endTimeSeconds))")
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.text)
                    .padding(.sp3)
                    .background(Color.ds.surface)
                    .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp2)))
            }
            .task {
                let loadStart = EditorDebugTrace.mark()
                let midpoint = max(result.startTimeSeconds, (result.startTimeSeconds + result.endTimeSeconds) / 2)
                thumbnail = try? await ThumbnailService.shared.loadVideoThumbnails(
                    for: assetRefId,
                    size: CGSize(width: 160, height: 160),
                    times: [midpoint]
                ).first
                let elapsedMs = (ProcessInfo.processInfo.systemUptime - loadStart) * 1000
                if elapsedMs > 150 {
                    EditorDebugTrace.log(
                        "SemanticRangeThumbnailCell",
                        "slow range thumbnail mediaId=\(result.videoID) elapsed=\(String(format: "%.1fms", elapsedMs))"
                    )
                }
            }
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func timeToMicroseconds(_ seconds: Double) -> Int64 {
        Int64((seconds * 1_000_000).rounded())
    }
}

struct SemanticLoadingThumbnailCell: View {
    let position: Int
    let totalCount: Int

    var body: some View {
        TimelineView(.animation) { context in
            let opacity = pulseOpacity(at: context.date)

            RoundedRectangle(cornerRadius: 4)
                .fill(Color.ds.surface)
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(opacity))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.ds.border.opacity(0.6), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    private func pulseOpacity(at date: Date) -> Double {
        let normalizedPosition = totalCount > 1 ? Double(position) / Double(totalCount - 1) : 0
        let phaseOffset = -Double.pi / 2 + (normalizedPosition * Double.pi)
        let wave = (sin((date.timeIntervalSinceReferenceDate * 2 * Double.pi / 1.1) + phaseOffset) + 1) / 2
        return 0.03 + (wave * 0.07)
    }
}

struct ImportClipPreviewOverlay: View {
    let item: ImportClipPreviewItem
    let namespace: Namespace.ID
    let onClose: () -> Void

    @State private var image: UIImage?
    @State private var videoURL: URL?
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: .spacing(.sp3)) {
            HStack {
                VStack(alignment: .leading, spacing: .spacing(.sp1)) {
                    Text(item.title)
                        .typography(.body)
                        .foregroundStyle(Color.ds.text)

                    if let subtitle = item.subtitle {
                        Text(subtitle)
                            .typography(.bodySmall)
                            .foregroundStyle(Color.ds.textMuted)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ds.textMuted)
                        .frame(width: 28, height: 28)
                        .background(Color.ds.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Group {
                if let loadError {
                    previewUnavailableState(title: "Preview unavailable", subtitle: loadError)
                } else if item.media.kind == .photo {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
                            .matchedGeometryEffect(id: item.heroID, in: namespace)
                    } else {
                        ProgressView()
                            .tint(Color.ds.accentFg)
                            .frame(maxWidth: .infinity, minHeight: 240)
                    }
                } else if let videoURL {
                    ClipRangePlayerView(
                        url: videoURL,
                        clipRangeSeconds: item.clipRangeSeconds,
                        durationHint: item.media.spec.duration
                    )
                    .matchedGeometryEffect(id: item.heroID, in: namespace)
                } else {
                    ProgressView()
                        .tint(Color.ds.accentFg)
                        .frame(maxWidth: .infinity, minHeight: 240)
                }
            }
        }
        .padding(.sp3)
        .frame(maxWidth: 360)
        .background(Color.ds.bg)
        .overlay(
            RoundedRectangle(cornerRadius: .spacing(.sp3))
                .stroke(Color.ds.border.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 14)
        .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))
        .task {
            await loadPreview()
        }
    }

    @ViewBuilder
    private func previewUnavailableState(title: String, subtitle: String) -> some View {
        VStack(spacing: .spacing(.sp2)) {
            Image(systemName: "eye.slash")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Color.ds.textMuted)

            Text(title)
                .typography(.body)
                .foregroundStyle(Color.ds.text)

            Text(subtitle)
                .typography(.bodySmall)
                .foregroundStyle(Color.ds.textMuted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
        .padding(.horizontal, .sp3)
    }

    private func loadPreview() async {
        loadError = nil
        image = nil
        videoURL = nil

        do {
            switch item.media.kind {
            case .photo:
                image = try await ThumbnailService.shared.loadThumbnail(
                    for: item.media.assetRefId,
                    size: CGSize(width: 1_200, height: 1_200)
                )
                if image == nil {
                    loadError = "Couldn't load that photo."
                }
            case .video:
                videoURL = try await ThumbnailService.shared.loadVideoURL(for: item.media.assetRefId)
                if videoURL == nil {
                    loadError = "Couldn't load that video."
                }
            case .audio:
                loadError = "Audio preview isn't available here yet."
            }
        } catch {
            loadError = error.localizedDescription
        }
    }
}

struct ClipRangePlayerView: View {
    let url: URL
    let clipRangeSeconds: ClosedRange<Double>?
    let durationHint: Double?

    @State private var player = AVPlayer()
    @State private var timeObserver: Any?
    @State private var isPlaying = false
    @State private var progress = 0.0
    @State private var isScrubbing = false

    var body: some View {
        VStack(spacing: .spacing(.sp2)) {
            VideoPlayer(player: player)
                .frame(height: 220)
                .background(Color.ds.surface)
                .clipShape(RoundedRectangle(cornerRadius: .spacing(.sp3)))

            HStack(spacing: .spacing(.sp2)) {
                Button {
                    togglePlayback()
                } label: {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.ds.text)
                        .frame(width: 32, height: 32)
                        .background(Color.ds.surface)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Slider(
                    value: Binding(
                        get: { progress },
                        set: { progress = $0 }
                    ),
                    in: 0...1,
                    onEditingChanged: handleScrubbingChanged(_:)
                )
                .tint(Color.ds.accentFg)

                Text(formattedElapsedTime)
                    .typography(.bodySmall)
                    .foregroundStyle(Color.ds.textMuted)
                    .monospacedDigit()
            }
        }
        .onAppear {
            configurePlayer()
        }
        .onDisappear {
            tearDownPlayer()
        }
    }

    private func configurePlayer() {
        tearDownPlayer()

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        player.actionAtItemEnd = .none

        let startTime = CMTime(seconds: rangeStartSeconds, preferredTimescale: 600)
        player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)

        timeObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.05, preferredTimescale: 600),
            queue: .main
        ) { currentTime in
            let seconds = currentTime.seconds
            guard seconds.isFinite else { return }

            if seconds >= rangeEndSeconds {
                let startTime = CMTime(seconds: rangeStartSeconds, preferredTimescale: 600)
                player.seek(to: startTime, toleranceBefore: .zero, toleranceAfter: .zero)
                if isPlaying {
                    player.play()
                } else {
                    player.pause()
                }
            }

            guard !isScrubbing else { return }
            let relative = max(0, min(previewDurationSeconds, seconds - rangeStartSeconds))
            progress = previewDurationSeconds > 0 ? relative / previewDurationSeconds : 0
        }

        player.play()
        isPlaying = true
    }

    private func togglePlayback() {
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
    }

    private func handleScrubbingChanged(_ isEditing: Bool) {
        isScrubbing = isEditing

        if isEditing {
            player.pause()
            return
        }

        let seekSeconds = rangeStartSeconds + (progress * previewDurationSeconds)
        let seekTime = CMTime(seconds: seekSeconds, preferredTimescale: 600)
        player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        if isPlaying {
            player.play()
        }
    }

    private var rangeStartSeconds: Double {
        clipRangeSeconds?.lowerBound ?? 0
    }

    private var rangeEndSeconds: Double {
        if let clipRangeSeconds {
            return clipRangeSeconds.upperBound
        }
        return max(durationHint ?? 0, 0.1)
    }

    private var previewDurationSeconds: Double {
        max(rangeEndSeconds - rangeStartSeconds, 0.1)
    }

    private var formattedElapsedTime: String {
        let elapsed = progress * previewDurationSeconds
        return "\(formatTime(elapsed)) / \(formatTime(previewDurationSeconds))"
    }

    private func formatTime(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let mins = total / 60
        let secs = total % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    private func tearDownPlayer() {
        player.pause()
        isPlaying = false
        if let timeObserver {
            player.removeTimeObserver(timeObserver)
            self.timeObserver = nil
        }
        player.replaceCurrentItem(with: nil)
    }
}

