//
//  TerminalState.swift
//  LiquidGlassTerminal
//
//  Manages terminal buffer, cursor, and state
//

import Foundation
import Combine

/// Manages the complete state of a terminal session
@MainActor
class TerminalState: ObservableObject {
    // MARK: - Published Properties

    @Published var size: TerminalSize
    @Published var cursorPosition: CursorPosition
    @Published var cursorVisible: Bool = true
    @Published var cursorBlink: Bool = true

    // MARK: - Buffer

    /// Main screen buffer
    var buffer: [[TerminalCell]]

    /// Scrollback buffer (lines that have scrolled off screen)
    var scrollback: [[TerminalCell]] = []

    /// Maximum scrollback lines
    var maxScrollback: Int = 10000

    // MARK: - Text Attributes

    var currentAttributes = TextAttributes()

    // MARK: - Cursor State

    private var savedCursor: CursorPosition = .zero()
    private var savedAttributes = TextAttributes()

    // MARK: - Scroll Region

    var scrollTop: Int = 0
    var scrollBottom: Int

    // MARK: - Terminal Modes

    var applicationCursorKeys: Bool = false
    var applicationKeypad: Bool = false
    var autowrap: Bool = true
    var originMode: Bool = false
    var insertMode: Bool = false
    var bracketedPaste: Bool = false

    // MARK: - Dirty Tracking

    private(set) var dirtyRows: Set<Int> = []
    private var needsFullRedraw: Bool = true

    // MARK: - Initialization

    init(size: TerminalSize = .default()) {
        self.size = size
        self.scrollBottom = size.rows - 1
        self.cursorPosition = .zero()

        // Initialize buffer with empty cells
        self.buffer = Array(
            repeating: Array(repeating: .empty(), count: size.cols),
            count: size.rows
        )
    }

    // MARK: - Buffer Access

    /// Get cell at position
    func cell(at row: Int, col: Int) -> TerminalCell? {
        guard size.contains(row: row, col: col) else { return nil }
        return buffer[row][col]
    }

    /// Set cell at position
    func setCell(_ cell: TerminalCell, at row: Int, col: Int) {
        guard size.contains(row: row, col: col) else { return }
        buffer[row][col] = cell
        markDirty(row: row)
    }

    // MARK: - Writing

    /// Write a character at current cursor position
    func writeChar(_ char: Character) {
        print("✍️ writeChar '\(char)' at row:\(cursorPosition.row) col:\(cursorPosition.col)")

        // Handle wide characters
        let isWide = char.isWideCharacter

        // Check if there's room for wide character
        if isWide && cursorPosition.col >= size.cols - 1 {
            // Not enough room, wrap to next line if autowrap is on
            if autowrap {
                cursorPosition.col = 0
                lineFeed()
            } else {
                return
            }
        }

        var cell = TerminalCell(character: char)
        currentAttributes.apply(to: &cell)
        cell.isWide = isWide

        // Write the character
        if cursorPosition.row < size.rows && cursorPosition.col < size.cols {
            buffer[cursorPosition.row][cursorPosition.col] = cell
            markDirty(row: cursorPosition.row)
            print("✍️ Wrote '\(char)' to buffer[\(cursorPosition.row)][\(cursorPosition.col)]")

            // Mark next cell as continuation if wide
            if isWide && cursorPosition.col + 1 < size.cols {
                var wideContinuation = TerminalCell.empty()
                wideContinuation.character = " "
                buffer[cursorPosition.row][cursorPosition.col + 1] = wideContinuation
            }
        }

        // Advance cursor
        cursorPosition.col += isWide ? 2 : 1

        // Handle autowrap
        if cursorPosition.col >= size.cols {
            if autowrap {
                cursorPosition.col = 0
                lineFeed()
            } else {
                cursorPosition.col = size.cols - 1
            }
        }
    }

    // MARK: - Cursor Movement

    func moveCursor(to position: CursorPosition) {
        var newPos = position
        newPos.clamp(to: size)
        cursorPosition = newPos
    }

    func moveCursorRelative(rows: Int, cols: Int) {
        cursorPosition.row += rows
        cursorPosition.col += cols
        cursorPosition.clamp(to: size)
    }

    func carriageReturn() {
        cursorPosition.col = 0
    }

    func lineFeed() {
        if cursorPosition.row == scrollBottom {
            scrollUp(in: scrollTop...scrollBottom)
        } else {
            cursorPosition.row = min(cursorPosition.row + 1, size.rows - 1)
        }
    }

    func reverseLineFeed() {
        if cursorPosition.row == scrollTop {
            scrollDown(in: scrollTop...scrollBottom)
        } else {
            cursorPosition.row = max(cursorPosition.row - 1, 0)
        }
    }

    func tab() {
        // Tab stops every 8 columns
        let nextTab = ((cursorPosition.col / 8) + 1) * 8
        cursorPosition.col = min(nextTab, size.cols - 1)
    }

    func backspace() {
        if cursorPosition.col > 0 {
            cursorPosition.col -= 1
        }
    }

    // MARK: - Scrolling

    func scrollUp(in range: ClosedRange<Int>) {
        let start = max(0, range.lowerBound)
        let end = min(size.rows - 1, range.upperBound)

        // Save first line to scrollback
        if start == 0 {
            scrollback.append(buffer[start])
            if scrollback.count > maxScrollback {
                scrollback.removeFirst()
            }
        }

        // Scroll lines up
        for row in start..<end {
            buffer[row] = buffer[row + 1]
            markDirty(row: row)
        }

        // Clear last line
        buffer[end] = Array(repeating: .empty(), count: size.cols)
        markDirty(row: end)
    }

    func scrollDown(in range: ClosedRange<Int>) {
        let start = max(0, range.lowerBound)
        let end = min(size.rows - 1, range.upperBound)

        // Scroll lines down
        for row in stride(from: end, through: start + 1, by: -1) {
            buffer[row] = buffer[row - 1]
            markDirty(row: row)
        }

        // Clear first line
        buffer[start] = Array(repeating: .empty(), count: size.cols)
        markDirty(row: start)
    }

    // MARK: - Erasing

    func eraseInDisplay(mode: Int) {
        switch mode {
        case 0: // Erase from cursor to end of screen
            eraseInLine(mode: 0)
            for row in (cursorPosition.row + 1)..<size.rows {
                buffer[row] = Array(repeating: .empty(), count: size.cols)
                markDirty(row: row)
            }

        case 1: // Erase from start of screen to cursor
            for row in 0..<cursorPosition.row {
                buffer[row] = Array(repeating: .empty(), count: size.cols)
                markDirty(row: row)
            }
            eraseInLine(mode: 1)

        case 2, 3: // Erase entire screen (3 also clears scrollback)
            for row in 0..<size.rows {
                buffer[row] = Array(repeating: .empty(), count: size.cols)
                markDirty(row: row)
            }
            if mode == 3 {
                scrollback.removeAll()
            }

        default:
            break
        }
    }

    func eraseInLine(mode: Int) {
        let row = cursorPosition.row
        guard row < size.rows else { return }

        switch mode {
        case 0: // Erase from cursor to end of line
            for col in cursorPosition.col..<size.cols {
                buffer[row][col] = .empty()
            }

        case 1: // Erase from start of line to cursor
            for col in 0...min(cursorPosition.col, size.cols - 1) {
                buffer[row][col] = .empty()
            }

        case 2: // Erase entire line
            buffer[row] = Array(repeating: .empty(), count: size.cols)

        default:
            break
        }

        markDirty(row: row)
    }

    // MARK: - Cursor Save/Restore

    func saveCursor() {
        savedCursor = cursorPosition
        savedAttributes = currentAttributes
    }

    func restoreCursor() {
        cursorPosition = savedCursor
        currentAttributes = savedAttributes
    }

    // MARK: - Terminal Resize

    func resize(to newSize: TerminalSize) {
        guard newSize != size else { return }

        var newBuffer: [[TerminalCell]] = []

        // Copy existing content
        for row in 0..<min(size.rows, newSize.rows) {
            var newRow = Array(buffer[row].prefix(newSize.cols))

            // Pad or truncate
            if newRow.count < newSize.cols {
                newRow.append(contentsOf: Array(repeating: .empty(), count: newSize.cols - newRow.count))
            }

            newBuffer.append(newRow)
        }

        // Add new rows if needed
        while newBuffer.count < newSize.rows {
            newBuffer.append(Array(repeating: .empty(), count: newSize.cols))
        }

        buffer = newBuffer
        size = newSize
        scrollBottom = newSize.rows - 1

        // Clamp cursor position
        cursorPosition.clamp(to: size)

        markAllDirty()
    }

    // MARK: - Dirty Tracking

    func markDirty(row: Int) {
        guard row >= 0 && row < size.rows else { return }
        dirtyRows.insert(row)
    }

    func markAllDirty() {
        needsFullRedraw = true
        dirtyRows = Set(0..<size.rows)
    }

    func clearDirty() {
        dirtyRows.removeAll()
        needsFullRedraw = false
    }

    // MARK: - Text Extraction

    func getText(in selection: TerminalSelection) -> String {
        let normalized = selection.normalized()
        var text = ""

        for row in normalized.start.row...normalized.end.row {
            guard row < size.rows else { continue }

            let startCol = row == normalized.start.row ? normalized.start.col : 0
            let endCol = row == normalized.end.row ? normalized.end.col : size.cols - 1

            for col in startCol...endCol {
                guard col < size.cols else { continue }
                text.append(buffer[row][col].character)
            }

            if row < normalized.end.row {
                text.append("\n")
            }
        }

        return text
    }
}

// MARK: - Character Extensions

extension Character {
    /// Check if character is a wide character (CJK, etc.)
    var isWideCharacter: Bool {
        // Simplified check - in production, use proper Unicode width calculation
        guard let scalar = self.unicodeScalars.first else { return false }
        let value = scalar.value

        // CJK ranges (simplified)
        return (value >= 0x1100 && value <= 0x115F) ||  // Hangul Jamo
               (value >= 0x2E80 && value <= 0x9FFF) ||  // CJK
               (value >= 0xAC00 && value <= 0xD7A3) ||  // Hangul Syllables
               (value >= 0xF900 && value <= 0xFAFF) ||  // CJK Compatibility
               (value >= 0xFF00 && value <= 0xFF60) ||  // Fullwidth Forms
               (value >= 0xFFE0 && value <= 0xFFE6) ||  // Fullwidth Forms
               (value >= 0x20000 && value <= 0x2FFFD) || // CJK Extension
               (value >= 0x30000 && value <= 0x3FFFD)    // CJK Extension
    }
}
