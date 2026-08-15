//
//  Theme.swift
//  BleepKit
//

import SwiftUI
import UIKit

/// Design tokens for the "Redaction Desk" direction: ink-on-paper
/// monochrome, a single proofreader-red accent, and sharp print-like
/// geometry. Every color, spacing value, corner radius, and font style
/// the UI uses is defined here — views reference tokens, never literals.
///
/// System semantic colors (`.primary`, `.secondary`, `.tint`) are used
/// directly at call sites; they adapt on their own and are not literals.

// MARK: - Colors

extension Color {
    /// The single accent — proofreader red (asset: AccentColor). Marks
    /// anything censored or interactive; also drives the app-wide tint.
    /// Read straight from the asset: on iOS 26 the NSAccentColorName
    /// route was observed resolving to default blue at runtime, so the
    /// app applies this as an explicit root tint instead.
    static let bleepAccent = Color("AccentColor")
    /// Dimming layer between the video and full-screen state overlays
    /// (asset: VideoScrim).
    static let bleepScrim = Color(.videoScrim)
    /// Content drawn directly over video or the scrim, where the backdrop
    /// is dark in both appearances (asset: OnVideo).
    static let bleepOnVideo = Color(.onVideo)
    /// Letterbox surround behind the video preview (asset: VideoBackdrop).
    static let bleepVideoBackdrop = Color(.videoBackdrop)
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

// MARK: - Corner radii

/// Sharp, print-like geometry. Two values only.
enum Radius {
    /// Rectangles: bars, rules, redactions.
    static let sharp: CGFloat = 0
    /// Interactive controls: near-rectangles with just enough relief.
    static let control: CGFloat = 2
}

// MARK: - Typography

extension Font {
    /// New York bold — screen titles and result headlines (the masthead).
    static let bleepMasthead = Font.system(.title2, design: .serif, weight: .bold)
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
    /// The primary play/pause glyph. Fixed size — does not follow
    /// Dynamic Type (tracked as audit finding 6.5).
    static let bleepPlayGlyph = Font.system(size: 44)
    /// The export result mark. Fixed size — does not follow Dynamic Type
    /// (tracked as audit finding 6.5).
    static let bleepResultGlyph = Font.system(size: 56)
}
