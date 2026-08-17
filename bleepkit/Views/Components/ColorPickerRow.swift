//
//  ColorPickerRow.swift
//  BleepKit
//

import SwiftUI
import UIKit

/// A color picker bound to the "#RRGGBB" hex strings the caption style
/// model stores.
struct ColorPickerRow: View {
    let title: String
    @Binding var hex: String

    var body: some View {
        ColorPicker(title, selection: colorBinding, supportsOpacity: false)
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(cgColor: CaptionLayerBuilder.color(hex: hex)) },
            set: { hex = $0.bleepKitHexString }
        )
    }
}

extension Color {
    /// "#RRGGBB" form of this color in sRGB, for persistence.
    var bleepKitHexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        UIColor(self).getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        func component(_ value: CGFloat) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02X%02X%02X", component(red), component(green), component(blue))
    }
}
