//
//  CaptionStyle.swift
//  BleepKit
//

import CoreGraphics
import Foundation

/// User-adjustable appearance of the burned-in captions.
///
/// Colors are stored as hex strings ("#RRGGBB") so the model stays Codable
/// and free of UI-framework types.
nonisolated struct CaptionStyle: Codable, Hashable, Sendable {
    /// Font families available for captions. All ship with iOS — the SF
    /// and New York designs resolve through the system font; the rest
    /// are bundled classics resolved by family name.
    enum FontFamily: String, Codable, CaseIterable, Sendable {
        case sfPro, sfProRounded, newYork, sfMono
        case avenirNext, futura, georgia, americanTypewriter, markerFelt, chalkboard

        /// The name shown in the style picker.
        var displayName: String {
            switch self {
            case .sfPro: "SF Pro"
            case .sfProRounded: "SF Pro Rounded"
            case .newYork: "New York"
            case .sfMono: "SF Mono"
            case .avenirNext: "Avenir Next"
            case .futura: "Futura"
            case .georgia: "Georgia"
            case .americanTypewriter: "American Typewriter"
            case .markerFelt: "Marker Felt"
            case .chalkboard: "Chalkboard"
            }
        }

        /// The iOS font-family name, for fonts resolved by name rather
        /// than through a system design; nil for the SF/New York designs.
        var familyName: String? {
            switch self {
            case .sfPro, .sfProRounded, .newYork, .sfMono: nil
            case .avenirNext: "Avenir Next"
            case .futura: "Futura"
            case .georgia: "Georgia"
            case .americanTypewriter: "American Typewriter"
            case .markerFelt: "Marker Felt"
            case .chalkboard: "Chalkboard SE"
            }
        }
    }

    var fontFamily: FontFamily = .sfProRounded
    /// Point size at the 1080×1920 render scale.
    var fontSize: CGFloat = 72
    /// Numeric weight, 100...900; maps to `UIFont.Weight`.
    var fontWeight: Int = 800
    var fillColorHex: String = "#FFFFFF"
    /// Color of the currently spoken (karaoke-highlighted) word.
    var activeColorHex: String = "#FFD60A"
    var strokeWidth: CGFloat = 6
    var strokeColorHex: String = "#000000"
    var shadowOpacity: Float = 0.6
    var shadowRadius: CGFloat = 8
    var backgroundEnabled: Bool = false
    var backgroundColorHex: String = "#000000"
    var backgroundOpacity: Float = 0.5
    var backgroundCornerRadius: CGFloat = 16
    var backgroundPadding: CGFloat = 20
    /// 0 = top of frame, 1 = bottom. Defaults below center to clear
    /// Instagram's UI chrome; clamped to 0.15...0.88 when rendering.
    var verticalPositionNormalized: CGFloat = 0.78
    /// A caption line breaks after this many words…
    var maxWordsPerLine: Int = 3
    /// …or after this many seconds, whichever limit is reached first.
    var maxSecondsPerLine: Double = 1.6
}
