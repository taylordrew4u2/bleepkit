# BleepKit — Known Failure Modes and Mitigations

Each failure mode is mitigated in a specific, named place in the code.

## 1. Speech timestamps drift; the curse leaks past the beep

**Mitigation:** `CensorRangeCalculator.censorRanges(tokens:padding:assetDuration:)`
(`Services/Audio/CensorRangeCalculator.swift`) expands every censored token
by ±`BeepSettings.paddingSeconds` (default 60 ms, user-adjustable 0–200 ms in
`CensorStyleView`) before clamping and merging.

## 2. Recognizer returns profanity pre-masked as "f***"

**Mitigation:** `ProfanityMatcher.isMasked(_:)`
(`Services/Profanity/ProfanityMatcher.swift`) treats any token matching
`\w?\*{2,}\w?` as a positive hit regardless of severity tier; the mask's
timing remains valid. `TextNormalizer.collapseRuns` deliberately exempts
asterisks so the mask survives normalization, and partially masked words
("f*ck") match via single-character wildcards. Verified on-device: the iOS 26
engine returned "damn" unmasked, so both the literal and masked paths are
exercised.

## 3. Adjacent curses produce stacked, clipping beeps

**Mitigation:** `CensorRangeCalculator` merges overlapping and adjacent
padded ranges (`next.start <= current.end`) before `AudioCensorBuilder`
inserts one beep per merged range. Verified spectrally on-device: two
back-to-back words produced one continuous 1 kHz tone with peak amplitude
0.42 (no clipping).

## 4. `AVVideoCompositionCoreAnimationTool` does not render in AVPlayer

**Mitigation:** `PlayerContainerView.rebuildSyncLayer()`
(`Views/PlayerView.swift`) attaches a separate `AVSynchronizedLayer` tree for
preview, built by the same `CaptionLayerBuilder`/`OverlayLayerBuilder`
instances used for export (`EditorViewModel.buildPreviewLayers` and
`ExportViewModel.run` both call the same method), differing only in target
size.

## 5. Animations with `beginTime = 0` are silently dropped on export

**Mitigation:** every animation in the project is created by
`CaptionLayerBuilder.discreteAnimation`/`discreteIntervalsAnimation` and
`OverlayLayerBuilder.steppedPositionAnimation`, which all set
`AVCoreAnimationBeginTimeAtZero`, `isRemovedOnCompletion = false`, and
`fillMode = .both`. `ExportPipeline.assertAnimationsExportSafe` re-checks the
whole tree in DEBUG builds before every export.

## 6. Export session reused after completion crashes

**Mitigation:** `ExportPipeline.export` constructs a fresh
`AVAssetExportSession` on every call; `ExportViewModel.startExport` goes
through the pipeline for every attempt, including retries.

## 7. Progress observation started after `export(to:as:)` yields nothing

**Mitigation:** `ExportPipeline.export` starts the
`session.states(updateInterval:)` consumption task strictly before awaiting
`export(to:as:)`.

## 8. Core Animation's bottom-left origin mirrors caption Y positions

**Mitigation:** all builders compute geometry in one top-left coordinate
space; `ExportPipeline.export` sets `parentLayer.isGeometryFlipped = true` so
the identical math holds under the export tool's bottom-left origin — one
geometry code path instead of two that can drift. Verified pixel-level
on-device: captions land in the bottom band of exported frames, never the
top.

## 9. Substring matching censors "class" and "assassin"

**Mitigation:** `ProfanityMatcher` matches whole normalized tokens only, and
consults the `profanity_en.json` allowlist before every lookup, including
after each inflection-stripping step ("passes" strips to allowlisted "pass"
and stops). Covered by `bleepkitTests/ProfanityMatcherTests.swift`.

## 10. Absolute sandbox paths break on relaunch

**Mitigation:** `Project.sourceFileName` stores only a file name;
`ProjectStore.sourceURL(forFileName:)`
(`Services/Storage/ProjectStore.swift`) resolves it against the current
container's `Documents/sources` on every use.

## 11. Blurry burned-in text

**Mitigation:** caption words are pre-rendered bitmaps rasterized at
`Configuration.contentsScale` (`UIScreen` scale for export) by
`CaptionLayerBuilder.renderWordImage`, and every layer sets
`contentsScale` explicitly.

## 12. iOS 26 language model not downloaded on first run

**Mitigation:** `SpeechAnalyzerEngine.transcribe` requests installation via
`AssetInventory.assetInstallationRequest(supporting:)` with a "Preparing
language model…" UI state; on failure `TranscriptionService.transcribe`
falls back to `LegacySpeechEngine` so first-run-without-network still works.

## 13. (Discovered during development) `CATextLayer` renders nothing inside `AVVideoCompositionCoreAnimationTool` on iOS 26

Found by pixel-level export verification: plain layers rendered, text layers
did not — flipped or not, animated or static.

**Mitigation:** `CaptionLayerBuilder.addWordLayers` renders every word to a
bitmap (attributed-string drawing, stroke+fill in one pass) shown via plain
`CALayer.contents`; the karaoke highlight is an opacity crossfade between the
fill-color and active-color bitmaps. No `CATextLayer` exists anywhere in the
export or preview trees.
