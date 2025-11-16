//
//  VT100Parser.swift
//  LiquidGlassTerminal
//
//  VT100/ANSI escape sequence parser
//

import Foundation

/// Parser states for escape sequence processing
private enum ParseState {
    case ground           // Normal text
    case escape           // Received ESC
    case escapeIntermediate
    case csiEntry         // Control Sequence Introducer (ESC [)
    case csiParam
    case csiIntermediate
    case csiIgnore
    case oscString        // Operating System Command (ESC ])
    case dcsEntry         // Device Control String (ESC P)
    case dcsParam
    case dcsIntermediate
    case dcsPassthrough
    case dcsIgnore
}

/// VT100/xterm compatible terminal parser
@MainActor
class VT100Parser {
    private var state: ParseState = .ground
    private var params: [Int] = []
    private var intermediates: [UInt8] = []
    private var oscString: String = ""
    private var dcsString: Data = Data()

    // UTF-8 decoding state
    private var utf8Buffer: [UInt8] = []
    private var utf8ExpectedBytes: Int = 0

    // OSC/DCS termination state
    private var awaitingStringTerminator: Bool = false

    // Track if we've handled the initial linefeed from shell startup
    private var firstLinefeedSkipped: Bool = false

    /// Parse data and update terminal state
    func parse(_ data: Data, terminal: TerminalState) {
        for byte in data {
            processByte(byte, terminal: terminal)
        }
    }

    private func processByte(_ byte: UInt8, terminal: TerminalState) {
        switch state {
        case .ground:
            handleGround(byte, terminal)

        case .escape:
            handleEscape(byte, terminal)

        case .escapeIntermediate:
            handleEscapeIntermediate(byte, terminal)

        case .csiEntry:
            handleCSIEntry(byte, terminal)

        case .csiParam:
            handleCSIParam(byte, terminal)

        case .csiIntermediate:
            handleCSIIntermediate(byte, terminal)

        case .csiIgnore:
            handleCSIIgnore(byte)

        case .oscString:
            handleOSC(byte, terminal)

        case .dcsEntry, .dcsParam, .dcsIntermediate, .dcsPassthrough, .dcsIgnore:
            handleDCS(byte, terminal)
        }
    }

    // MARK: - Ground State

    private func handleGround(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x06, 0x0E...0x17, 0x19, 0x1C...0x1F:
            // Ignore control characters
            break

        case 0x07:  // BEL
            // Beep (could trigger system beep)
            break

        case 0x08:  // BS - Backspace
            terminal.backspace()

        case 0x09:  // HT - Tab
            terminal.tab()

        case 0x0A, 0x0B, 0x0C:  // LF, VT, FF - Line Feed
            // Skip the very first linefeed from shell initialization if still on row 0
            if !firstLinefeedSkipped && terminal.cursorPosition.row == 0 {
                firstLinefeedSkipped = true
                // Skip this linefeed - it's the initial shell output
                break
            }
            terminal.lineFeed()

        case 0x0D:  // CR - Carriage Return
            terminal.carriageReturn()

        case 0x1B:  // ESC
            state = .escape

        case 0x20...0x7E:  // ASCII printable
            let scalar = UnicodeScalar(byte)
            terminal.writeChar(Character(scalar))

        case 0x80...0xFF:  // UTF-8 continuation or start
            handleUTF8Byte(byte, terminal)

        default:
            break
        }
    }

    // MARK: - UTF-8 Handling

    private func handleUTF8Byte(_ byte: UInt8, _ terminal: TerminalState) {
        if utf8ExpectedBytes == 0 {
            // Start of new UTF-8 sequence
            utf8Buffer = [byte]

            if byte & 0b11100000 == 0b11000000 {
                // 2-byte sequence
                utf8ExpectedBytes = 2
            } else if byte & 0b11110000 == 0b11100000 {
                // 3-byte sequence
                utf8ExpectedBytes = 3
            } else if byte & 0b11111000 == 0b11110000 {
                // 4-byte sequence
                utf8ExpectedBytes = 4
            } else {
                // Invalid UTF-8 start byte, ignore
                utf8Buffer = []
                return
            }
        } else {
            // Continuation byte
            utf8Buffer.append(byte)
        }

        // Check if we have complete sequence
        if utf8Buffer.count == utf8ExpectedBytes {
            if let string = String(bytes: utf8Buffer, encoding: .utf8) {
                for char in string {
                    terminal.writeChar(char)
                }
            }
            utf8Buffer = []
            utf8ExpectedBytes = 0
        }
    }

    // MARK: - Escape State

    private func handleEscape(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x1F:  // Execute
            handleGround(byte, terminal)

        case UInt8(ascii: "["):  // CSI
            state = .csiEntry
            params = []
            intermediates = []

        case UInt8(ascii: "]"):  // OSC
            state = .oscString
            oscString = ""

        case UInt8(ascii: "P"):  // DCS
            state = .dcsEntry
            params = []
            intermediates = []
            dcsString = Data()

        case UInt8(ascii: "M"):  // RI - Reverse Index
            terminal.reverseLineFeed()
            state = .ground

        case UInt8(ascii: "E"):  // NEL - Next Line
            terminal.lineFeed()
            terminal.carriageReturn()
            state = .ground

        case UInt8(ascii: "D"):  // IND - Index
            terminal.lineFeed()
            state = .ground

        case UInt8(ascii: "7"):  // DECSC - Save Cursor
            terminal.saveCursor()
            state = .ground

        case UInt8(ascii: "8"):  // DECRC - Restore Cursor
            terminal.restoreCursor()
            state = .ground

        case UInt8(ascii: "c"):  // RIS - Reset to Initial State
            // Full reset
            terminal.currentAttributes.reset()
            terminal.moveCursor(to: .zero())
            terminal.eraseInDisplay(mode: 2)
            state = .ground

        case 0x20...0x2F:  // Intermediate
            intermediates.append(byte)
            state = .escapeIntermediate

        default:
            state = .ground
        }
    }

    private func handleEscapeIntermediate(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x1F:
            handleGround(byte, terminal)

        case 0x20...0x2F:
            intermediates.append(byte)

        default:
            state = .ground
        }
    }

    // MARK: - CSI (Control Sequence Introducer)

    private func handleCSIEntry(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x1F:
            handleGround(byte, terminal)

        case 0x30...0x39, UInt8(ascii: ";"):  // Parameters
            state = .csiParam
            handleCSIParam(byte, terminal)

        case 0x3C...0x3F:  // Private markers
            state = .csiParam

        case 0x20...0x2F:  // Intermediates
            intermediates.append(byte)
            state = .csiIntermediate

        case 0x40...0x7E:  // Final byte
            executeCSI(byte, terminal)
            state = .ground

        default:
            state = .ground
        }
    }

    private func handleCSIParam(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x1F:
            handleGround(byte, terminal)

        case 0x30...0x39:  // Digit
            if params.isEmpty {
                params.append(0)
            }
            let lastIndex = params.count - 1
            let digit = Int(byte - 0x30)

            // Protect against overflow
            let (newValue, overflow) = params[lastIndex].multipliedReportingOverflow(by: 10)
            if !overflow {
                let (finalValue, addOverflow) = newValue.addingReportingOverflow(digit)
                if !addOverflow && finalValue < 100000 {  // Reasonable upper limit
                    params[lastIndex] = finalValue
                }
            }

        case UInt8(ascii: ";"):  // Parameter separator
            params.append(0)

        case 0x20...0x2F:  // Intermediate
            intermediates.append(byte)
            state = .csiIntermediate

        case 0x3C...0x3F:  // Private marker
            break

        case 0x40...0x7E:  // Final byte
            executeCSI(byte, terminal)
            state = .ground

        default:
            state = .csiIgnore
        }
    }

    private func handleCSIIntermediate(_ byte: UInt8, _ terminal: TerminalState) {
        switch byte {
        case 0x00...0x1F:
            handleGround(byte, terminal)

        case 0x20...0x2F:
            intermediates.append(byte)

        case 0x40...0x7E:
            executeCSI(byte, terminal)
            state = .ground

        default:
            state = .csiIgnore
        }
    }

    private func handleCSIIgnore(_ byte: UInt8) {
        switch byte {
        case 0x40...0x7E:
            state = .ground
        default:
            break
        }
    }

    private func executeCSI(_ final: UInt8, _ terminal: TerminalState) {
        // Ensure we have at least one parameter
        if params.isEmpty {
            params.append(0)
        }

        let char = Character(UnicodeScalar(final))

        switch char {
        case "A":  // CUU - Cursor Up
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: -n, cols: 0)

        case "B":  // CUD - Cursor Down
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: n, cols: 0)

        case "C":  // CUF - Cursor Forward
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: 0, cols: n)

        case "D":  // CUB - Cursor Back
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: 0, cols: -n)

        case "E":  // CNL - Cursor Next Line
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: n, cols: 0)
            terminal.carriageReturn()

        case "F":  // CPL - Cursor Previous Line
            let n = max(1, params[0])
            terminal.moveCursorRelative(rows: -n, cols: 0)
            terminal.carriageReturn()

        case "G":  // CHA - Cursor Horizontal Absolute
            let col = max(1, params[0]) - 1
            terminal.cursorPosition.col = col
            terminal.cursorPosition.clamp(to: terminal.size)

        case "H", "f":  // CUP - Cursor Position
            let row = max(1, params.count > 0 ? params[0] : 1) - 1
            let col = max(1, params.count > 1 ? params[1] : 1) - 1
            terminal.moveCursor(to: CursorPosition(row: row, col: col))

        case "J":  // ED - Erase in Display
            let mode = params[0]
            terminal.eraseInDisplay(mode: mode)

        case "K":  // EL - Erase in Line
            let mode = params[0]
            terminal.eraseInLine(mode: mode)

        case "L":  // IL - Insert Lines
            let n = max(1, params[0])
            for _ in 0..<n {
                terminal.scrollDown(in: terminal.cursorPosition.row...terminal.scrollBottom)
            }

        case "M":  // DL - Delete Lines
            let n = max(1, params[0])
            for _ in 0..<n {
                terminal.scrollUp(in: terminal.cursorPosition.row...terminal.scrollBottom)
            }

        case "P":  // DCH - Delete Characters
            let n = max(1, params[0])
            let row = terminal.cursorPosition.row
            let col = terminal.cursorPosition.col
            if row < terminal.size.rows {
                for _ in 0..<n {
                    if col < terminal.size.cols - 1 {
                        terminal.buffer[row].remove(at: col)
                        terminal.buffer[row].append(.empty())
                    }
                }
                terminal.markDirty(row: row)
            }

        case "S":  // SU - Scroll Up
            let n = max(1, params[0])
            for _ in 0..<n {
                terminal.scrollUp(in: terminal.scrollTop...terminal.scrollBottom)
            }

        case "T":  // SD - Scroll Down
            let n = max(1, params[0])
            for _ in 0..<n {
                terminal.scrollDown(in: terminal.scrollTop...terminal.scrollBottom)
            }

        case "X":  // ECH - Erase Characters
            let n = max(1, params[0])
            let row = terminal.cursorPosition.row
            let startCol = terminal.cursorPosition.col
            for col in startCol..<min(startCol + n, terminal.size.cols) {
                terminal.setCell(.empty(), at: row, col: col)
            }

        case "d":  // VPA - Vertical Position Absolute
            let row = max(1, params[0]) - 1
            terminal.cursorPosition.row = row
            terminal.cursorPosition.clamp(to: terminal.size)

        case "h":  // SM - Set Mode
            handleSetMode(params, terminal)

        case "l":  // RM - Reset Mode
            handleResetMode(params, terminal)

        case "m":  // SGR - Select Graphic Rendition
            handleSGR(params, terminal)

        case "r":  // DECSTBM - Set Scrolling Region
            let top = max(1, params.count > 0 ? params[0] : 1) - 1
            let bottom = max(1, params.count > 1 ? params[1] : terminal.size.rows) - 1
            terminal.scrollTop = min(top, terminal.size.rows - 1)
            terminal.scrollBottom = min(bottom, terminal.size.rows - 1)
            terminal.moveCursor(to: .zero())

        case "s":  // SCOSC - Save Cursor Position
            terminal.saveCursor()

        case "u":  // SCORC - Restore Cursor Position
            terminal.restoreCursor()

        default:
            // Unhandled sequence
            break
        }

        params = []
        intermediates = []
    }

    // MARK: - SGR (Select Graphic Rendition)

    private func handleSGR(_ params: [Int], _ terminal: TerminalState) {
        if params.isEmpty || (params.count == 1 && params[0] == 0) {
            terminal.currentAttributes.reset()
            return
        }

        var i = 0
        while i < params.count {
            let param = params[i]

            switch param {
            case 0:  // Reset
                terminal.currentAttributes.reset()

            case 1:  // Bold
                terminal.currentAttributes.bold = true

            case 2:  // Dim
                terminal.currentAttributes.dim = true

            case 3:  // Italic
                terminal.currentAttributes.italic = true

            case 4:  // Underline
                terminal.currentAttributes.underline = true

            case 5, 6:  // Blink
                terminal.currentAttributes.blink = true

            case 7:  // Reverse
                terminal.currentAttributes.reverse = true

            case 8:  // Hidden
                terminal.currentAttributes.hidden = true

            case 9:  // Strikethrough
                terminal.currentAttributes.strikethrough = true

            case 22:  // Normal intensity
                terminal.currentAttributes.bold = false
                terminal.currentAttributes.dim = false

            case 23:  // Not italic
                terminal.currentAttributes.italic = false

            case 24:  // Not underlined
                terminal.currentAttributes.underline = false

            case 25:  // Not blinking
                terminal.currentAttributes.blink = false

            case 27:  // Not reversed
                terminal.currentAttributes.reverse = false

            case 28:  // Not hidden
                terminal.currentAttributes.hidden = false

            case 29:  // Not strikethrough
                terminal.currentAttributes.strikethrough = false

            case 30...37:  // Foreground color
                terminal.currentAttributes.foregroundColor = .ansi(param - 30)

            case 38:  // Extended foreground color
                i += parseSGRColor(params: params, startIndex: i + 1, terminal: terminal, isForeground: true)

            case 39:  // Default foreground
                terminal.currentAttributes.foregroundColor = .ansiDefault

            case 40...47:  // Background color
                terminal.currentAttributes.backgroundColor = .ansi(param - 40)

            case 48:  // Extended background color
                i += parseSGRColor(params: params, startIndex: i + 1, terminal: terminal, isForeground: false)

            case 49:  // Default background
                terminal.currentAttributes.backgroundColor = .ansiDefault

            case 90...97:  // Bright foreground color
                terminal.currentAttributes.foregroundColor = .ansi(param - 90 + 8)

            case 100...107:  // Bright background color
                terminal.currentAttributes.backgroundColor = .ansi(param - 100 + 8)

            default:
                break
            }

            i += 1
        }
    }

    private func parseSGRColor(params: [Int], startIndex: Int, terminal: TerminalState, isForeground: Bool) -> Int {
        guard startIndex < params.count else { return 0 }

        let colorType = params[startIndex]

        switch colorType {
        case 5:  // 256 color palette
            if startIndex + 1 < params.count {
                let index = params[startIndex + 1]
                let color = TerminalColor.palette256(index)
                if isForeground {
                    terminal.currentAttributes.foregroundColor = color
                } else {
                    terminal.currentAttributes.backgroundColor = color
                }
                return 2
            }

        case 2:  // RGB color
            if startIndex + 3 < params.count {
                let r = UInt8(clamping: params[startIndex + 1])
                let g = UInt8(clamping: params[startIndex + 2])
                let b = UInt8(clamping: params[startIndex + 3])
                let color = TerminalColor.rgb(r, g, b)
                if isForeground {
                    terminal.currentAttributes.foregroundColor = color
                } else {
                    terminal.currentAttributes.backgroundColor = color
                }
                return 4
            }

        default:
            break
        }

        return 0
    }

    // MARK: - Mode Handling

    private func handleSetMode(_ params: [Int], _ terminal: TerminalState) {
        for param in params {
            switch param {
            case 4:  // IRM - Insert Mode
                terminal.insertMode = true

            case 20:  // LNM - Line Feed/New Line Mode
                break

            case 25:  // Show cursor
                terminal.cursorVisible = true

            case 1049:  // Alternate screen buffer
                // TODO: Implement alternate buffer
                break

            case 2004:  // Bracketed paste mode
                terminal.bracketedPaste = true

            default:
                break
            }
        }
    }

    private func handleResetMode(_ params: [Int], _ terminal: TerminalState) {
        for param in params {
            switch param {
            case 4:  // IRM - Insert Mode
                terminal.insertMode = false

            case 25:  // Hide cursor
                terminal.cursorVisible = false

            case 1049:  // Alternate screen buffer
                // TODO: Implement alternate buffer
                break

            case 2004:  // Bracketed paste mode
                terminal.bracketedPaste = false

            default:
                break
            }
        }
    }

    // MARK: - OSC (Operating System Command)

    private func handleOSC(_ byte: UInt8, _ terminal: TerminalState) {
        // OSC sequences end with BEL or ST (ESC \)
        if byte == 0x07 {  // BEL
            executeOSC(oscString, terminal)
            state = .ground
            oscString = ""
            awaitingStringTerminator = false
        } else if byte == 0x1B {  // ESC (might be ST)
            awaitingStringTerminator = true
        } else if awaitingStringTerminator && byte == UInt8(ascii: "\\") {
            // ST (String Terminator) = ESC \
            executeOSC(oscString, terminal)
            state = .ground
            oscString = ""
            awaitingStringTerminator = false
        } else if byte >= 0x20 {
            let char = UnicodeScalar(byte)
            oscString.append(Character(char))
            awaitingStringTerminator = false
        }
    }

    private func executeOSC(_ string: String, _ terminal: TerminalState) {
        // Parse OSC sequences like "0;title" or "2;title"
        let parts = string.split(separator: ";", maxSplits: 1)
        guard let command = parts.first, let code = Int(command) else { return }

        switch code {
        case 0, 1, 2:  // Set window title
            // Could notify delegate to update window title
            break

        case 4:  // Set color palette
            // TODO: Implement custom color palette
            break

        case 52:  // Clipboard operations
            // TODO: Implement clipboard integration
            break

        default:
            break
        }
    }

    // MARK: - DCS (Device Control String)

    private func handleDCS(_ byte: UInt8, _ terminal: TerminalState) {
        // DCS handling - mostly ignore for now
        if byte == 0x1B {  // ESC (ST sequence)
            state = .ground
            dcsString = Data()
        } else if byte >= 0x20 {
            dcsString.append(byte)
        }
    }
}

// MARK: - Integer Clamping

extension UInt8 {
    init(clamping value: Int) {
        if value < 0 {
            self = 0
        } else if value > 255 {
            self = 255
        } else {
            self = UInt8(value)
        }
    }
}
