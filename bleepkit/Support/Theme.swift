//
//  Theme.swift
//  BleepKit
//

import SwiftUI
import UIKit

/// Design tokens for the "Cutting Room" direction: monochrome minimal,
/// white on black like the app icon — one tool, one job, no color.
/// Every color, spacing value, corner radius, and font style the UI
/// uses is defined here — views reference tokens, never literals.
///
/// System semantic colors (`.primary`, `.secondary`, `.tint`) are used
/// directly at call sites; they adapt on their own and are not literals.

// MARK: - Colors

extension Color {
    /// The single accent — plain white, the icon's bubble (asset:
    /// AccentColor). Marks anything censored or interactive; also
    /// drives the app-wide tint.
    /// Read straight from the asset: on iOS 26 the NSAccentColorName
    /// route was observed resolving to default blue at runtime, so the
    /// app applies this as an explicit root tint instead.
    static let bleepAccent = Color("AccentColor")
    /// Text and glyphs sitting on an accent-filled surface — black on
    /// the white, like the icon's grawlix (asset: OnAccent).
    static let bleepOnAccent = Color(.onAccent)
    /// Dimming layer between the video and full-screen state overlays
    /// (asset: VideoScrim).
    static let bleepScrim = Color(.videoScrim)
    /// Content drawn directly over video or the scrim, where the backdrop
    /// is dark in both appearances (asset: OnVideo).
    static let bleepOnVideo = Color(.onVideo)
    /// Letterbox surround behind the video preview (asset: VideoBackdrop).
    static let bleepVideoBackdrop = Color(.videoBackdrop)
    /// The animated splash's backdrop — pure black in both appearances,
    /// matching the static launch screen for a seamless cold start
    /// (asset: LaunchBackground).
    static let bleepLaunchBackground = Color(.launchBackground)
}

extension UIColor {
    /// UIKit twin of `Color.bleepVideoBackdrop` for the player container.
    static let bleepVideoBackdrop = UIColor(resource: .videoBackdrop)
}

// MARK: - Spacing

/// Spacing scale in points. `standard` (12) and `roomy` (24) predate the
/// editorial 8/16/32/48 scale and are kept so tokenization changes no
/// layout; collapse them onto the scale in a deliberate later pass.
enum Spacing {
    /// 2 pt — a label and its sub-caption inside one row.
    static let hairline: CGFloat = 2
    /// 4 pt — a control and its readout.
    static let tight: CGFloat = 4
    /// 8 pt — related controls within a group.
    static let compact: CGFloat = 8
    /// 12 pt — sibling groups.
    static let standard: CGFloat = 12
    /// 16 pt — distinct sections.
    static let medium: CGFloat = 16
    /// 24 pt — major regions.
    static let roomy: CGFloat = 24
    /// 32 pt — page-level breathing room.
    static let wide: CGFloat = 32
}

// MARK: - Adaptive layout

/// Width caps for regular-width (iPad, Stage Manager) layouts; compact
/// layouts ignore them by never reaching the cap.
enum ContentWidth {
    /// The dashboard's centered column.
    static let dashboard: CGFloat = 700
    /// The style editors' trailing inspector pane.
    static let inspector: CGFloat = 380
    /// The paywall's centered column.
    static let paywall: CGFloat = 440
    /// Minimum project-grid tile width — two columns on iPhone,
    /// more as the dashboard column allows.
    static let gridTileMin: CGFloat = 160
}

// MARK: - Tap targets

/// Minimum hit-area for interactive elements, per the HIG.
enum TapTarget {
    static let minimum: CGFloat = 44
}

// MARK: - Corner radii

enum Radius {
    /// Rectangles: bars, rules, redactions.
    static let sharp: CGFloat = 0
    /// Small inline controls and badges.
    static let control: CGFloat = 2
    /// Cards: project tiles and the continue-editing hero.
    static let card: CGFloat = 16
}

// MARK: - Typography

extension Font {
    /// Quiet sans — screen titles and result headlines.
    static let bleepMasthead = Font.system(.title3, weight: .semibold)
    /// Emphasized standalone line: loading messages, export percentage.
    static let bleepEmphasis = Font.headline
    /// Supporting prose one step under body.
    static let bleepDetail = Font.callout
    /// Numeric readouts beside sliders.
    static let bleepDetailValue = Font.callout.monospacedDigit()
    /// Row metadata: dates, durations, file details.
    static let bleepMetadata = Font.caption
    /// Timecodes aligned in columns.
    static let bleepTimecode = Font.caption.monospacedDigit()
    /// Smallest annotations: override states, engine names.
    static let bleepFineprint = Font.caption2
    /// Smallest numeric annotations: millisecond durations.
    static let bleepFineprintTimecode = Font.caption2.monospacedDigit()
    /// Labels on compact inline controls.
    static let bleepControlLabel = Font.footnote
    /// Transport step buttons (icon sizing).
    static let bleepTransportGlyph = Font.title2
}

// MARK: - Thumbnails

/// Fixed frames for video thumbnails on the dashboard.
enum ThumbnailSize {
    /// The continue-editing hero card's height.
    static let heroHeight: CGFloat = 220
    /// A project grid tile's image height.
    static let gridHeight: CGFloat = 110
    /// Decode cap for the hero thumbnail (roughly full width at 3×).
    static let heroMaxPixels: CGFloat = 1200
    /// Decode cap for grid tile thumbnails.
    static let gridMaxPixels: CGFloat = 540
}

// MARK: - Launch splash

/// Geometry of the launch splash's meter-into-speech-bubble animation.
enum SplashMetrics {
    /// Width of one audio-meter bar.
    static let barWidth: CGFloat = 8
    /// Peak meter-bar height.
    static let meterHeight: CGFloat = 96
    /// Number of meter bars.
    static let barCount: Int = 12
    /// The app icon's speech bubble, tail included, that the meter
    /// collapses into.
    static let bubbleWidth: CGFloat = 250
    /// Its height.
    static let bubbleHeight: CGFloat = 190
}

extension Font {
    /// The splash's grawlix wordmark, sized to the icon bubble. Fixed
    /// size on purpose: it's decorative art, hidden from accessibility.
    static let bleepSplashGrawlix = Font.system(size: 56, weight: .bold)
}

// MARK: - Glyph sizes

/// Base sizes for oversized standalone glyphs. Consume through
/// `@ScaledMetric` so they follow Dynamic Type (audit 6.5).
enum GlyphSize {
    /// The primary play/pause glyph.
    static let play: CGFloat = 44
}
