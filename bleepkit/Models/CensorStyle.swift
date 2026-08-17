//
//  CensorStyle.swift
//  BleepKit
//

import Foundation

/// How a censored word is rendered in the burned-in caption.
///
/// The censored word keeps its position in the caption line — the rendering
/// is replaced, never the layout.
nonisolated enum CensorStyle: Codable, Hashable, Sendable {
    /// First character, then asterisks for the remaining length — "f***".
    case asterisks
    /// A filled rounded rect covering the word's measured glyph bounds.
    case blackBar
    /// A user-picked or bundled sticker, aspect-fit into the glyph bounds.
    case image(assetIdentifier: String)
    /// A single emoji glyph scaled to the glyph bounds' height.
    case emoji(String)
}
