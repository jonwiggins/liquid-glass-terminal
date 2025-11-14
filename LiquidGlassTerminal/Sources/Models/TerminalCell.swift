//
//  TerminalCell.swift
//  LiquidGlassTerminal
//
//  Represents a single cell in the terminal grid
//

import Foundation

/// A single character cell in the terminal with its formatting attributes
struct TerminalCell: Equatable, Hashable {
    var character: Character
    var foregroundColor: TerminalColor
    var backgroundColor: TerminalColor
    var bold: Bool
    var dim: Bool
    var italic: Bool
    var underline: Bool
    var blink: Bool
    var reverse: Bool
    var hidden: Bool
    var strikethrough: Bool

    /// Wide character flag (for CJK characters, etc.)
    var isWide: Bool

    /// Create empty cell with default attributes
    static func empty() -> TerminalCell {
        return TerminalCell(
            character: " ",
            foregroundColor: .ansiDefault,
            backgroundColor: .ansiDefault,
            bold: false,
            dim: false,
            italic: false,
            underline: false,
            blink: false,
            reverse: false,
            hidden: false,
            strikethrough: false,
            isWide: false
        )
    }

    /// Create cell with character and default attributes
    init(character: Character) {
        self.character = character
        self.foregroundColor = .ansiDefault
        self.backgroundColor = .ansiDefault
        self.bold = false
        self.dim = false
        self.italic = false
        self.underline = false
        self.blink = false
        self.reverse = false
        self.hidden = false
        self.strikethrough = false
        self.isWide = false
    }

    /// Full initializer
    init(
        character: Character,
        foregroundColor: TerminalColor,
        backgroundColor: TerminalColor,
        bold: Bool,
        dim: Bool,
        italic: Bool,
        underline: Bool,
        blink: Bool,
        reverse: Bool,
        hidden: Bool,
        strikethrough: Bool,
        isWide: Bool
    ) {
        self.character = character
        self.foregroundColor = foregroundColor
        self.backgroundColor = backgroundColor
        self.bold = bold
        self.dim = dim
        self.italic = italic
        self.underline = underline
        self.blink = blink
        self.reverse = reverse
        self.hidden = hidden
        self.strikethrough = strikethrough
        self.isWide = isWide
    }

    /// Check if cell has any special formatting
    var hasFormatting: Bool {
        return bold || dim || italic || underline || blink || reverse || hidden || strikethrough ||
               foregroundColor != .ansiDefault || backgroundColor != .ansiDefault
    }
}

/// Represents current text attributes for new characters
struct TextAttributes: Equatable {
    var foregroundColor: TerminalColor = .ansiDefault
    var backgroundColor: TerminalColor = .ansiDefault
    var bold: Bool = false
    var dim: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var blink: Bool = false
    var reverse: Bool = false
    var hidden: Bool = false
    var strikethrough: Bool = false

    /// Reset all attributes to defaults
    mutating func reset() {
        foregroundColor = .ansiDefault
        backgroundColor = .ansiDefault
        bold = false
        dim = false
        italic = false
        underline = false
        blink = false
        reverse = false
        hidden = false
        strikethrough = false
    }

    /// Apply attributes to a cell
    func apply(to cell: inout TerminalCell) {
        cell.foregroundColor = foregroundColor
        cell.backgroundColor = backgroundColor
        cell.bold = bold
        cell.dim = dim
        cell.italic = italic
        cell.underline = underline
        cell.blink = blink
        cell.reverse = reverse
        cell.hidden = hidden
        cell.strikethrough = strikethrough
    }
}
