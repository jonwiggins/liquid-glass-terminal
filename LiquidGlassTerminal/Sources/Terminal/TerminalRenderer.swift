//
//  TerminalRenderer.swift
//  LiquidGlassTerminal
//
//  Core Graphics-based terminal text renderer
//

import Foundation
import AppKit
import CoreText

/// Renders terminal buffer to an NSView
class TerminalRenderer {
    // MARK: - Properties

    private let terminalState: TerminalState
    private var fontAtlas: FontAtlas
    private var cellSize: CGSize

    // MARK: - Initialization

    init(terminalState: TerminalState, font: NSFont) {
        self.terminalState = terminalState
        self.fontAtlas = FontAtlas(font: font)
        self.cellSize = fontAtlas.cellSize
    }

    // MARK: - Font Management

    func setFont(_ font: NSFont) {
        fontAtlas = FontAtlas(font: font)
        cellSize = fontAtlas.cellSize
    }

    var font: NSFont {
        return fontAtlas.font
    }

    // MARK: - Size Calculations

    func viewSize(for terminalSize: TerminalSize) -> CGSize {
        return CGSize(
            width: CGFloat(terminalSize.cols) * cellSize.width,
            height: CGFloat(terminalSize.rows) * cellSize.height
        )
    }

    func terminalSize(for viewSize: CGSize) -> TerminalSize {
        let cols = max(1, Int(viewSize.width / cellSize.width))
        let rows = max(1, Int(viewSize.height / cellSize.height))
        return TerminalSize(rows: rows, cols: cols)
    }

    // MARK: - Rendering

    @MainActor
    func draw(in context: CGContext, rect: CGRect) {
        print("🖼️ Renderer.draw() - terminal size: \(terminalState.size)")
        print("🖼️ Cursor at: \(terminalState.cursorPosition)")

        // Set rendering quality
        context.setAllowsAntialiasing(true)
        context.setShouldAntialias(true)
        context.setAllowsFontSmoothing(true)
        context.setShouldSmoothFonts(true)

        // Determine visible rows
        let startRow = max(0, Int(rect.minY / cellSize.height))
        let endRow = min(terminalState.size.rows - 1, Int(rect.maxY / cellSize.height) + 1)

        print("🖼️ Drawing rows \(startRow) to \(endRow)")

        // Draw each visible row
        var totalCells = 0
        for row in startRow...endRow {
            let cellsInRow = drawRow(row, in: context)
            totalCells += cellsInRow
        }

        print("🖼️ Drew \(totalCells) cells total")

        // Draw cursor
        if terminalState.cursorVisible {
            print("🖼️ Drawing cursor at \(terminalState.cursorPosition)")
            drawCursor(in: context)
        }
    }

    @MainActor
    private func drawRow(_ row: Int, in context: CGContext) -> Int {
        let y = CGFloat(row) * cellSize.height
        var drawnCells = 0

        for col in 0..<terminalState.size.cols {
            guard let cell = terminalState.cell(at: row, col: col) else { continue }

            // Debug first few cells of first row
            if row == 0 && col < 5 {
                print("🖼️ Row \(row) Col \(col): '\(cell.character)' fg:\(cell.foregroundColor) bg:\(cell.backgroundColor)")
            }

            let x = CGFloat(col) * cellSize.width
            let cellRect = CGRect(x: x, y: y, width: cellSize.width, height: cellSize.height)

            // Draw background if not default
            if cell.backgroundColor != .ansiDefault {
                let bgColor = cell.backgroundColor.toNSColor(isForeground: false)
                context.setFillColor(bgColor.cgColor)
                context.fill(cellRect)
            }

            // Skip empty or space characters
            if cell.character == " " && !cell.hasFormatting {
                continue
            }

            // Prepare text attributes
            var fgColor = cell.foregroundColor.toNSColor(isForeground: true)
            var font = fontAtlas.font

            // Apply formatting
            if cell.bold {
                if let boldFont = NSFont(
                    descriptor: font.fontDescriptor.withSymbolicTraits(.bold),
                    size: font.pointSize
                ) {
                    font = boldFont
                }
            }

            if cell.italic {
                if let italicFont = NSFont(
                    descriptor: font.fontDescriptor.withSymbolicTraits(.italic),
                    size: font.pointSize
                ) {
                    font = italicFont
                }
            }

            if cell.dim {
                fgColor = fgColor.withAlphaComponent(0.5)
            }

            if cell.reverse {
                // Swap foreground and background colors
                let bgColor = cell.backgroundColor.toNSColor(isForeground: false)
                let temp = fgColor
                fgColor = bgColor
                context.setFillColor(temp.cgColor)
                context.fill(cellRect)
            }

            // Draw character
            drawCharacter(
                cell.character,
                at: CGPoint(x: x, y: y),
                font: font,
                color: fgColor,
                in: context
            )

            // Draw underline
            if cell.underline {
                let underlineY = y + cellSize.height - 2
                context.setStrokeColor(fgColor.cgColor)
                context.setLineWidth(1.0)
                context.move(to: CGPoint(x: x, y: underlineY))
                context.addLine(to: CGPoint(x: x + cellSize.width, y: underlineY))
                context.strokePath()
            }

            // Draw strikethrough
            if cell.strikethrough {
                let strikeY = y + cellSize.height / 2
                context.setStrokeColor(fgColor.cgColor)
                context.setLineWidth(1.0)
                context.move(to: CGPoint(x: x, y: strikeY))
                context.addLine(to: CGPoint(x: x + cellSize.width, y: strikeY))
                context.strokePath()
            }

            drawnCells += 1
        }

        return drawnCells
    }

    private func drawCharacter(
        _ char: Character,
        at point: CGPoint,
        font: NSFont,
        color: NSColor,
        in context: CGContext
    ) {
        let string = String(char)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color
        ]

        let attrString = NSAttributedString(string: string, attributes: attributes)

        // Calculate baseline position
        let baselineY = point.y + (cellSize.height - font.ascender + font.descender) / 2 + font.ascender

        // Draw the string
        context.saveGState()
        context.textMatrix = .identity
        context.translateBy(x: point.x, y: baselineY)
        context.scaleBy(x: 1.0, y: -1.0)  // Flip coordinate system

        let line = CTLineCreateWithAttributedString(attrString)
        CTLineDraw(line, context)

        context.restoreGState()
    }

    @MainActor
    private func drawCursor(in context: CGContext) {
        let cursorX = CGFloat(terminalState.cursorPosition.col) * cellSize.width
        let cursorY = CGFloat(terminalState.cursorPosition.row) * cellSize.height

        let cursorRect = CGRect(
            x: cursorX,
            y: cursorY,
            width: cellSize.width,
            height: cellSize.height
        )

        // Draw cursor with glow effect
        context.saveGState()

        // Glow
        context.setShadow(
            offset: .zero,
            blur: 8.0,
            color: NSColor.systemBlue.withAlphaComponent(0.5).cgColor
        )

        // Cursor block
        context.setFillColor(NSColor.systemBlue.withAlphaComponent(0.7).cgColor)
        context.fill(cursorRect.insetBy(dx: 0.5, dy: 0.5))

        context.restoreGState()
    }
}

// MARK: - Font Atlas

/// Manages font metrics and glyph rendering
class FontAtlas {
    let font: NSFont
    let cellSize: CGSize

    init(font: NSFont) {
        self.font = font

        // Calculate cell size based on font metrics
        let attributes: [NSAttributedString.Key: Any] = [.font: font]
        let testString = NSAttributedString(string: "M", attributes: attributes)

        let line = CTLineCreateWithAttributedString(testString)
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0

        let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        let height = ceil(ascent + descent + leading)

        self.cellSize = CGSize(width: ceil(width), height: height)
    }
}
