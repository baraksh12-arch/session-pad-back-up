// ColorMapper.swift
// SessionPad — Maps Ableton Live color indices to SwiftUI Colors.
//
// Ableton Live uses a fixed palette of 70 color indices (0-69).
// Index 0 is "no color" / grey. The palette matches exactly what
// Live displays in its clip and track color pickers.
//
// Source: Ableton Live 11/12 color palette (reverse-engineered from MIDI feedback
// and the Live Python API color_index property documentation).

import SwiftUI

enum ColorMapper {

    /// Returns the SwiftUI Color for a given Ableton color index.
    static func color(forIndex index: Int) -> Color {
        let clamped = max(0, min(69, index))
        if let entry = palette[clamped] {
            return Color(red: entry.r, green: entry.g, blue: entry.b)
        }
        return Color(white: 0.35)  // Default: dark grey
    }

    /// Returns a lighter (pastel) version for background fills.
    static func lightColor(forIndex index: Int) -> Color {
        color(forIndex: index).opacity(0.25)
    }

    // MARK: - Ableton Live Color Palette

    private struct RGB {
        let r, g, b: Double
        init(_ r: Int, _ g: Int, _ b: Int) {
            self.r = Double(r) / 255.0
            self.g = Double(g) / 255.0
            self.b = Double(b) / 255.0
        }
    }

    // Ableton Live 11/12 color palette — 70 entries (indices 0–69)
    // These are the exact RGB values from the Live UI.
    private static let palette: [Int: RGB] = [
        0:  RGB(90,  90,  90),   // Grey (default / no color)
        1:  RGB(255, 74,  74),   // Red
        2:  RGB(255, 155, 50),   // Orange
        3:  RGB(255, 210, 0),    // Yellow
        4:  RGB(200, 255, 0),    // Yellow-Green
        5:  RGB(113, 255, 0),    // Green
        6:  RGB(0,   255, 100),  // Mint
        7:  RGB(0,   255, 198),  // Teal
        8:  RGB(0,   210, 255),  // Cyan
        9:  RGB(0,   130, 255),  // Blue
        10: RGB(0,   74,  255),  // Deep Blue
        11: RGB(92,  0,   255),  // Indigo
        12: RGB(180, 0,   255),  // Violet
        13: RGB(255, 0,   215),  // Magenta
        14: RGB(255, 0,   115),  // Pink
        15: RGB(255, 0,   44),   // Crimson
        16: RGB(255, 130, 130),  // Light Red
        17: RGB(255, 195, 130),  // Peach
        18: RGB(255, 237, 130),  // Light Yellow
        19: RGB(228, 255, 130),  // Light Yellow-Green
        20: RGB(178, 255, 130),  // Light Green
        21: RGB(130, 255, 168),  // Light Mint
        22: RGB(130, 255, 226),  // Light Teal
        23: RGB(130, 228, 255),  // Light Cyan
        24: RGB(130, 178, 255),  // Light Blue
        25: RGB(130, 140, 255),  // Periwinkle
        26: RGB(165, 130, 255),  // Lavender
        27: RGB(215, 130, 255),  // Light Violet
        28: RGB(255, 130, 245),  // Light Magenta
        29: RGB(255, 130, 195),  // Light Pink
        30: RGB(255, 130, 155),  // Rose
        31: RGB(180, 75,  75),   // Dark Red
        32: RGB(180, 120, 75),   // Brown
        33: RGB(180, 165, 75),   // Dark Yellow
        34: RGB(140, 180, 75),   // Olive
        35: RGB(100, 180, 75),   // Forest Green
        36: RGB(75,  180, 112),  // Dark Mint
        37: RGB(75,  180, 165),  // Dark Teal
        38: RGB(75,  155, 180),  // Dark Cyan
        39: RGB(75,  115, 180),  // Dark Blue
        40: RGB(75,  85,  180),  // Dark Periwinkle
        41: RGB(110, 75,  180),  // Dark Indigo
        42: RGB(150, 75,  180),  // Dark Violet
        43: RGB(180, 75,  170),  // Dark Magenta
        44: RGB(180, 75,  130),  // Dark Pink
        45: RGB(180, 75,  90),   // Dark Rose
        46: RGB(100, 40,  40),   // Very Dark Red
        47: RGB(100, 70,  40),   // Very Dark Brown
        48: RGB(100, 93,  40),   // Very Dark Yellow
        49: RGB(76,  100, 40),   // Very Dark Olive
        50: RGB(52,  100, 40),   // Very Dark Green
        51: RGB(40,  100, 63),   // Very Dark Mint
        52: RGB(40,  100, 94),   // Very Dark Teal
        53: RGB(40,  84,  100),  // Very Dark Cyan
        54: RGB(40,  60,  100),  // Very Dark Blue
        55: RGB(40,  46,  100),  // Very Dark Periwinkle
        56: RGB(60,  40,  100),  // Very Dark Indigo
        57: RGB(85,  40,  100),  // Very Dark Violet
        58: RGB(100, 40,  95),   // Very Dark Magenta
        59: RGB(100, 40,  72),   // Very Dark Pink
        60: RGB(100, 40,  50),   // Very Dark Rose
        61: RGB(255, 255, 255),  // White
        62: RGB(210, 210, 210),  // Light Grey
        63: RGB(160, 160, 160),  // Mid Grey
        64: RGB(110, 110, 110),  // Dark Grey
        65: RGB(60,  60,  60),   // Very Dark Grey
        66: RGB(30,  30,  30),   // Near Black
        67: RGB(255, 150, 0),    // Amber
        68: RGB(185, 255, 0),    // Chartreuse
        69: RGB(0,   255, 50),   // Pure Green
    ]
}
