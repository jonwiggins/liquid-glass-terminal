# Terminal Emulation - Technical Reference

## Overview
This document covers the technical details of terminal emulation for the liquid glass terminal.

## Terminal Emulation Fundamentals

### What is a Terminal Emulator?

A terminal emulator is a program that:
1. **Spawns a shell process** (bash, zsh, fish, etc.) via a pseudo-terminal (PTY)
2. **Handles I/O** between the shell and the display
3. **Parses escape sequences** to interpret formatting commands
4. **Maintains terminal state** (cursor position, colors, modes, etc.)
5. **Renders text** to the screen with proper formatting
6. **Handles user input** (keyboard, mouse) and sends it to the shell

## PTY (Pseudo-Terminal) System

### What is a PTY?

A PTY is a pair of virtual devices that emulate a terminal:
- **Master side**: Terminal emulator reads/writes here
- **Slave side**: Shell process reads/writes here

### macOS PTY Implementation

```swift
import Darwin

class PTYController {
    private var masterFD: Int32 = -1
    private var slaveFD: Int32 = -1
    private var childPID: pid_t = -1
    private var slaveName: String = ""

    func openPTY() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var slavePath = [CChar](repeating: 0, count: 1024)

        // Open master PTY
        guard openpty(&master, &slave, &slavePath, nil, nil) == 0 else {
            throw PTYError.openFailed
        }

        self.masterFD = master
        self.slaveFD = slave
        self.slaveName = String(cString: slavePath)

        // Set non-blocking I/O on master
        fcntl(master, F_SETFL, O_NONBLOCK)
    }

    func spawn(command: String, args: [String] = [], env: [String: String] = [:]) throws {
        let pid = fork()

        if pid == 0 {
            // Child process

            // Create new session
            setsid()

            // Set controlling terminal
            ioctl(slaveFD, TIOCSCTTY, 0)

            // Redirect stdio to slave
            dup2(slaveFD, STDIN_FILENO)
            dup2(slaveFD, STDOUT_FILENO)
            dup2(slaveFD, STDERR_FILENO)

            // Close unused FDs
            close(masterFD)
            if slaveFD > 2 {
                close(slaveFD)
            }

            // Set environment
            var envArray = env.map { "\($0.key)=\($0.value)" }

            // Execute shell
            let argv = ([command] + args).map { strdup($0) } + [nil]
            execve(command, argv, environ)

            // If we get here, exec failed
            exit(1)
        } else if pid > 0 {
            // Parent process
            self.childPID = pid

            // Close slave (only child needs it)
            close(slaveFD)
            slaveFD = -1
        } else {
            throw PTYError.forkFailed
        }
    }

    func read() -> Data? {
        var buffer = [UInt8](repeating: 0, count: 4096)
        let bytesRead = Darwin.read(masterFD, &buffer, buffer.count)

        if bytesRead > 0 {
            return Data(buffer[..<bytesRead])
        }

        return nil
    }

    func write(_ data: Data) {
        data.withUnsafeBytes { bytes in
            Darwin.write(masterFD, bytes.baseAddress, data.count)
        }
    }

    func resize(rows: Int, cols: Int) {
        var size = winsize()
        size.ws_row = UInt16(rows)
        size.ws_col = UInt16(cols)
        ioctl(masterFD, TIOCSWINSZ, &size)
    }
}
```

### I/O Handling with DispatchSource

```swift
class PTYIOHandler {
    private let pty: PTYController
    private var readSource: DispatchSourceRead?

    func startMonitoring(onData: @escaping (Data) -> Void) {
        readSource = DispatchSource.makeReadSource(
            fileDescriptor: pty.masterFD,
            queue: .global(qos: .userInteractive)
        )

        readSource?.setEventHandler { [weak self] in
            guard let self = self,
                  let data = self.pty.read() else { return }

            DispatchQueue.main.async {
                onData(data)
            }
        }

        readSource?.resume()
    }

    func stopMonitoring() {
        readSource?.cancel()
        readSource = nil
    }
}
```

## VT100 / ANSI Escape Sequence Parsing

### Escape Sequence Structure

```
ESC [ <parameters> <command>
```

Examples:
- `ESC[2J` - Clear screen
- `ESC[H` - Move cursor to home (0,0)
- `ESC[31m` - Set foreground color to red
- `ESC[1;32m` - Bold + green

### Parser Implementation

```swift
enum ParseState {
    case ground           // Normal text
    case escape           // Received ESC
    case csi              // Control Sequence Introducer (ESC [)
    case oscString        // Operating System Command
    case dcsString        // Device Control String
}

class VT100Parser {
    private var state: ParseState = .ground
    private var params: [Int] = []
    private var currentParam: String = ""
    private var oscString: String = ""

    func parse(_ byte: UInt8, terminal: inout TerminalState) {
        let char = Character(UnicodeScalar(byte))

        switch state {
        case .ground:
            handleGround(byte, &terminal)

        case .escape:
            handleEscape(byte, &terminal)

        case .csi:
            handleCSI(byte, &terminal)

        case .oscString:
            handleOSC(byte, &terminal)

        case .dcsString:
            handleDCS(byte, &terminal)
        }
    }

    private func handleGround(_ byte: UInt8, _ terminal: inout TerminalState) {
        switch byte {
        case 0x1B:  // ESC
            state = .escape

        case 0x08:  // Backspace
            terminal.moveCursorLeft()

        case 0x09:  // Tab
            terminal.tab()

        case 0x0A, 0x0B, 0x0C:  // LF, VT, FF
            terminal.lineFeed()

        case 0x0D:  // CR
            terminal.carriageReturn()

        case 0x20...0x7E, 0x80...0xFF:  // Printable characters
            terminal.printChar(byte)

        default:
            break
        }
    }

    private func handleEscape(_ byte: UInt8, _ terminal: inout TerminalState) {
        switch byte {
        case UInt8(ascii: "["):
            state = .csi
            params = []
            currentParam = ""

        case UInt8(ascii: "]"):
            state = .oscString
            oscString = ""

        case UInt8(ascii: "P"):
            state = .dcsString

        case UInt8(ascii: "M"):  // Reverse index
            terminal.reverseIndex()
            state = .ground

        case UInt8(ascii: "7"):  // Save cursor
            terminal.saveCursor()
            state = .ground

        case UInt8(ascii: "8"):  // Restore cursor
            terminal.restoreCursor()
            state = .ground

        default:
            state = .ground
        }
    }

    private func handleCSI(_ byte: UInt8, _ terminal: inout TerminalState) {
        switch byte {
        case 0x30...0x39:  // Digits 0-9
            currentParam.append(Character(UnicodeScalar(byte)))

        case UInt8(ascii: ";"):
            if let param = Int(currentParam) {
                params.append(param)
            }
            currentParam = ""

        case UInt8(ascii: "H"), UInt8(ascii: "f"):  // Cursor position
            executeCSI_CursorPosition(terminal: &terminal)

        case UInt8(ascii: "A"):  // Cursor up
            executeCSI_CursorUp(terminal: &terminal)

        case UInt8(ascii: "B"):  // Cursor down
            executeCSI_CursorDown(terminal: &terminal)

        case UInt8(ascii: "C"):  // Cursor forward
            executeCSI_CursorForward(terminal: &terminal)

        case UInt8(ascii: "D"):  // Cursor back
            executeCSI_CursorBack(terminal: &terminal)

        case UInt8(ascii: "J"):  // Erase display
            executeCSI_EraseDisplay(terminal: &terminal)

        case UInt8(ascii: "K"):  // Erase line
            executeCSI_EraseLine(terminal: &terminal)

        case UInt8(ascii: "m"):  // SGR - Select Graphic Rendition
            executeCSI_SGR(terminal: &terminal)

        case UInt8(ascii: "r"):  // Set scroll region
            executeCSI_SetScrollRegion(terminal: &terminal)

        default:
            state = .ground
        }
    }

    private func executeCSI_CursorPosition(terminal: inout TerminalState) {
        let row = params.first ?? 1
        let col = params.count > 1 ? params[1] : 1
        terminal.setCursorPosition(row: row - 1, col: col - 1)
        state = .ground
    }

    private func executeCSI_SGR(terminal: inout TerminalState) {
        if let param = Int(currentParam) {
            params.append(param)
        }

        if params.isEmpty {
            params = [0]  // Reset
        }

        var i = 0
        while i < params.count {
            let param = params[i]

            switch param {
            case 0:  // Reset
                terminal.resetAttributes()

            case 1:  // Bold
                terminal.setBold(true)

            case 2:  // Dim
                terminal.setDim(true)

            case 3:  // Italic
                terminal.setItalic(true)

            case 4:  // Underline
                terminal.setUnderline(true)

            case 5, 6:  // Blink
                terminal.setBlink(true)

            case 7:  // Reverse
                terminal.setReverse(true)

            case 8:  // Hidden
                terminal.setHidden(true)

            case 9:  // Strikethrough
                terminal.setStrikethrough(true)

            case 22:  // Normal intensity
                terminal.setBold(false)
                terminal.setDim(false)

            case 30...37:  // Foreground color
                terminal.setForegroundColor(.ansi(param - 30))

            case 38:  // Extended foreground color
                i += parseExtendedColor(params: params, start: i + 1, terminal: &terminal, isForeground: true)

            case 40...47:  // Background color
                terminal.setBackgroundColor(.ansi(param - 40))

            case 48:  // Extended background color
                i += parseExtendedColor(params: params, start: i + 1, terminal: &terminal, isForeground: false)

            case 90...97:  // Bright foreground color
                terminal.setForegroundColor(.ansi(param - 90 + 8))

            case 100...107:  // Bright background color
                terminal.setBackgroundColor(.ansi(param - 100 + 8))

            default:
                break
            }

            i += 1
        }

        state = .ground
    }

    private func parseExtendedColor(params: [Int], start: Int, terminal: inout TerminalState, isForeground: Bool) -> Int {
        guard start < params.count else { return 0 }

        let colorType = params[start]

        switch colorType {
        case 5:  // 256 color
            if start + 1 < params.count {
                let colorIndex = params[start + 1]
                let color = TerminalColor.palette256(colorIndex)
                if isForeground {
                    terminal.setForegroundColor(color)
                } else {
                    terminal.setBackgroundColor(color)
                }
                return 2
            }

        case 2:  // RGB color
            if start + 3 < params.count {
                let r = params[start + 1]
                let g = params[start + 2]
                let b = params[start + 3]
                let color = TerminalColor.rgb(r, g, b)
                if isForeground {
                    terminal.setForegroundColor(color)
                } else {
                    terminal.setBackgroundColor(color)
                }
                return 4
            }

        default:
            break
        }

        return 0
    }
}
```

## Terminal State Management

```swift
struct TerminalCell {
    var char: Character = " "
    var foregroundColor: TerminalColor = .ansiDefault
    var backgroundColor: TerminalColor = .ansiDefault
    var bold: Bool = false
    var italic: Bool = false
    var underline: Bool = false
    var blink: Bool = false
    var reverse: Bool = false
    var strikethrough: Bool = false
}

enum TerminalColor {
    case ansiDefault
    case ansi(Int)           // 0-15
    case palette256(Int)     // 0-255
    case rgb(Int, Int, Int)  // True color
}

class TerminalState {
    var rows: Int
    var cols: Int
    var buffer: [[TerminalCell]]
    var scrollback: [[TerminalCell]] = []
    var cursorRow: Int = 0
    var cursorCol: Int = 0
    var savedCursor: (row: Int, col: Int) = (0, 0)

    // Current text attributes
    var currentFg: TerminalColor = .ansiDefault
    var currentBg: TerminalColor = .ansiDefault
    var currentBold: Bool = false
    var currentItalic: Bool = false
    var currentUnderline: Bool = false
    var currentBlink: Bool = false
    var currentReverse: Bool = false
    var currentStrikethrough: Bool = false

    // Scroll region
    var scrollTop: Int = 0
    var scrollBottom: Int

    init(rows: Int, cols: Int) {
        self.rows = rows
        self.cols = cols
        self.scrollBottom = rows - 1
        self.buffer = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
    }

    func printChar(_ byte: UInt8) {
        guard cursorRow < rows && cursorCol < cols else { return }

        var cell = TerminalCell()
        cell.char = Character(UnicodeScalar(byte))
        cell.foregroundColor = currentFg
        cell.backgroundColor = currentBg
        cell.bold = currentBold
        cell.italic = currentItalic
        cell.underline = currentUnderline
        cell.blink = currentBlink
        cell.reverse = currentReverse
        cell.strikethrough = currentStrikethrough

        buffer[cursorRow][cursorCol] = cell

        cursorCol += 1
        if cursorCol >= cols {
            cursorCol = 0
            lineFeed()
        }
    }

    func lineFeed() {
        cursorRow += 1

        if cursorRow > scrollBottom {
            // Scroll up
            let scrolledLine = buffer.removeFirst()
            scrollback.append(scrolledLine)
            buffer.append(Array(repeating: TerminalCell(), count: cols))
            cursorRow = scrollBottom
        }
    }

    func carriageReturn() {
        cursorCol = 0
    }

    func setCursorPosition(row: Int, col: Int) {
        cursorRow = max(0, min(row, rows - 1))
        cursorCol = max(0, min(col, cols - 1))
    }

    func clearScreen() {
        buffer = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
        cursorRow = 0
        cursorCol = 0
    }

    // ... more methods ...
}
```

## Color Support

### 16 ANSI Colors
```swift
let ansiColors: [NSColor] = [
    // Normal
    NSColor(hex: "#000000"),  // 0: Black
    NSColor(hex: "#CD3131"),  // 1: Red
    NSColor(hex: "#0DBC79"),  // 2: Green
    NSColor(hex: "#E5E510"),  // 3: Yellow
    NSColor(hex: "#2472C8"),  // 4: Blue
    NSColor(hex: "#BC3FBC"),  // 5: Magenta
    NSColor(hex: "#11A8CD"),  // 6: Cyan
    NSColor(hex: "#E5E5E5"),  // 7: White

    // Bright
    NSColor(hex: "#666666"),  // 8: Bright Black
    NSColor(hex: "#F14C4C"),  // 9: Bright Red
    NSColor(hex: "#23D18B"),  // 10: Bright Green
    NSColor(hex: "#F5F543"),  // 11: Bright Yellow
    NSColor(hex: "#3B8EEA"),  // 12: Bright Blue
    NSColor(hex: "#D670D6"),  // 13: Bright Magenta
    NSColor(hex: "#29B8DB"),  // 14: Bright Cyan
    NSColor(hex: "#FFFFFF"),  // 15: Bright White
]
```

### 256 Color Palette
```swift
func color256(_ index: Int) -> NSColor {
    if index < 16 {
        return ansiColors[index]
    } else if index < 232 {
        // 216 colors: 6x6x6 cube
        let i = index - 16
        let r = (i / 36) * 51
        let g = ((i % 36) / 6) * 51
        let b = (i % 6) * 51
        return NSColor(red: CGFloat(r) / 255,
                      green: CGFloat(g) / 255,
                      blue: CGFloat(b) / 255,
                      alpha: 1.0)
    } else {
        // 24 grayscale colors
        let gray = (index - 232) * 10 + 8
        return NSColor(white: CGFloat(gray) / 255, alpha: 1.0)
    }
}
```

## Performance Considerations

### 1. Efficient Buffer Updates
```swift
struct DirtyRegion {
    var minRow: Int
    var maxRow: Int
    var minCol: Int
    var maxCol: Int
}

class TerminalBuffer {
    private var dirtyRegions: [DirtyRegion] = []

    func markDirty(row: Int, col: Int) {
        // Coalesce nearby dirty regions
        // Only redraw changed areas
    }
}
```

### 2. Double Buffering
```swift
class TerminalEngine {
    var frontBuffer: TerminalState
    var backBuffer: TerminalState

    func swap() {
        swap(&frontBuffer, &backBuffer)
    }
}
```

### 3. Lazy Scrollback
```swift
// Only keep recent scrollback in memory
let maxScrollback = 10000
if scrollback.count > maxScrollback {
    scrollback.removeFirst(scrollback.count - maxScrollback)
}
```

## Testing Terminal Emulation

### Test Suite
1. **vttest** - Comprehensive VT100/VT220 test
2. **Terminal test files** - ANSI art, color tests
3. **Application tests** - vim, emacs, tmux, htop
4. **Unicode test** - Emoji, CJK characters, combining marks

### Common Issues
- Incorrect cursor positioning
- Wrong color rendering (especially 256-color and RGB)
- Scrolling bugs (region scrolling vs. full screen)
- Wraparound handling
- Character width calculation (wide chars)

## References

- [VT100 User Guide](https://vt100.net/docs/vt100-ug/)
- [xterm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)
- [ANSI Escape Codes](https://en.wikipedia.org/wiki/ANSI_escape_code)
- [Terminal emulator guide](https://www.asciitable.com/)
- [iTerm2 Proprietary Sequences](https://iterm2.com/documentation-escape-codes.html)
