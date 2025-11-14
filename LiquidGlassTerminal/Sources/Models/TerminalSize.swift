//
//  TerminalSize.swift
//  LiquidGlassTerminal
//
//  Terminal dimensions and cursor position
//

import Foundation

/// Terminal dimensions
struct TerminalSize: Equatable {
    private var _rows: Int
    private var _cols: Int

    var rows: Int {
        get { _rows }
        set { _rows = max(1, newValue) }
    }

    var cols: Int {
        get { _cols }
        set { _cols = max(1, newValue) }
    }

    init(rows: Int, cols: Int) {
        self._rows = max(1, rows)
        self._cols = max(1, cols)
    }

    /// Create with default size
    static func `default`() -> TerminalSize {
        return TerminalSize(rows: 24, cols: 80)
    }

    /// Validate coordinates are within bounds
    func contains(row: Int, col: Int) -> Bool {
        return row >= 0 && row < rows && col >= 0 && col < cols
    }

    /// Equatable conformance
    static func == (lhs: TerminalSize, rhs: TerminalSize) -> Bool {
        return lhs.rows == rhs.rows && lhs.cols == rhs.cols
    }
}

/// Cursor position in the terminal
struct CursorPosition: Equatable {
    var row: Int
    var col: Int

    static func zero() -> CursorPosition {
        return CursorPosition(row: 0, col: 0)
    }

    /// Clamp position to valid range
    mutating func clamp(to size: TerminalSize) {
        row = max(0, min(row, size.rows - 1))
        col = max(0, min(col, size.cols - 1))
    }
}

/// Represents a rectangular selection in the terminal
struct TerminalSelection: Equatable {
    var start: CursorPosition
    var end: CursorPosition

    /// Check if position is within selection
    func contains(_ pos: CursorPosition) -> Bool {
        let minRow = min(start.row, end.row)
        let maxRow = max(start.row, end.row)
        let minCol = min(start.col, end.col)
        let maxCol = max(start.col, end.col)

        return pos.row >= minRow && pos.row <= maxRow &&
               pos.col >= minCol && pos.col <= maxCol
    }

    /// Get normalized selection (start before end)
    func normalized() -> TerminalSelection {
        if start.row < end.row || (start.row == end.row && start.col < end.col) {
            return self
        }
        return TerminalSelection(start: end, end: start)
    }
}
