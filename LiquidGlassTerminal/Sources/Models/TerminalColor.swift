//
//  TerminalColor.swift
//  LiquidGlassTerminal
//
//  Core color representation for terminal
//

import Foundation
import AppKit

/// Represents a terminal color with support for ANSI, 256-color palette, and RGB
enum TerminalColor: Equatable, Hashable {
    case ansiDefault
    case ansi(Int)           // 0-15
    case palette256(Int)     // 0-255
    case rgb(UInt8, UInt8, UInt8)  // True color

    /// Convert to NSColor for rendering
    func toNSColor(useDefaultForeground: NSColor? = nil, useDefaultBackground: NSColor? = nil, isForeground: Bool = true) -> NSColor {
        switch self {
        case .ansiDefault:
            if isForeground {
                return useDefaultForeground ?? ColorPalette.defaultForeground
            } else {
                return useDefaultBackground ?? ColorPalette.defaultBackground
            }

        case .ansi(let index):
            return ColorPalette.ansiColor(index)

        case .palette256(let index):
            return ColorPalette.color256(index)

        case .rgb(let r, let g, let b):
            return NSColor(
                red: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0
            )
        }
    }
}

/// Color palette definitions
struct ColorPalette {
    static let defaultForeground = NSColor(hex: "#E5E5E5")
    static let defaultBackground = NSColor(hex: "#000000", alpha: 0.0)  // Transparent for glass effect

    // 16 ANSI colors (matches VS Code dark theme)
    private static let ansiColors: [NSColor] = [
        // Normal colors (0-7)
        NSColor(hex: "#000000"),  // Black
        NSColor(hex: "#CD3131"),  // Red
        NSColor(hex: "#0DBC79"),  // Green
        NSColor(hex: "#E5E510"),  // Yellow
        NSColor(hex: "#2472C8"),  // Blue
        NSColor(hex: "#BC3FBC"),  // Magenta
        NSColor(hex: "#11A8CD"),  // Cyan
        NSColor(hex: "#E5E5E5"),  // White

        // Bright colors (8-15)
        NSColor(hex: "#666666"),  // Bright Black (Gray)
        NSColor(hex: "#F14C4C"),  // Bright Red
        NSColor(hex: "#23D18B"),  // Bright Green
        NSColor(hex: "#F5F543"),  // Bright Yellow
        NSColor(hex: "#3B8EEA"),  // Bright Blue
        NSColor(hex: "#D670D6"),  // Bright Magenta
        NSColor(hex: "#29B8DB"),  // Bright Cyan
        NSColor(hex: "#FFFFFF"),  // Bright White
    ]

    static func ansiColor(_ index: Int) -> NSColor {
        guard index >= 0 && index < ansiColors.count else {
            return defaultForeground
        }
        return ansiColors[index]
    }

    static func color256(_ index: Int) -> NSColor {
        // Validate index
        guard index >= 0 && index <= 255 else {
            return defaultForeground
        }

        // Handle 0-15 as ANSI colors
        if index < 16 {
            return ansiColor(index)
        }

        // 16-231: 6x6x6 color cube
        if index < 232 {
            let adjustedIndex = index - 16
            let r = (adjustedIndex / 36) * 51
            let g = ((adjustedIndex % 36) / 6) * 51
            let b = (adjustedIndex % 6) * 51

            return NSColor(
                red: CGFloat(r) / 255.0,
                green: CGFloat(g) / 255.0,
                blue: CGFloat(b) / 255.0,
                alpha: 1.0
            )
        }

        // 232-255: Grayscale
        let gray = (index - 232) * 10 + 8
        return NSColor(white: CGFloat(gray) / 255.0, alpha: 1.0)
    }
}

// MARK: - NSColor Extensions

extension NSColor {
    /// Create NSColor from hex string
    convenience init(hex: String, alpha: CGFloat = 1.0) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)

        let r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (r, g, b) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }

        self.init(
            red: CGFloat(r) / 255.0,
            green: CGFloat(g) / 255.0,
            blue: CGFloat(b) / 255.0,
            alpha: alpha
        )
    }

    /// Convert to hex string
    func toHex() -> String {
        guard let rgbColor = self.usingColorSpace(.deviceRGB) else {
            return "#000000"
        }

        var r: CGFloat = 0
        var g: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0

        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        return String(format: "#%02X%02X%02X",
                     Int(r * 255.0),
                     Int(g * 255.0),
                     Int(b * 255.0))
    }
}
