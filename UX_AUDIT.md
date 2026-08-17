# BleepKit — Design & UX Audit

Scope: the full SwiftUI layer (`App/`, `Views/`, `Views/Components/`, `ViewModels/`), read on 2026-08-15. No code was modified. Severity scale: **blocker** (user cannot proceed or loses work), **friction** (user succeeds but is confused, slowed, or surprised), **polish** (noticeable but harmless).

---

## 1. First-run path

**Cold launch → censored video saved to Photos takes 7 taps on first run (5 taps on later runs).**

| # | Tap | Screen |
|---|-----|--------|
| 1 | "Choose from Photos" | Import idle list |
| 2 | Select a video (picker auto-dismisses) | Photos picker |
| 3 | "Done" | "Imported" details screen |
| 4 | Tap the new project row | Import idle list |
| 5 | "Allow" on the speech-recognition alert (first run only) | System alert |
| — | Transcription and preview run automatically | Editor |
| 6 | Export button | Editor toolbar |
| 7 | "Allow" on the Photos add-only alert (first run only) | System alert |

### Findings

**1.1 — `bleepkit/ImportView.swift:133-165` (SourceDetailsView)**
After importing, the user lands on a dead-end "Imported" screen whose only exit, "Done", sends them *back to the start*; they must then re-find their video in the Projects list and tap it to actually begin editing. Two of the seven first-run taps exist only to escape this screen.
Severity: **friction** (the single largest cost in the funnel).
Fix: navigate directly into `EditorView` when an import succeeds, and demote the metadata screen to an optional info button.

**1.2 — `bleepkit/ImportView.swift:139-156` (SourceDetailsView)**
The screen between the user and their goal is full of developer-facing data — "Oriented size", "Frame rate", "Stored as" (a UUID filename), extracted-audio byte size, and a "Play Extracted Audio" verification button — none of which a first-time user can act on.
Severity: **polish**.
Fix: if the screen survives, reduce it to title, duration, and a prominent "Start Editing" action.

**1.3 — `bleepkit/EditorView.swift:60-67`**
The Export button is disabled while the preview builds, with no explanation; a first-run user who taps it during the (potentially long) transcription gets no feedback about why nothing happens.
Severity: **polish**.
Fix: pair the disabled state with a caption or replace the icon with a small spinner while `previewReady` is false.

---

## 2. Waits without progress, and silent failures

**2.1 — `bleepkit/EditorView.swift:90-104` + `bleepkit/ViewModels/EditorViewModel.swift:471-531`**
If the initial transcription is **cancelled, fails, or speech permission is denied**, the editor shows a bare, unlabeled spinner forever: the `ZStack` only handles `.working` and `previewError`, and `refreshPreview()` is never called on those paths, so `previewReady` stays false. Transport and Export stay disabled; the failure message exists only if the user happens to navigate into the Transcript screen.
Severity: **blocker** — the app's main screen becomes a permanent spinner with no message and no way out.
Fix: render `.failed`, `.permissionDenied`, and `.idle` transcription states in the editor's preview area with the same retry/Settings actions `WordListView` already has.

**2.2 — `bleepkit/App/RootView.swift:32-37`**
Opening a movie in BleepKit from another app on a **cold launch** can silently do nothing: `onOpenURL` calls `importViewModel?.importFile`, and the view model is created in `.task`, so a URL arriving first is dropped without any feedback.
Severity: **blocker** for the open-in entry path.
Fix: buffer the incoming URL in `@State` and replay it once the view model exists.

**2.3 — `bleepkit/ImportView.swift:106-114`**
Swipe-deleting a project can fail silently — the error goes only to the log, so the user sees the row snap back (or persist after relaunch) with no explanation.
Severity: **friction**.
Fix: surface the delete failure in an alert.

**2.4 — `bleepkit/ViewModels/EditorViewModel.swift:205-218, 386-394, 405-413`**
Every editor change (overrides, styles, beep settings) is persisted with the error only logged; if the save fails, the user's edits silently vanish on next launch while the current session looks fine.
Severity: **friction**.
Fix: propagate a save failure into a visible, non-modal warning banner in the editor.

**2.5 — `bleepkit/ImportView.swift:173-214` (AudioPlaybackRow)**
"Play Extracted Audio" gives no feedback if playback fails, and the button never resets when the clip finishes — it reads "Stop" indefinitely, so the user can't tell whether anything played.
Severity: **polish**.
Fix: observe item end/failure and reset the button state (or report the failure).

**2.6 — `bleepkit/Views/CensorStyleView.swift:43-79` + `bleepkit/ViewModels/EditorViewModel.swift:386-394`**
Every tick of the four beep sliders rebuilds the entire preview composition, so dragging a slider makes the preview repeatedly flash to a spinner and drop the frame the user was inspecting — the wait is unexplained and repeats continuously mid-drag.
Severity: **friction**.
Fix: debounce `refreshPreview()` until the slider drag ends.

---

## 3. Missing empty / error / loading states

The app is unusually good here — `LoadingStateView`, `ErrorStateView`, `EmptyStateView`, and `PermissionDeniedView` exist and every long operation has a cancel. The gaps:

**3.1 — `bleepkit/EditorView.swift:90-104`**
No editor-level state for transcription `.failed` / `.permissionDenied` / `.idle` (detailed as finding 2.1). This is the one genuinely missing error/empty state in the app.
Severity: **blocker** (same instance as 2.1).

**3.2 — `bleepkit/ViewModels/EditorViewModel.swift:127-139` + `bleepkit/Views/WordListView.swift:84-91`**
A non-English user gets **zero automatic censoring**, and the only explanation is a small gray footnote at the bottom of the Transcript list — nothing on the editor screen itself says why nothing was bleeped.
Severity: **friction**.
Fix: show the English-only notice prominently in the editor (banner or alert) the first time transcription completes with a non-English locale.

**3.3 — `bleepkit/ImportView.swift:64-71`**
The "No Projects Yet" empty state is a full-screen-styled `ContentUnavailableView` squeezed inside a `List` section under the import buttons, which renders as an oddly tall, centered cell rather than a real empty state.
Severity: **polish**.
Fix: use a plain footer-style text row for the in-list case, reserving `ContentUnavailableView` for full-screen use.

---

## 4. Destructive or irreversible actions without confirmation / undo

**4.1 — `bleepkit/ImportView.swift:81, 106-114`**
Swipe-to-delete a project **permanently deletes the imported source video and all edits** with no confirmation and no undo — one accidental swipe destroys everything the user made.
Severity: **blocker**.
Fix: add a confirmation dialog ("Delete project and its video?") to `onDelete`.

**4.2 — `bleepkit/ExportView.swift:28-34, 37`**
While an export is rendering, swipe-to-dismiss is correctly disabled, but the "Close" toolbar button still cancels the export and dismisses instantly — a stray tap silently throws away minutes of rendering with no "cancel export?" prompt.
Severity: **friction**.
Fix: when `isWorking`, make Close show a confirmation before cancelling.

**4.3 — `bleepkit/Views/WordListView.swift:103-105`**
"Re-transcribe" immediately discards the current transcript (overrides are best-effort re-matched, and any that don't match within 0.5 s are lost) with no confirmation.
Severity: **friction**.
Fix: confirm before re-transcribing when any user overrides exist.

---

## 5. HIG deviations

**5.1 — `bleepkit/EditorView.swift:183-186` → `bleepkit/Views/CaptionStyleView.swift`**
Caption appearance is edited on a **pushed full-screen form that hides the video**, so the user adjusts font size, colors, and position blind, then navigates back to see the result — the HIG pattern for editing an on-canvas element is an inspector/half-height sheet that keeps the content visible. The same applies to `CensorStyleView` (beep sliders can't be auditioned against the preview).
Severity: **friction** (the biggest HIG issue in the app).
Fix: present the style editors as medium-detent sheets over the editor so the preview stays visible and live.

**5.2 — `bleepkit/EditorView.swift:208-231` vs `bleepkit/Views/CensorStyleView.swift:20-34`**
The censor style is settable in two different places with different names ("Caption censor style" in the toolbar paintbrush menu vs "Treatment" in the Censoring screen), and the overlay sticker lives only in the toolbar menu while everything else censor-related lives in the Censoring screen — the user can't build a stable model of where settings live.
Severity: **friction**.
Fix: keep one canonical home (the Censoring screen) and remove the duplicate picker from the toolbar menu.

**5.3 — `bleepkit/EditorView.swift:88, 114-138`**
Positioning the overlay sticker is a **completely undiscoverable gesture**: nothing anywhere hints that tapping/dragging the video pins the sticker, the gesture silently does nothing unless two settings are in the right state, and there is no visible handle on the sticker itself. HIG: gestures need a visible affordance or an alternative control.
Severity: **friction**.
Fix: add an explicit "Position" affordance (e.g., a draggable handle on the sticker or an instruction overlay when overlay is enabled).

**5.4 — `bleepkit/EditorView.swift:177-197`**
The three main destinations (Transcript, Captions, Censoring) are `NavigationLink`s dressed as small bordered footnote buttons crowded under the transport controls — navigation is presented as actions, at the app's least prominent size, for its most important screens.
Severity: **polish**.
Fix: promote them to a standard toolbar/bottom-bar or a segmented control with clear prominence.

**5.5 — `bleepkit/ExportView.swift:38-44`**
The export sheet starts rendering the moment it appears, with no confirm step — combined with 4.2, presentation *is* commitment. Acceptable for a one-option export, but it removes any chance to review before spending the render.
Severity: **polish**.
Fix: either keep auto-start but make cancellation graceful (4.2), or open with a single "Export" confirm button.

No tab bar exists and none is needed for this single-flow app — no deviation there.

---

## 6. Accessibility

Overall strong: nearly every icon-only control has an `accessibilityLabel`, text uses Dynamic Type styles, and system components dominate. The gaps:

**6.1 — `bleepkit/EditorView.swift:151-173`**
The frame-step buttons are bare `title2`-sized SF Symbols (~22 pt glyphs) with no minimum frame — tap targets well under 44×44 pt on the app's most-used screen.
Severity: **friction**.
Fix: give each transport button a `.frame(minWidth: 44, minHeight: 44)` (and `.contentShape`).

**6.2 — `bleepkit/Views/WordListView.swift:181-191`**
The per-word override control is a lone ~20 pt `slider.horizontal.3` glyph at the trailing edge of each row — under 44×44 pt, and directly adjacent to the full-row seek button, so mis-taps seek instead of opening the menu.
Severity: **friction**.
Fix: pad the menu label to a 44×44 pt tappable frame.

**6.3 — `bleepkit/EditorView.swift:88, 114-138`**
Overlay positioning is drag-only with **no VoiceOver or Switch Control alternative** — a non-sighted user cannot move the sticker at all.
Severity: **friction**.
Fix: add an accessible alternative (e.g., X/Y sliders in the Censoring screen, or accessibility actions on the preview).

**6.4 — `bleepkit/EditorView.swift:90-99` + `bleepkit/Views/Components/StateViews.swift:19-21`**
The loading/error overlays sit on a `.black.opacity(0.6)` scrim, but `LoadingStateView`'s message uses the default primary color — **black text on a dark scrim in light mode**, failing contrast exactly when the user needs to read "Transcribing…".
Severity: **friction**.
Fix: force `.foregroundStyle(.white)` (or a `colorScheme(.dark)` environment) on content shown over the video scrim.

**6.5 — `bleepkit/EditorView.swift:163` and `bleepkit/ExportView.swift:108-110`**
The play/pause glyph (`size: 44`) and success checkmark (`size: 56`) are fixed-size fonts that ignore Dynamic Type; all other text scales correctly.
Severity: **polish**.
Fix: use scalable styles (e.g., `.font(.largeTitle)` with `@ScaledMetric`) instead of fixed point sizes.

**6.6 — `bleepkit/Views/Components/ScrubberView.swift:16-26`**
The timeline slider has a label ("Timeline") but no `accessibilityValue`, so VoiceOver announces a bare percentage instead of the current timecode shown visually.
Severity: **polish**.
Fix: add `.accessibilityValue(currentSeconds.timecodeString)`.

**6.7 — `bleepkit/Views/WordListView.swift:156-161`**
Censored words rely on system red text plus an icon — the icon saves it from being color-only, but small red-on-white body text sits at roughly the 4.5:1 contrast floor.
Severity: **polish**.
Fix: bold the censored word or use a filled background chip rather than red foreground text.

---

## 7. Visual inconsistency — values that should be shared tokens

**7.1 — `bleepkit/EditorView.swift:94, 99`**
`.black.opacity(0.6)` scrim is hardcoded twice in the same file; any future overlay will drift.
Severity: **polish**.
Fix: extract a single `overlayScrim` style used by all preview overlays.

**7.2 — `bleepkit/ExportView.swift:56-123`**
The export sheet mixes two visual languages: cancelled state uses `ContentUnavailableView`, success uses a hand-built VStack with a hardcoded `.green` 56 pt checkmark and different spacing — same sheet, two layouts.
Severity: **polish**.
Fix: render success with `ContentUnavailableView` too (or share one result-view component).

**7.3 — `bleepkit/ExportView.swift:118-121` vs `bleepkit/ExportView.swift:93-96`**
Button prominence is inverted: the happy path's "Share Video" is `.bordered` while the permission-denied path's identical button is `.borderedProminent`.
Severity: **polish**.
Fix: make the primary action `.borderedProminent` consistently.

**7.4 — spacing constants across `bleepkit/EditorView.swift:50, 143, 151, 177`, `bleepkit/ExportView.swift:68, 88, 107`, `bleepkit/Views/Components/StateViews.swift:16`**
Stack spacings (4/8/12/16/24/32) and paddings (`.horizontal, 32`, `.bottom, 8/24`) are ad-hoc per view with no shared scale.
Severity: **polish**.
Fix: define a small spacing enum (e.g., `.xs/.s/.m/.l`) and use it in new/edited layouts.

**7.5 — `bleepkit/Views/WordListView.swift:157-161`**
Semantic state colors (`Color.red` for censored, `.secondary` for allowed) are inlined at the point of use; the same "censored" red should come from one token so list, editor, and any future badges agree.
Severity: **polish**.
Fix: add a `Color.censored` (asset-catalog color) and reference it everywhere censored state is drawn.

---

## All findings ranked by user impact

| Rank | ID | Severity | One-line summary |
|------|----|----------|------------------|
| 1 | 2.1 / 3.1 | blocker | Editor shows a permanent unlabeled spinner if transcription fails, is cancelled, or permission is denied |
| 2 | 4.1 | blocker | Swipe-delete permanently destroys a project and its video with no confirmation or undo |
| 3 | 2.2 | blocker | Videos opened from other apps on cold launch are silently dropped |
| 4 | 1.1 | friction | Import dead-ends on a details screen; user must backtrack and re-find their project to start editing |
| 5 | 5.1 | friction | Caption/censor style editing hides the video, so all visual tuning is done blind |
| 6 | 4.2 | friction | Close button silently cancels an in-progress export with one tap |
| 7 | 5.3 / 6.3 | friction | Sticker positioning is an undiscoverable drag with no accessible alternative |
| 8 | 3.2 | friction | Non-English users get no censoring and the explanation is a buried footnote |
| 9 | 2.6 | friction | Beep sliders rebuild the whole preview per tick, flashing spinners mid-drag |
| 10 | 6.4 | friction | Loading text over the video scrim is unreadable in light mode |
| 11 | 6.1 | friction | Frame-step buttons are far below the 44×44 pt tap-target minimum |
| 12 | 6.2 | friction | Per-word override glyph is a tiny target beside a full-row seek button |
| 13 | 2.4 | friction | Failed saves lose edits silently on next launch |
| 14 | 2.3 | friction | Failed project deletion gives no feedback |
| 15 | 4.3 | friction | Re-transcribe discards the transcript (and can drop overrides) without confirming |
| 16 | 5.2 | friction | Censor style is duplicated in two places under two different names |
| 17 | 1.2 | polish | Post-import screen is developer metadata, not user value |
| 18 | 5.4 | polish | Main destinations are styled as tiny footnote buttons |
| 19 | 1.3 | polish | Disabled Export button gives no reason |
| 20 | 5.5 | polish | Export sheet auto-starts with no confirm step |
| 21 | 2.5 | polish | Extracted-audio playback never resets and fails silently |
| 22 | 7.2 / 7.3 | polish | Export sheet mixes two layouts and inverts button prominence |
| 23 | 3.3 | polish | Full-screen empty state crammed into a list cell |
| 24 | 6.5 | polish | Fixed 44/56 pt icon fonts ignore Dynamic Type |
| 25 | 6.6 | polish | Scrubber lacks a VoiceOver timecode value |
| 26 | 6.7 / 7.5 | polish | Censored-word red is borderline contrast and untokenized |
| 27 | 7.1 / 7.4 | polish | Scrim color and spacing constants hardcoded per view |
