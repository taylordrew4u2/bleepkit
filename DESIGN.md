# BleepKit — Cutting Room

This refinement retains the existing native SwiftUI identity: a dark video canvas, white actions, black text on white controls, system typography with Dynamic Type, and Apple SF Symbols. It changes screen hierarchy and review tools without changing video, transcript, censor, caption, or export defaults.

## Design source

Better Design custom project: `54abb566-82ee-4326-a29a-99a9787af461`.
The saved configuration specifies SF Pro, SF Mono, SF Symbols, a white primary color, black background, and 8-point card rounding. Its generated web kit still returns the initial blue/monospace/Feather draft, so that kit and showcase are not the native implementation spec. No web dependencies are installed into this SwiftUI app.

The implementation authority is `bleepkit/Support/Theme.swift` and the existing asset catalog. Keep platform semantic surfaces and secondary text for native forms, menus, sheets, and lists; do not replace them with fixed web approximations. Keep the system font loader and SF Symbols.

## Native component map

| Pattern | Native primitive |
| --- | --- |
| App navigation and project destinations | NavigationStack / NavigationLink |
| Photos and Files entry points | PhotosPicker / fileImporter |
| Secondary Help and Trash destinations | Menu |
| Transcript review and style inputs | List / Form / Picker / Toggle / Slider |
| Advanced style details | DisclosureGroup |
| Live style editing | Medium/large sheet on compact widths; inspector on regular widths |
| Playback and review transport | Native Buttons / Slider; decorative censor-range Canvas |
| Export state and recovery | ProgressView / confirmationDialog / ContentUnavailableView / ShareLink |

## Rules

- One Photos import action and one secondary Files action. Keep Help, Trash, and existing import paths reachable.
- Project titles sit below thumbnails; duration and action menu occupy different corners. Grid reflows to one column at accessibility text sizes.
- Review filters use effective `isCensored`, including manual overrides. Preserve every word, timing readout, text correction, and automatic/always/never option.
- Censor state has a visible symbol and an accurate spoken label. Seeking pauses playback; labels must not promise automatic playback.
- Timeline markers use the same padded ranges as preview/export. Preserve the native accessible slider and its timecode value.
- Keep all style controls and defaults. Disclosures reduce scrolling; caption typography/layout and censor treatment remain directly available.
- Slur detection is always enabled, while per-word overrides retain their existing behavior. Describe the distinction accurately.
- Export prepares before percentage rendering begins. Photos saving is non-dismissible; cancellation, retry, and direct sharing after denied Photos access remain available.
- Use `bleepOnAccent` on accent-filled surfaces. Use semantic text colors elsewhere and 44-point targets for standalone icon actions.
- Keep animations brief, interruptible, and sensitive to Reduce Motion. Read display scale and size classes from the consuming SwiftUI environment.

## Trade-offs

Frequent creators gain a clearer starting point, faster censor review, and less scrolling to style controls. Help/Trash and advanced details take an extra tap. The neutral monochrome identity keeps the video dominant; it intentionally forgoes a more colorful consumer rebrand.

## Verification

Compare equivalent empty and populated projects on iPhone and iPad, including accessibility text sizes. Exercise importing, transcript filters/corrections/overrides, live styling, next-bleep wrapping, scrubbing, export preparation/progress, cancel/retry, Photos-denied sharing, and source aspect-ratio preservation. Build and source review alone do not establish rendered visual approval.
