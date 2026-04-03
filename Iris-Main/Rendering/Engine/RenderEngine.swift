import MetalKit
import simd
import QuartzCore
import os

final class RenderEngine: NSObject {
    private struct CacheLookupStats {
        var exactHits: Int = 0
        var nearestHits: Int = 0
        var fallbackHits: Int = 0
        var misses: Int = 0
    }

    private(set) var currentTime: Double = 0
    private(set) var isPlaying: Bool = false
    private(set) var metrics: RenderMetrics = RenderMetrics()

    var onTimeChanged: ((Double) -> Void)?
    var onPlaybackStateChanged: ((Bool) -> Void)?
    var onMetricsUpdated: ((RenderMetrics) -> Void)?

    private let metalContext: MetalContext
    private let compositor: CompositorPipeline
    private let captionRenderer: CaptionRenderer
    private let frameCache: FrameCache
    private let frameScheduler: FrameScheduler
    private let assetProvider: AssetFrameProvider

    private var timeline: RenderTimelineInput = .empty
    private var lastDrawTime: CFTimeInterval = 0
    private var lastPrefetchTime: CFTimeInterval = 0
    private var lastMetricsBroadcast: CFTimeInterval = 0
    private var lastMissPrefetchTime: CFTimeInterval = 0
    private var lastCacheLookupLogTime: CFTimeInterval = 0
    private weak var mtkView: MTKView?
    private var prefetchTask: Task<Void, Never>?
    private var activePrefetchTasks: [Int: Task<Void, Never>] = [:]
    private var needsRedraw: Bool = true
    private var lastRenderedTextures: [UUID: MTLTexture] = [:]
    private var isScrubbing: Bool = false
    private var lastScrubPrefetchTime: CFTimeInterval = 0
    private let inFlightKeys = LockedSet<FrameCache.CacheKey>()
    private let prefetchGeneration = LockedValue<Int>(0)
    private let lastRedrawSignalTime = LockedValue<CFTimeInterval>(0)
    private let isPrefetchActive = LockedValue<Bool>(false)
    private let pendingScrubPrefetchIntent = LockedValue<RenderIntent?>(nil)

    private let maxConcurrentDecodes = 4
    private let redrawCoalesceInterval = 4
    private let scrubPrefetchInterval: CFTimeInterval = 1.0 / 40.0

    #if DEBUG
    private static let logger = Logger(subsystem: "Iris-Main", category: "Render.Engine")
    #endif

    override init() {
        let context = try! MetalContext()
        self.metalContext = context
        self.compositor = try! CompositorPipeline(metalContext: context)
        self.captionRenderer = CaptionRenderer(metalContext: context)
        self.frameCache = FrameCache()
        self.frameScheduler = FrameScheduler()
        self.assetProvider = AssetFrameProvider(metalContext: context)
        super.init()
    }

    // MARK: - Public API

    func configure(timeline: RenderTimelineInput) {
        self.timeline = timeline
        cancelAllPrefetch()
        frameCache.clear()
        captionRenderer.clearCache()
        assetProvider.invalidateAll()
        lastRenderedTextures.removeAll()
        inFlightKeys.removeAll()
        currentTime = 0
        needsRedraw = true
        triggerPrefetch(intent: .playback)
    }

    func updateTimeline(_ timeline: RenderTimelineInput) {
        self.timeline = timeline
        requestRedraw()
        triggerPrefetch(intent: .scrub(velocity: 0))
    }

    func bindPreview(to view: MTKView) {
        view.device = metalContext.device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        self.mtkView = view
    }

    private func setDrawingMode(continuous: Bool) {
        guard let view = mtkView else { return }
        if continuous {
            view.enableSetNeedsDisplay = false
            view.isPaused = false
        } else {
            view.isPaused = true
            view.enableSetNeedsDisplay = true
        }
    }

    func requestRedraw() {
        needsRedraw = true
        if !isPlaying {
            mtkView?.setNeedsDisplay()
        }
    }

    func play() {
        guard !isPlaying, timeline.duration > 0 else { return }
        isScrubbing = false
        assetProvider.resetSequentialReaders()
        if currentTime >= timeline.duration {
            currentTime = 0
        }
        isPlaying = true
        lastDrawTime = CACurrentMediaTime()
        needsRedraw = true
        setDrawingMode(continuous: true)
        onPlaybackStateChanged?(true)
        triggerPrefetch(intent: .playback)
    }

    func pause() {
        guard isPlaying else { return }
        isPlaying = false
        setDrawingMode(continuous: false)
        onPlaybackStateChanged?(false)
        cancelAllPrefetch()
        mtkView?.setNeedsDisplay()
    }

    private func cancelAllPrefetch() {
        prefetchTask?.cancel()
        for (_, task) in activePrefetchTasks {
            task.cancel()
        }
        activePrefetchTasks.removeAll()
        assetProvider.cancelAllPendingDecodes()
        pendingScrubPrefetchIntent.modify { $0 = nil }
    }

    func seek(to time: Double, intent: RenderIntent = .scrub(velocity: 0)) {
        let clampedTime = max(0, min(time, timeline.duration))
        let previousTime = currentTime
        switch intent {
        case .playback:
            currentTime = clampedTime
        case .scrub(let velocity):
            // Keep scrub responsive while still avoiding over-rendering.
            let quantum: Double
            if isScrubbing {
                if abs(velocity) > 20 {
                    quantum = 1.0 / 24.0
                } else if abs(velocity) > 8 {
                    quantum = 1.0 / 30.0
                } else {
                    quantum = 1.0 / 45.0
                }
            } else {
                quantum = 1.0 / 60.0
            }
            let quantized = (clampedTime / quantum).rounded() * quantum
            currentTime = max(0, min(quantized, timeline.duration))
        }
        requestRedraw()
        onTimeChanged?(currentTime)

        let shouldTriggerPrefetch: Bool = {
            guard case .scrub = intent, isScrubbing else { return true }
            let now = CACurrentMediaTime()
            if now - lastScrubPrefetchTime >= scrubPrefetchInterval {
                lastScrubPrefetchTime = now
                return true
            }
            return false
        }()

        if shouldTriggerPrefetch {
            triggerPrefetch(intent: intent)
        } else if case .scrub(let velocity) = intent {
            #if DEBUG
            Self.logger.debug(
                "scrub prefetch throttled time=\(self.currentTime, format: .fixed(precision: 3))s previous=\(previousTime, format: .fixed(precision: 3))s velocity=\(velocity, format: .fixed(precision: 2))"
            )
            #endif
        }
    }

    func setScrubbing(_ scrubbing: Bool) {
        isScrubbing = scrubbing
        lastScrubPrefetchTime = 0
        if scrubbing {
            assetProvider.resetSequentialReaders()
        } else {
            triggerPrefetch(intent: .scrub(velocity: 0))
        }
    }

    func loadAssetDuration(for url: URL) async throws -> Double {
        try await assetProvider.assetDuration(for: url)
    }

    // MARK: - Prefetch

    private func triggerPrefetch(intent: RenderIntent) {
        let shouldCoalesceScrub: Bool = {
            guard case .scrub = intent, isScrubbing else { return false }
            return isPrefetchActive.value
        }()
        if shouldCoalesceScrub {
            pendingScrubPrefetchIntent.modify { $0 = intent }
            #if DEBUG
            if case .scrub(let velocity) = intent {
                Self.logger.debug(
                    "scrub prefetch coalesced time=\(self.currentTime, format: .fixed(precision: 3))s velocity=\(velocity, format: .fixed(precision: 2))"
                )
            }
            #endif
            return
        }

        let shouldCancelExisting: Bool = {
            switch intent {
            case .playback:
                return true
            case .scrub:
                // During active scrubbing, avoid cancellation storms that prevent
                // decode tasks from ever inserting into cache.
                return !isScrubbing
            }
        }()
        if shouldCancelExisting {
            prefetchTask?.cancel()
        }
        let generation = prefetchGeneration.modify { $0 += 1; return $0 }
        isPrefetchActive.modify { $0 = true }
        activePrefetchTasks = activePrefetchTasks.filter { !$0.value.isCancelled }

        let timelineCopy = timeline
        let time = currentTime
        let cache = frameCache
        let scheduler = frameScheduler
        let provider = assetProvider
        let captions = captionRenderer
        let inFlight = inFlightKeys
        let maxConcurrent = (isScrubbing && !isPlaying) ? 2 : maxConcurrentDecodes
        let coalesceInterval = redrawCoalesceInterval
        let redrawDuringPrefetch: Bool = {
            if case .playback = intent { return true }
            return isScrubbing
        }()
        let minRedrawInterval: CFTimeInterval = isPlaying ? 0.05 : 1.0 / 30.0
        let previewSize = mtkView.map { CGSize(width: $0.drawableSize.width, height: $0.drawableSize.height) }
        let displayScale = mtkView.map { CGFloat($0.contentScaleFactor) } ?? 2.0
        let generationTracker = prefetchGeneration
        let redrawSignalTracker = lastRedrawSignalTime
        let prefetchActiveTracker = isPrefetchActive
        let pendingScrubIntentTracker = pendingScrubPrefetchIntent

        let task = Task.detached(priority: .userInitiated) { [weak self] in
            defer {
                prefetchActiveTracker.modify { $0 = false }
                Task { @MainActor [weak self] in
                    self?.activePrefetchTasks.removeValue(forKey: generation)
                }
                if !Task.isCancelled {
                    let pendingIntent = pendingScrubIntentTracker.modify { pending in
                        let value = pending
                        pending = nil
                        return value
                    }
                    if let pendingIntent {
                        Task { @MainActor in
                            self?.triggerPrefetch(intent: pendingIntent)
                        }
                    }
                }
            }

            let plan = scheduler.computeFramesToPrefetch(
                timeline: timelineCopy,
                currentTime: time,
                intent: intent,
                cache: cache
            )

            let requests = plan.flat.filter { request in
                let key = FrameCache.CacheKey(clipID: request.clipID, time: request.sourceTime)
                return !inFlight.contains(key) && cache.get(key) == nil
            }
            self?.logPrefetchStart(
                generation: generation,
                intent: intent,
                planCount: plan.flat.count,
                requestCount: requests.count
            )
            #if DEBUG
            if case .scrub(let velocity) = intent {
                let firstRequest = requests.first?.sourceTime ?? -1
                let lastRequest = requests.last?.sourceTime ?? -1
                Self.logger.debug(
                    "scrub work gen=\(generation) velocity=\(velocity, format: .fixed(precision: 2)) requests=\(requests.count) first=\(firstRequest, format: .fixed(precision: 3))s last=\(lastRequest, format: .fixed(precision: 3))s cache=\(cache.count)"
                )
            }
            #endif

            let isPlaybackIntent: Bool = {
                if case .playback = intent { return true }
                return false
            }()

            if isPlaybackIntent {
                // Sequential decode via AVAssetReader (zero-copy CVPixelBuffer path).
                // Reads frames in order, reusing hardware decoder state across frames.
                var insertedFrames = 0
                var insertsSinceNotify = 0

                if !timelineCopy.captions.isEmpty, let size = previewSize {
                    captions.prerenderCaptions(
                        timelineCopy.captions,
                        near: time,
                        outputSize: size,
                        displayScale: displayScale
                    )
                }

                let sortedRequests = requests.sorted { $0.sourceTime < $1.sourceTime }
                for request in sortedRequests {
                    guard !Task.isCancelled else { break }

                    let key = FrameCache.CacheKey(clipID: request.clipID, time: request.sourceTime)
                    inFlight.insert(key)
                    do {
                        defer { inFlight.remove(key) }

                        do {
                            let decoded = try await provider.decodeFrameForPlayback(
                                from: request.assetURL,
                                at: request.sourceTime
                            )
                            guard !Task.isCancelled else { break }
                            cache.insert(key, texture: decoded.texture, backing: decoded.backing)
                            let actualKey = FrameCache.CacheKey(clipID: request.clipID, time: decoded.actualTime)
                            if actualKey != key {
                                cache.insert(actualKey, texture: decoded.texture, backing: decoded.backing)
                            }
                            insertedFrames += 1
                            insertsSinceNotify += 1
                        } catch {
                            self?.logDecodeFailure(error: error, request: request)
                        }

                        if redrawDuringPrefetch && insertsSinceNotify >= coalesceInterval {
                            insertsSinceNotify = 0
                            let now = CACurrentMediaTime()
                            let shouldSignal = redrawSignalTracker.modify { lastSignal in
                                if now - lastSignal >= minRedrawInterval {
                                    lastSignal = now
                                    return true
                                }
                                return false
                            }
                            if shouldSignal {
                                await MainActor.run {
                                    self?.requestRedraw()
                                }
                            }
                        }
                    }
                }

                if insertedFrames > 0 {
                    await MainActor.run {
                        self?.requestRedraw()
                    }
                }
                self?.logPrefetchFinish(generation: generation, requested: requests.count, inserted: insertedFrames)
            } else {
                // Concurrent decode via AVAssetImageGenerator for scrub/random access.
                await withTaskGroup(of: Bool.self) { group in
                    if !timelineCopy.captions.isEmpty, let size = previewSize {
                        group.addTask {
                            captions.prerenderCaptions(
                                timelineCopy.captions,
                                near: time,
                                outputSize: size,
                                displayScale: displayScale
                            )
                            return true
                        }
                    }

                    var active = 0
                    var insertsSinceNotify = 0
                    var insertedFrames = 0

                    for request in requests {
                        guard !Task.isCancelled, generationTracker.value == generation else { break }

                        let key = FrameCache.CacheKey(clipID: request.clipID, time: request.sourceTime)
                        inFlight.insert(key)

                        if active >= maxConcurrent {
                            if let success = await group.next(), success {
                                insertsSinceNotify += 1
                                insertedFrames += 1
                            }
                            active -= 1

                            if redrawDuringPrefetch && insertsSinceNotify >= coalesceInterval {
                                insertsSinceNotify = 0
                                let now = CACurrentMediaTime()
                                let shouldSignal = redrawSignalTracker.modify { lastSignal in
                                    if now - lastSignal >= minRedrawInterval {
                                        lastSignal = now
                                        return true
                                    }
                                    return false
                                }
                                if !shouldSignal { continue }
                                await MainActor.run {
                                    self?.requestRedraw()
                                }
                            }
                        }

                        active += 1
                        group.addTask {
                            defer { inFlight.remove(key) }
                            guard !Task.isCancelled else { return false }
                            do {
                                let decoded = try await provider.decodeFrame(
                                    from: request.assetURL,
                                    at: request.sourceTime,
                                    maxSize: previewSize
                                )
                                guard !Task.isCancelled else { return false }
                                cache.insert(key, texture: decoded.texture, backing: decoded.backing)
                                let actualKey = FrameCache.CacheKey(clipID: request.clipID, time: decoded.actualTime)
                                if actualKey != key {
                                    cache.insert(actualKey, texture: decoded.texture, backing: decoded.backing)
                                }
                                return true
                            } catch {
                                self?.logDecodeFailure(error: error, request: request)
                                return false
                            }
                        }
                    }

                    for await success in group {
                        if success {
                            insertsSinceNotify += 1
                            insertedFrames += 1
                        }
                        if redrawDuringPrefetch && insertsSinceNotify >= coalesceInterval {
                            insertsSinceNotify = 0
                            let now = CACurrentMediaTime()
                            let shouldSignal = redrawSignalTracker.modify { lastSignal in
                                if now - lastSignal >= minRedrawInterval {
                                    lastSignal = now
                                    return true
                                }
                                return false
                            }
                            if !shouldSignal { continue }
                            await MainActor.run {
                                self?.requestRedraw()
                            }
                        }
                    }

                    if insertedFrames > 0 {
                        await MainActor.run {
                            self?.requestRedraw()
                        }
                    }
                    #if DEBUG
                    if case .scrub(let velocity) = intent, insertedFrames == 0, requests.count > 0 {
                        Self.logger.debug(
                            "scrub inserted nothing gen=\(generation) velocity=\(velocity, format: .fixed(precision: 2)) requested=\(requests.count) cache=\(cache.count)"
                        )
                    }
                    #endif
                    self?.logPrefetchFinish(generation: generation, requested: requests.count, inserted: insertedFrames)
                }
            }
        }
        prefetchTask = task
        activePrefetchTasks[generation] = task
    }

    // MARK: - Render

    private func renderCurrentFrame(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let commandBuffer = metalContext.commandQueue.makeCommandBuffer()
        else { return }

        let frameStart = CACurrentMediaTime()
        var cacheHits = 0
        var cacheMisses = 0
        var lookupStats = CacheLookupStats()
        var notableEvents: [String] = []

        let sortedTracks = timeline.tracks.sorted { $0.zOrder < $1.zOrder }
        var layers: [CompositorPipeline.Layer] = []
        let outputSize = CGSize(width: drawable.texture.width, height: drawable.texture.height)

        for track in sortedTracks {
            for clip in track.clips {
                guard clip.timelineRange.contains(currentTime) else { continue }
                let sourceTime = FrameScheduler.mapToSourceTime(timelineTime: currentTime, clip: clip)
                let key = FrameCache.CacheKey(clipID: clip.id, time: sourceTime)

                let texture: MTLTexture?
                if let cached = frameCache.get(key) {
                    cacheHits += 1
                    lookupStats.exactHits += 1
                    texture = cached
                } else if let nearby = frameCache.nearestResult(clipID: clip.id, time: sourceTime) {
                    cacheHits += 1
                    lookupStats.nearestHits += 1
                    texture = nearby.texture
                    if nearby.distanceMs >= 120, notableEvents.count < 3 {
                        notableEvents.append("nearest clip=\(clip.id.uuidString.prefix(8)) dist=\(nearby.distanceMs)ms")
                    }
                } else if let fallback = lastRenderedTextures[clip.id] {
                    cacheMisses += 1
                    lookupStats.fallbackHits += 1
                    texture = fallback
                    if notableEvents.count < 3 {
                        notableEvents.append("fallback clip=\(clip.id.uuidString.prefix(8)) src=\(sourceTime.formatted(.number.precision(.fractionLength(3))))s")
                    }
                    #if DEBUG
                    if isScrubbing {
                        Self.logger.debug(
                            "scrub render fallback clip=\(clip.id.uuidString, privacy: .public) time=\(self.currentTime, format: .fixed(precision: 3))s src=\(sourceTime, format: .fixed(precision: 3))s cache=\(self.frameCache.count)"
                        )
                    }
                    #endif
                } else {
                    cacheMisses += 1
                    lookupStats.misses += 1
                    texture = nil
                    if notableEvents.count < 3 {
                        notableEvents.append("miss clip=\(clip.id.uuidString.prefix(8)) src=\(sourceTime.formatted(.number.precision(.fractionLength(3))))s")
                    }
                }

                guard let texture else { continue }

                lastRenderedTextures[clip.id] = texture

                let sourceSize = CGSize(width: texture.width, height: texture.height)
                let transform = Self.buildTransformMatrix(
                    sourceSize: sourceSize,
                    outputSize: outputSize,
                    transform: clip.transform
                )
                let uniforms = ColorAdjustmentsUniforms(
                    exposure: clip.colorAdjustments.exposure,
                    contrast: clip.colorAdjustments.contrast,
                    saturation: clip.colorAdjustments.saturation,
                    highlights: clip.colorAdjustments.highlights,
                    shadows: clip.colorAdjustments.shadows,
                    opacity: clip.opacity
                )
                layers.append(CompositorPipeline.Layer(texture: texture, transform: transform, colorAdjustments: uniforms))
            }
        }

        var captionLayers: [CompositorPipeline.CaptionLayer] = []
        let displayScale = CGFloat(view.contentScaleFactor)
        for caption in timeline.captions where currentTime >= caption.startTime && currentTime <= caption.endTime {
            if let tex = captionRenderer.texture(for: caption, outputSize: outputSize, displayScale: displayScale),
               let texSize = captionRenderer.textureSize(for: caption.id) {
                let transform = captionRenderer.buildTransform(
                    caption: caption,
                    captionTextureSize: texSize,
                    outputSize: outputSize
                )
                captionLayers.append(CompositorPipeline.CaptionLayer(texture: tex, transform: transform, opacity: caption.opacity))
            }
        }

        compositor.composite(
            layers: layers,
            captions: captionLayers,
            into: drawable.texture,
            commandBuffer: commandBuffer
        )

        commandBuffer.present(drawable)
        commandBuffer.commit()

        let frameEnd = CACurrentMediaTime()
        let total = cacheHits + cacheMisses
        metrics.frameLatencyMs = (frameEnd - frameStart) * 1000
        metrics.cacheHitRatio = total > 0 ? Double(cacheHits) / Double(total) : 1.0
        metrics.cachedFrameCount = frameCache.count
        metrics.totalFramesRendered += 1
        if cacheMisses > 0 { metrics.droppedFrameCount += 1 }

        if cacheMisses > 0 && isPlaying && !isPrefetchActive.value {
            let now = CACurrentMediaTime()
            if now - lastMissPrefetchTime >= 0.5 {
                lastMissPrefetchTime = now
                triggerPrefetch(intent: .playback)
            }
        }

        logCacheLookupSummary(
            stats: lookupStats,
            currentTime: currentTime,
            cacheCount: frameCache.count,
            notableEvents: notableEvents
        )
    }

    private func logCacheLookupSummary(
        stats: CacheLookupStats,
        currentTime: Double,
        cacheCount: Int,
        notableEvents: [String]
    ) {
        let now = CACurrentMediaTime()
        let hasAnomaly = stats.fallbackHits > 0 || stats.misses > 0
        guard hasAnomaly || !notableEvents.isEmpty else { return }
        guard now - lastCacheLookupLogTime >= 0.5 else { return }
        lastCacheLookupLogTime = now

        #if DEBUG
        let events = notableEvents.isEmpty ? "none" : notableEvents.joined(separator: " | ")
        Self.logger.debug(
            "lookup t=\(currentTime, format: .fixed(precision: 3))s exact=\(stats.exactHits) nearest=\(stats.nearestHits) fallback=\(stats.fallbackHits) miss=\(stats.misses) cache=\(cacheCount) events=\(events, privacy: .public)"
        )
        #endif
    }

    private func logPrefetchStart(generation: Int, intent: RenderIntent, planCount: Int, requestCount: Int) {
        #if DEBUG
        let intentText: String = {
            switch intent {
            case .playback:
                return "playback"
            case .scrub(let velocity):
                return "scrub(v=\(velocity.formatted(.number.precision(.fractionLength(2)))))"
            }
        }()
        Self.logger.debug(
            "prefetch start gen=\(generation) intent=\(intentText, privacy: .public) planned=\(planCount) to_decode=\(requestCount)"
        )
        #endif
    }

    private func logPrefetchFinish(generation: Int, requested: Int, inserted: Int) {
        #if DEBUG
        if requested == 0 || inserted < requested {
            Self.logger.debug("prefetch done gen=\(generation) requested=\(requested) inserted=\(inserted)")
        }
        #endif
    }

    private func logDecodeFailure(error: Error, request: FrameScheduler.FrameRequest) {
        #if DEBUG
        let nsError = error as NSError
        Self.logger.error(
            "decode failed clip=\(request.clipID.uuidString, privacy: .public) file=\(request.assetURL.lastPathComponent, privacy: .public) src=\(request.sourceTime, format: .fixed(precision: 3))s domain=\(nsError.domain, privacy: .public) code=\(nsError.code)"
        )
        #endif
    }

    // MARK: - Transform Matrix

    static func buildTransformMatrix(
        sourceSize: CGSize,
        outputSize: CGSize,
        transform: RenderTransformInput
    ) -> matrix_float4x4 {
        let sourceAspect = Float(sourceSize.width / sourceSize.height)
        let outputAspect = Float(outputSize.width / outputSize.height)

        var scaleX: Float = 1
        var scaleY: Float = 1

        if sourceAspect > outputAspect {
            scaleY = outputAspect / sourceAspect
        } else {
            scaleX = sourceAspect / outputAspect
        }

        scaleX *= transform.scale.x
        scaleY *= transform.scale.y

        let S = matrix_float4x4.scale(x: scaleX, y: scaleY, z: 1)
        let R = matrix_float4x4.rotationZ(angle: transform.rotation)

        let ax = (transform.anchor.x - 0.5) * 2.0 * scaleX
        let ay = -(transform.anchor.y - 0.5) * 2.0 * scaleY
        let T1 = matrix_float4x4.translation(x: -ax, y: -ay, z: 0)
        let T2 = matrix_float4x4.translation(x: ax, y: ay, z: 0)

        let posX = transform.position.x * 2.0
        let posY = -transform.position.y * 2.0
        let T_pos = matrix_float4x4.translation(x: posX, y: posY, z: 0)

        return T_pos * T2 * R * T1 * S
    }
}

// MARK: - MTKViewDelegate

extension RenderEngine: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        requestRedraw()
    }

    func draw(in view: MTKView) {
        if isPlaying {
            let now = CACurrentMediaTime()
            let delta = lastDrawTime > 0 ? now - lastDrawTime : 0
            lastDrawTime = now
            currentTime = min(currentTime + delta, timeline.duration)

            if currentTime >= timeline.duration {
                currentTime = timeline.duration
                isPlaying = false
                setDrawingMode(continuous: false)
                onPlaybackStateChanged?(false)
            }

            onTimeChanged?(currentTime)
            needsRedraw = true

            if now - lastPrefetchTime > 0.3 {
                lastPrefetchTime = now
                triggerPrefetch(intent: .playback)
            }
        }

        guard needsRedraw || isPlaying else { return }
        needsRedraw = false

        renderCurrentFrame(in: view)

        let now = CACurrentMediaTime()
        if now - lastMetricsBroadcast > 0.1 {
            lastMetricsBroadcast = now
            onMetricsUpdated?(metrics)
        }
    }
}

// MARK: - Thread-safe set for in-flight tracking

final class LockedSet<Element: Hashable>: @unchecked Sendable {
    private var storage = Set<Element>()
    private let lock = NSLock()

    func insert(_ element: Element) {
        lock.lock()
        storage.insert(element)
        lock.unlock()
    }

    func remove(_ element: Element) {
        lock.lock()
        storage.remove(element)
        lock.unlock()
    }

    func contains(_ element: Element) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage.contains(element)
    }

    func removeAll() {
        lock.lock()
        storage.removeAll()
        lock.unlock()
    }
}

final class LockedValue<Value>: @unchecked Sendable {
    private var valueStorage: Value
    private let lock = NSLock()

    init(_ initialValue: Value) {
        self.valueStorage = initialValue
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return valueStorage
    }

    @discardableResult
    func modify<Result>(_ update: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return update(&valueStorage)
    }
}
