//
//  EditorViewModel.swift
//  BleepKit
//

import AVFAudio
import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation
import Observation
import OSLog
import QuartzCore

/// Drives editing of one project: transcription (re-extracting audio when
/// needed, running the engine, caching tokens), profanity detection, per-word
/// censor overrides, severity-tier settings, and the censored preview
/// (composition, playback transport, and preview layer trees).
@MainActor
@Observable
final class EditorViewModel {
    /// The transcription flow's UI state.
    enum TranscriptionState {
        /// Nothing running and no cached transcript (or a cancelled run).
        case idle
        case working(step: String)
        /// Tokens are available (freshly transcribed or loaded from cache).
        case ready([WordToken])
        /// The user declined speech-recognition permission.
        case permissionDenied
        case failed(message: String)
    }

    private(set) var transcriptionState: TranscriptionState = .idle
    /// Name of the engine that produced the current tokens — the editor's
    /// debug label. "cached" when tokens were loaded from the record.
    private(set) var engineIdentifier: String?
    /// Set when the device locale isn't English: captions still work, but
    /// the bundled profanity vocabulary is English-only.
    private(set) var localeNotice: String?

    let project: Project

    // MARK: Playback state

    /// The preview player; owned for the editor's lifetime.
    let player = AVPlayer()
    /// Playhead position, updated 30×/second while the preview plays.
    private(set) var currentSeconds: Double = 0
    private(set) var isPlaying = false
    /// Bumped whenever the preview layer trees must be rebuilt.
    private(set) var previewRevision = 0
    private(set) var previewReady = false
    private(set) var previewError: String?
    private(set) var assetDurationSeconds: Double = 0
    /// The output raster — the source's oriented native size, untouched.
    /// Defaults to 9:16 until the first composition builds.
    private(set) var renderSize = CompositionBuilder.renderSize

    private let transcriptionService: TranscriptionService
    private let audioExtractor: AudioExtractor
    private let projectStore: ProjectStore
    private let tempFiles: TempFileManager
    private let profanityMatcher: ProfanityMatcher
    private let audioCensorBuilder: AudioCensorBuilder
    private var transcriptionTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Holds the player and its periodic time-observer token together so
    /// the (nonisolated) deinit can tear them down without touching
    /// main-actor state. Created once in init, invalidated in deinit.
    private final class PlayerObservation: @unchecked Sendable {
        private let player: AVPlayer
        private let token: Any

        init(player: AVPlayer, token: Any) {
            self.player = player
            self.token = token
        }

        func invalidate() {
            player.removeTimeObserver(token)
        }
    }
    private let playerObservation: PlayerObservation

    /// Indirection between the periodic time observer and the view model:
    /// the observer closure is created during init (before `self` is fully
    /// initialized), so it captures this relay instead of `self`.
    private final class PlayheadRelay: @unchecked Sendable {
        /// Set once after init completes; only touched on the main actor.
        var handler: (@MainActor (Double) -> Void)?
    }
    private var cachedOverlayImage: (identifier: String, image: CGImage)?

    init(project: Project, environment: AppEnvironment) {
        self.project = project
        transcriptionService = environment.transcriptionService
        audioExtractor = environment.audioExtractor
        projectStore = environment.projectStore
        tempFiles = environment.tempFiles
        profanityMatcher = environment.profanityMatcher
        audioCensorBuilder = environment.audioCensorBuilder

        let relay = PlayheadRelay()
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { time in
            MainActor.assumeIsolated {
                relay.handler?(time.seconds)
            }
        }
        playerObservation = PlayerObservation(player: player, token: token)
        relay.handler = { [weak self] seconds in
            self?.playheadMoved(to: seconds)
        }
    }

    deinit {
        playerObservation.invalidate()
    }

    // MARK: Transcription

    /// Shows the cached transcript if one exists — reopening a project never
    /// re-transcribes — and otherwise starts a fresh transcription.
    func loadOrTranscribe() {
        if Locale.current.language.languageCode?.identifier != "en" {
            localeNotice = "Profanity detection is English-only. Captions still work in your language; flag words manually from the transcript."
        }
        let cached = project.tokens
        if !cached.isEmpty {
            engineIdentifier = "cached"
            transcriptionState = .ready(cached)
            refreshPreview()
            return
        }
        transcribe()
    }

    /// Starts (or restarts) a transcription run.
    func transcribe() {
        transcriptionTask?.cancel()
        transcriptionState = .working(step: "Extracting audio…")
        transcriptionTask = Task {
            await self.performTranscription()
        }
    }

    /// Cancels the in-flight run; the task tears down the engine and deletes
    /// its scratch audio.
    func cancelTranscription() {
        transcriptionTask?.cancel()
    }

    // MARK: Profanity controls

    /// The severity tiers currently counting as hits. Slur is always
    /// included and cannot be disabled.
    var enabledSeverities: Set<ProfanitySeverity> {
        var severities = Set(project.enabledSeverities.compactMap(ProfanitySeverity.init(rawValue:)))
        severities.insert(.slur)
        return severities
    }

    /// Whether a (toggleable) severity tier is enabled.
    func isSeverityEnabled(_ severity: ProfanitySeverity) -> Bool {
        enabledSeverities.contains(severity)
    }

    /// Enables or disables a severity tier and re-runs detection. The slur
    /// tier is non-toggleable and requests to change it are ignored.
    func setSeverity(_ severity: ProfanitySeverity, enabled: Bool) {
        guard severity != .slur else { return }
        var severities = enabledSeverities
        if enabled {
            severities.insert(severity)
        } else {
            severities.remove(severity)
        }
        project.enabledSeverities = severities.map(\.rawValue).sorted()
        reannotate()
    }

    /// Sets a per-word override: true forces censoring, false forces
    /// allowing, nil returns the word to automatic detection. Persists
    /// immediately.
    func setOverride(forTokenID tokenID: UUID, to value: Bool?) {
        var tokens = project.tokens
        guard let index = tokens.firstIndex(where: { $0.id == tokenID }) else { return }
        tokens[index].userOverride = value
        persist(tokens)
    }

    /// Re-runs detection over the current tokens (after a severity change),
    /// leaving user overrides untouched.
    private func reannotate() {
        let annotated = profanityMatcher.annotate(
            tokens: project.tokens,
            enabledSeverities: enabledSeverities
        )
        persist(annotated)
    }

    private func persist(_ tokens: [WordToken]) {
        project.tokens = tokens
        do {
            try projectStore.save()
        } catch {
            Logger.storage.error("Failed to save tokens: \(error.localizedDescription)")
        }
        if case .ready = transcriptionState {
            transcriptionState = .ready(tokens)
        }
        // Overrides and severity changes alter the censor ranges, so the
        // audio mix and layer trees must both refresh.
        refreshPreview()
    }

    // MARK: Preview

    /// The merged censor ranges for the current tokens and settings — the
    /// single source of truth shared by audio, captions, and overlay.
    var censorRanges: [CensorRange] {
        CensorRangeCalculator.censorRanges(
            tokens: project.tokens,
            padding: project.beepSettings.paddingSeconds,
            assetDuration: .projectSeconds(project.durationSeconds)
        )
    }

    /// Rebuilds the censored composition and swaps it into the player.
    func refreshPreview() {
        previewTask?.cancel()
        previewReady = false
        previewError = nil
        previewTask = Task {
            await self.buildPreview()
        }
    }

    private func buildPreview() async {
        do {
            let sourceURL = try ProjectStore.sourceURL(forFileName: project.sourceFileName)
            let built = try await CompositionBuilder.makeCensoredComposition(
                sourceURL: sourceURL,
                ranges: censorRanges,
                beepSettings: project.beepSettings,
                audioCensorBuilder: audioCensorBuilder
            )
            try Task.checkCancellation()
            let item = AVPlayerItem(asset: built.composition)
            item.videoComposition = built.videoComposition
            // Applying the mix to the item is what makes beeps audible in
            // preview.
            item.audioMix = built.audioMix
            let resumeSeconds = currentSeconds
            assetDurationSeconds = built.durationSeconds
            renderSize = built.renderSize
            player.replaceCurrentItem(with: item)
            if resumeSeconds > 0.01 {
                await player.seek(
                    to: .projectSeconds(min(resumeSeconds, built.durationSeconds)),
                    toleranceBefore: .zero,
                    toleranceAfter: .zero
                )
            }
            previewRevision += 1
            previewReady = true
        } catch is CancellationError {
            // A newer refresh superseded this one.
        } catch {
            Logger.video.error("Preview build failed: \(error.localizedDescription)")
            previewError = error.localizedDescription
        }
    }

    /// Builds the preview copies of the overlay and caption trees, sized to
    /// the player's video rect. The same builders serve export at render
    /// size — only the coordinate scale differs.
    func buildPreviewLayers(targetSize: CGSize, contentsScale: CGFloat) -> [CALayer] {
        guard assetDurationSeconds > 0, targetSize.width > 1 else { return [] }
        var layers: [CALayer] = []

        let captionBuilder = CaptionLayerBuilder(configuration: .init(
            style: project.captionStyle,
            censorStyle: project.censorStyle,
            censorImage: censorStyleImage(),
            targetSize: targetSize,
            contentsScale: contentsScale
        ))

        if project.overlayEnabled, let overlayImage = resolvedOverlayImage() {
            let ranges = censorRanges
            var captionTargets: [CGRect] = []
            if project.overlayFollowsCaption {
                let frames = captionBuilder.censoredWordFrames(tokens: project.tokens)
                captionTargets = ranges.map { range in
                    range.sourceTokenIDs.compactMap { frames[$0] }.first ?? .null
                }
            }
            let overlayBuilder = OverlayLayerBuilder(configuration: .init(
                image: overlayImage,
                normalizedCenter: CGPoint(x: project.overlayPositionX, y: project.overlayPositionY),
                targetSize: targetSize,
                contentsScale: contentsScale,
                followsCaption: project.overlayFollowsCaption,
                captionTargets: captionTargets
            ))
            layers.append(overlayBuilder.buildLayer(
                ranges: ranges,
                assetDurationSeconds: assetDurationSeconds
            ))
        }

        layers.append(captionBuilder.buildLayer(
            tokens: project.tokens,
            assetDurationSeconds: assetDurationSeconds
        ))
        return layers
    }

    /// Resolves the overlay sticker identifier ("emoji:🤬") to a bitmap,
    /// cached per identifier.
    private func resolvedOverlayImage() -> CGImage? {
        guard let identifier = project.overlayAssetIdentifier else { return nil }
        if let cached = cachedOverlayImage, cached.identifier == identifier {
            return cached.image
        }
        guard identifier.hasPrefix("emoji:") else { return nil }
        let emoji = String(identifier.dropFirst("emoji:".count))
        guard let image = StickerRenderer.emojiImage(emoji) else { return nil }
        cachedOverlayImage = (identifier, image)
        return image
    }

    /// Image for the caption `.image` censor treatment (same sticker set).
    private func censorStyleImage() -> CGImage? {
        if case .image(let identifier) = project.censorStyle,
           identifier.hasPrefix("emoji:") {
            return StickerRenderer.emojiImage(String(identifier.dropFirst("emoji:".count)))
        }
        return nil
    }

    // MARK: Overlay settings

    func setOverlayEnabled(_ enabled: Bool) {
        project.overlayEnabled = enabled
        if enabled, project.overlayAssetIdentifier == nil {
            project.overlayAssetIdentifier = "emoji:\(StickerRenderer.bundledEmoji[0])"
        }
        saveProjectAndRebuildLayers()
    }

    func setOverlaySticker(_ emoji: String) {
        project.overlayAssetIdentifier = "emoji:\(emoji)"
        saveProjectAndRebuildLayers()
    }

    func setOverlayFollowsCaption(_ follows: Bool) {
        project.overlayFollowsCaption = follows
        saveProjectAndRebuildLayers()
    }

    /// Pins the overlay at a normalized position (drag-to-position).
    func setOverlayPosition(x: Double, y: Double) {
        project.overlayPositionX = min(max(x, 0), 1)
        project.overlayPositionY = min(max(y, 0), 1)
        saveProjectAndRebuildLayers()
    }

    func setCensorStyle(_ style: CensorStyle) {
        project.censorStyle = style
        saveProjectAndRebuildLayers()
    }

    /// Persists a caption-style change and rebuilds the layer trees.
    func setCaptionStyle(_ style: CaptionStyle) {
        project.captionStyle = style
        saveProjectAndRebuildLayers()
    }

    /// Persists a beep-settings change. Padding and ramp alter the censor
    /// ranges and audio mix, so the whole preview composition rebuilds.
    func setBeepSettings(_ settings: BeepSettings) {
        project.beepSettings = settings
        do {
            try projectStore.save()
        } catch {
            Logger.storage.error("Failed to save beep settings: \(error.localizedDescription)")
        }
        refreshPreview()
    }

    /// Pauses playback (used when the app leaves the foreground).
    func pausePlayback() {
        player.pause()
        isPlaying = false
    }

    /// Persists a style-only change and rebuilds the layer trees. The
    /// composition and audio mix are untouched — censor timing didn't
    /// change.
    private func saveProjectAndRebuildLayers() {
        project.updatedAt = .now
        do {
            try projectStore.save()
        } catch {
            Logger.storage.error("Failed to save project: \(error.localizedDescription)")
        }
        previewRevision += 1
    }

    // MARK: Transport

    private func playheadMoved(to seconds: Double) {
        currentSeconds = seconds
        if isPlaying, player.timeControlStatus != .playing {
            isPlaying = false
        }
    }

    func togglePlayback() {
        if player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback)
            try session.setActive(true)
        } catch {
            Logger.audio.error("Audio session activation failed: \(error.localizedDescription)")
        }
        // Restart from the top when the playhead sits at the end.
        if assetDurationSeconds > 0, currentSeconds >= assetDurationSeconds - 0.05 {
            player.seek(to: .zero, toleranceBefore: .zero, toleranceAfter: .zero)
        }
        player.play()
        isPlaying = true
    }

    /// Scrubs to a position, pausing playback.
    func scrub(to seconds: Double) {
        player.pause()
        isPlaying = false
        currentSeconds = seconds
        player.seek(
            to: .projectSeconds(seconds),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    /// Steps forward or backward by whole frames.
    func stepFrames(_ count: Int) {
        player.pause()
        isPlaying = false
        player.currentItem?.step(byCount: count)
    }

    /// Seeks the preview to a token's start (word-list row tap).
    func seekToToken(_ token: WordToken) {
        scrub(to: token.startSeconds)
    }

    // MARK: Transcription flow

    private func performTranscription() async {
        var scratchAudioURL: URL?
        defer {
            if let scratchAudioURL {
                tempFiles.remove(scratchAudioURL)
            }
        }
        do {
            let sourceURL = try ProjectStore.sourceURL(forFileName: project.sourceFileName)
            guard let audioURL = try await audioExtractor.extractAudio(from: sourceURL) else {
                transcriptionState = .failed(message: "This video has no audio track, so there's nothing to transcribe.")
                return
            }
            scratchAudioURL = audioURL
            try Task.checkCancellation()

            transcriptionState = .working(step: "Transcribing…")
            let transcript = try await transcriptionService.transcribe(
                audioURL: audioURL,
                locale: .current
            ) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self, case .working = self.transcriptionState else { return }
                    self.transcriptionState = .working(step: event.userDescription)
                }
            }
            try Task.checkCancellation()

            for token in transcript.tokens {
                Logger.transcription.info("token \"\(token.text, privacy: .public)\" start=\(token.startSeconds, format: .fixed(precision: 3)) duration=\(token.durationSeconds, format: .fixed(precision: 3)) confidence=\(token.confidence, format: .fixed(precision: 2))")
            }
            Logger.transcription.info("Transcribed \(transcript.tokens.count) tokens with \(transcript.engineIdentifier, privacy: .public)")

            var annotated = profanityMatcher.annotate(
                tokens: transcript.tokens,
                enabledSeverities: enabledSeverities
            )
            annotated = Self.carryingOverrides(from: project.tokens, into: annotated)
            let flagged = annotated.filter(\.detectedProfane).count
            Logger.profanity.info("Detected \(flagged) profane tokens of \(annotated.count)")

            project.tokens = annotated
            try projectStore.save()
            engineIdentifier = transcript.engineIdentifier
            transcriptionState = .ready(annotated)
            refreshPreview()
        } catch is CancellationError {
            Logger.transcription.notice("Transcription cancelled")
            transcriptionState = .idle
        } catch let error as TranscriptionError {
            if case .notAuthorized = error {
                transcriptionState = .permissionDenied
            } else {
                Logger.transcription.error("Transcription failed: \(error.localizedDescription)")
                transcriptionState = .failed(message: error.localizedDescription)
            }
        } catch {
            Logger.transcription.error("Transcription failed: \(error.localizedDescription)")
            transcriptionState = .failed(message: error.localizedDescription)
        }
    }

    /// Re-applies user overrides from a previous transcript to a fresh one,
    /// matching by normalized text within half a second — so overrides
    /// survive re-transcription.
    private static func carryingOverrides(from previous: [WordToken], into fresh: [WordToken]) -> [WordToken] {
        let overridden = previous.filter { $0.userOverride != nil }
        guard !overridden.isEmpty else { return fresh }
        var result = fresh
        for old in overridden {
            let oldText = TextNormalizer.normalize(old.text)
            if let index = result.firstIndex(where: { candidate in
                candidate.userOverride == nil
                    && abs(candidate.startSeconds - old.startSeconds) < 0.5
                    && TextNormalizer.normalize(candidate.text) == oldText
            }) {
                result[index].userOverride = old.userOverride
            }
        }
        return result
    }
}
