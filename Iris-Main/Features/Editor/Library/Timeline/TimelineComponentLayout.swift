import SwiftUI

struct TimelineComponentLayout: Equatable {
    let rulerHeight: CGFloat
    let readoutWidth: CGFloat
    let rulerFadeWidth: CGFloat
    let organizerTrackTopOffset: CGFloat
    let trackSpacing: CGFloat
    let videoTrackHeight: CGFloat
    let audioTrackHeight: CGFloat
    let captionTrackHeight: CGFloat
    let minimumSegmentWidth: CGFloat

    static let defaultPixelsPerSecond: CGFloat = 100
    static let minimumPixelsPerSecond: CGFloat = 40
    static let maximumPixelsPerSecond: CGFloat = 360
    static let standard = preset(TimelineTrackDisplaySize.standard)

    static func preset(_ size: EditorComponentSize) -> TimelineComponentLayout {
        preset(TimelineTrackDisplaySize(size))
    }

    static func preset(_ size: TimelineTrackDisplaySize) -> TimelineComponentLayout {
        switch size {
        case .compressed:
            return TimelineComponentLayout(
                rulerHeight: 28,
                readoutWidth: 118,
                rulerFadeWidth: .spacing(.sp5),
                organizerTrackTopOffset: .spacing(.sp3),
                trackSpacing: .spacing(.sp1),
                videoTrackHeight: .spacing(.sp5),
                audioTrackHeight: .spacing(.sp5),
                captionTrackHeight: .spacing(.sp4),
                minimumSegmentWidth: 20
            )
        case .standard:
            return TimelineComponentLayout(
                rulerHeight: 30,
                readoutWidth: 118,
                rulerFadeWidth: .spacing(.sp5),
                organizerTrackTopOffset: .spacing(.sp4),
                trackSpacing: .spacing(.sp2),
                videoTrackHeight: .spacing(.sp8),
                audioTrackHeight: .spacing(.sp8),
                captionTrackHeight: .spacing(.sp5),
                minimumSegmentWidth: 24
            )
        case .expanded:
            return TimelineComponentLayout(
                rulerHeight: 32,
                readoutWidth: 118,
                rulerFadeWidth: .spacing(.sp5),
                organizerTrackTopOffset: .spacing(.sp5),
                trackSpacing: .spacing(.sp2),
                videoTrackHeight: .spacing(.sp10),
                audioTrackHeight: .spacing(.sp10),
                captionTrackHeight: .spacing(.sp7),
                minimumSegmentWidth: 28
            )
        }
    }

    func trackHeight(for kind: TimelineTrackContentKind) -> CGFloat {
        switch kind {
        case .video: videoTrackHeight
        case .audio: audioTrackHeight
        case .caption: captionTrackHeight
        }
    }

    func trackStackHeight(for tracks: [TimelineTrackModel]) -> CGFloat {
        let heights = tracks.map { trackHeight(for: $0.kind) }.reduce(0, +)
        let spacing = CGFloat(max(0, tracks.count - 1)) * trackSpacing
        return heights + spacing
    }

    func sectionHeight(for tracks: [TimelineTrackModel]) -> CGFloat {
        rulerHeight + organizerTrackTopOffset + trackStackHeight(for: tracks)
    }
}

enum TimelineTrackContentKind: String, Codable, CaseIterable, Identifiable {
    case video
    case audio
    case caption

    var id: String { rawValue }

    init?(_ trackKind: TrackKind) {
        switch trackKind {
        case .video, .overlay:
            self = .video
        case .audio:
            self = .audio
        case .captions:
            self = .caption
        }
    }

    var displayTitle: String {
        switch self {
        case .video: "Video"
        case .audio: "Audio"
        case .caption: "Caption"
        }
    }

    var systemImageName: String {
        switch self {
        case .video: "video.fill"
        case .audio: "waveform"
        case .caption: "textformat"
        }
    }
}

enum TimelineTrackDisplaySize: String, Codable, CaseIterable, Identifiable {
    case compressed
    case standard
    case expanded

    var id: String { rawValue }

    init(_ componentSize: EditorComponentSize) {
        switch componentSize {
        case .compressed: self = .compressed
        case .standard: self = .standard
        case .expanded: self = .expanded
        }
    }
}

struct TimelineSegmentModel: Identifiable, Equatable {
    let id: String
    let rangeUs: TimeRange
    let sourceRangeUs: TimeRange?
    var title: String?
    var captionText: String?
    var mediaKind: MediaKind?
    var assetRefId: String?
    var thumbnailStripPath: String?
    var waveformPath: String?

    var durationUs: Int64 {
        max(0, rangeUs.duration)
    }

    init(
        id: String,
        rangeUs: TimeRange,
        sourceRangeUs: TimeRange? = nil,
        title: String? = nil,
        captionText: String? = nil,
        mediaKind: MediaKind? = nil,
        assetRefId: String? = nil,
        thumbnailStripPath: String? = nil,
        waveformPath: String? = nil
    ) {
        self.id = id
        self.rangeUs = rangeUs
        self.sourceRangeUs = sourceRangeUs
        self.title = title
        self.captionText = captionText
        self.mediaKind = mediaKind
        self.assetRefId = assetRefId
        self.thumbnailStripPath = thumbnailStripPath
        self.waveformPath = waveformPath
    }
}

struct TimelineTrackModel: Identifiable, Equatable {
    let id: String
    let kind: TimelineTrackContentKind
    var size: TimelineTrackDisplaySize
    var segments: [TimelineSegmentModel]
    var label: String?

    init(
        id: String,
        kind: TimelineTrackContentKind,
        size: TimelineTrackDisplaySize = .standard,
        segments: [TimelineSegmentModel] = [],
        label: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.size = size
        self.segments = segments
        self.label = label
    }
}

struct TimelineRulerModel: Equatable {
    var currentTimeUs: Int64
    var durationUs: Int64
    var pixelsPerSecond: CGFloat

    init(
        currentTimeUs: Int64,
        durationUs: Int64,
        pixelsPerSecond: CGFloat = TimelineComponentLayout.defaultPixelsPerSecond
    ) {
        self.currentTimeUs = currentTimeUs
        self.durationUs = durationUs
        self.pixelsPerSecond = pixelsPerSecond
    }
}

struct TimelineOrganizerModel: Equatable {
    var tracks: [TimelineTrackModel]
    var durationUs: Int64
    var currentTimeUs: Int64
    var pixelsPerSecond: CGFloat

    init(
        tracks: [TimelineTrackModel] = [],
        durationUs: Int64 = 0,
        currentTimeUs: Int64 = 0,
        pixelsPerSecond: CGFloat = TimelineComponentLayout.defaultPixelsPerSecond
    ) {
        self.tracks = tracks
        self.durationUs = durationUs
        self.currentTimeUs = currentTimeUs
        self.pixelsPerSecond = pixelsPerSecond
    }
}

extension TimelineSegmentModel {
    init(clip: Clip, media: Media?, fallbackTitle: String? = nil) {
        self.init(
            id: clip.clipId,
            rangeUs: clip.timelineRange,
            sourceRangeUs: clip.sourceRange,
            title: fallbackTitle,
            mediaKind: media?.kind,
            assetRefId: media?.assetRefId,
            thumbnailStripPath: media?.spec.thumbnailStripPath,
            waveformPath: media?.spec.waveformPath
        )
    }

    init(captionCue: CaptionCue) {
        self.init(
            id: captionCue.cueId,
            rangeUs: TimeRange(start: captionCue.timelineStartUs, end: captionCue.timelineEndUs),
            sourceRangeUs: captionCue.sourceStartUs.flatMap { sourceStart in
                captionCue.sourceEndUs.map { TimeRange(start: sourceStart, end: $0) }
            },
            title: captionCue.text,
            captionText: captionCue.text
        )
    }
}

extension TimelineTrackModel {
    init?(
        track: Track,
        clips: [Clip],
        mediaById: [String: Media],
        captionGroups: [CaptionGroup] = [],
        captionCues: [CaptionCue] = [],
        size: TimelineTrackDisplaySize = .standard
    ) {
        guard let contentKind = TimelineTrackContentKind(track.kind) else { return nil }
        let segments: [TimelineSegmentModel]
        if contentKind == .caption {
            let groupIds = Set(captionGroups.filter { $0.trackId == track.trackId }.map(\.groupId))
            segments = captionCues
                .filter { groupIds.contains($0.groupId) }
                .sorted { $0.timelineStartUs < $1.timelineStartUs }
                .map(TimelineSegmentModel.init(captionCue:))
        } else {
            segments = clips
                .sorted { $0.timelineRange.start < $1.timelineRange.start }
                .map { TimelineSegmentModel(clip: $0, media: mediaById[$0.mediaId]) }
        }

        self.init(
            id: track.trackId,
            kind: contentKind,
            size: size,
            segments: segments,
            label: contentKind.displayTitle
        )
    }
}

extension TimelineOrganizerModel {
    init(context: EditorTimelineContext) {
        let displaySize = TimelineTrackDisplaySize(context.layoutSize)
        let trackModels = context.tracks.compactMap { track in
            TimelineTrackModel(
                track: track,
                clips: context.clipsByTrackId[track.trackId] ?? [],
                mediaById: context.mediaById,
                captionGroups: context.captionGroups,
                captionCues: context.captionCues,
                size: displaySize
            )
        }

        self.init(
            tracks: trackModels,
            durationUs: context.timelineDurationUs,
            currentTimeUs: context.currentTimeAtCenter,
            pixelsPerSecond: context.pixelsPerSecond
        )
    }
}
