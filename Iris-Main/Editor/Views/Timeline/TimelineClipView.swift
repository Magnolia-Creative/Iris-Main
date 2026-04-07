import SwiftUI

struct TimelineClipView: View {
    let clip: Clip
    let trackKind: TrackKind
    let media: Media?
    let isSelected: Bool
    let isDragging: Bool
    let width: CGFloat
    let height: CGFloat
    @State private var thumbnail: UIImage?
    @State private var thumbnailStrip: UIImage?
    @State private var waveformImage: UIImage?

    var body: some View {
        let cornerRadius: CGFloat = .spacing(.sp1)
        let isPhoto = media?.kind == .photo
        let contentHeight = max(0, height)
        let waveformHeight: CGFloat = .spacing(.sp3)
        let clipRange = clipSourceUnits

        VStack(spacing: 0) {
            ZStack(alignment: .bottom) {
                if trackKind == .video, let thumbnailStrip, let clipRange {
                    StripThumbnailView(stripImage: thumbnailStrip, startUnit: clipRange.start, endUnit: clipRange.end)
                } else if trackKind == .video, let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                } else {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color.clear)
                }

                if trackKind != .video {
                    Image(systemName: "photo.fill.on.rectangle.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.ds.accentFg)
                }

                if trackKind == .video, let waveformImage, let clipRange {
                    WaveformThumbnailView(waveformImage: waveformImage, startUnit: clipRange.start, endUnit: clipRange.end)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                        .background(Color.black.opacity(0.4))
                        .frame(height: waveformHeight + 4)
                }
            }
            .frame(height: contentHeight)
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .overlay(alignment: .topLeading) {
            if trackKind == .video {
                Image(systemName: isPhoto ? "photo.fill" : "video.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(RoundedRectangle(cornerRadius: .spacing(.sp1)).fill(Color.black.opacity(0.6)))
                    .padding(.top, .spacing(.sp1))
                    .padding(.leading, .spacing(.sp1))
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius).stroke(Color.ds.border, lineWidth: 2)
        )
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius)
                .strokeBorder(Color.ds.accentFg, lineWidth: 3)
                .opacity(isSelected ? 1 : 0)
                .scaleEffect(isSelected ? 1 : 0.98)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isSelected)
        .opacity(isDragging ? 0.25 : 1)
        .task(id: thumbnailTaskId) {
            guard trackKind == .video, let media else {
                thumbnail = nil
                thumbnailStrip = nil
                waveformImage = nil
                return
            }
            let size = CGSize(width: width, height: height)
            if isPhoto {
                thumbnailStrip = nil
                waveformImage = nil
                do {
                    let stream = try ThumbnailService.shared.loadThumbnailStream(for: media.assetRefId, size: size)
                    for await update in stream {
                        if let image = update.image { thumbnail = image }
                        if update.isFinal { break }
                    }
                } catch { thumbnail = nil }
            } else {
                thumbnailStrip = nil
                async let stripImage = ThumbnailService.shared.loadThumbnailStripImage(for: media)
                async let waveform = ThumbnailService.shared.loadWaveformImage(for: media)

                do {
                    let stream = try ThumbnailService.shared.loadThumbnailStream(for: media.assetRefId, size: size)
                    for await update in stream {
                        if let image = update.image { thumbnail = image }
                        if update.isFinal { break }
                    }
                } catch { thumbnail = nil }

                waveformImage = await waveform
                if let resolvedStrip = await stripImage {
                    thumbnailStrip = resolvedStrip
                    thumbnail = nil
                }
            }
        }
    }

    private var thumbnailTaskId: String {
        let widthBucket = max(1, Int(width.rounded(.up)))
        let heightBucket = max(1, Int(height.rounded(.up)))
        let stripPath = media?.spec.thumbnailStripPath ?? "nostrip"
        return "\(media?.mediaId ?? "none")-\(trackKind)-\(stripPath)-\(widthBucket)x\(heightBucket)"
    }

    private var clipSourceUnits: (start: CGFloat, end: CGFloat)? {
        guard let duration = media?.spec.duration, duration > 0 else { return nil }
        let startSeconds = Double(clip.sourceRange.start) / 1_000_000.0
        let endSeconds = Double(clip.sourceRange.end) / 1_000_000.0
        let startUnit = max(0, min(1, startSeconds / duration))
        let endUnit = max(startUnit, min(1, endSeconds / duration))
        return (start: CGFloat(startUnit), end: CGFloat(endUnit))
    }
}

private struct StripThumbnailView: View {
    let stripImage: UIImage
    let startUnit: CGFloat
    let endUnit: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clampedStart = max(0, min(1, startUnit))
            let clampedEnd = max(clampedStart + 0.0001, min(1, endUnit))
            let range = clampedEnd - clampedStart
            let scaledWidth = width / range

            Image(uiImage: stripImage)
                .resizable()
                .scaledToFill()
                .frame(width: scaledWidth, height: height)
                .offset(x: -clampedStart * scaledWidth)
                .clipped()
        }
    }
}

private struct WaveformThumbnailView: View {
    let waveformImage: UIImage
    let startUnit: CGFloat
    let endUnit: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let clampedStart = max(0, min(1, startUnit))
            let clampedEnd = max(clampedStart + 0.0001, min(1, endUnit))
            let range = clampedEnd - clampedStart
            let scaledWidth = width / range

            Image(uiImage: waveformImage)
                .resizable()
                .scaledToFill()
                .frame(width: scaledWidth, height: height)
                .offset(x: -clampedStart * scaledWidth)
                .clipped()
                .opacity(0.85)
        }
    }
}
