# Quick Start Guide

## Getting Started with Development

### Prerequisites

1. **macOS 13.0+** (Ventura or later)
2. **Xcode 15.0+** with Swift 6.0
3. **Command Line Tools**: `xcode-select --install`

### Initial Setup

#### Step 1: Create Xcode Project

```bash
# Open Xcode and create new project
# File > New > Project
# Choose: macOS > App
# Interface: SwiftUI
# Language: Swift
```

**Project Settings:**
- Product Name: `LiquidGlassTerminal`
- Organization Identifier: `com.yourname`
- Bundle Identifier: `com.yourname.LiquidGlassTerminal`
- Deployment Target: macOS 13.0

#### Step 2: Project Structure

Create the following folder structure in your project:

```
LiquidGlassTerminal/
├── App/
│   ├── LiquidGlassTerminalApp.swift  (Entry point)
│   └── ContentView.swift              (Main window)
├── Glass/
│   └── GlassBackgroundView.swift     (Glass effects)
├── Terminal/
│   ├── TerminalView.swift            (Terminal display)
│   └── TerminalState.swift           (Terminal state)
├── Shell/
│   └── PTYController.swift           (PTY handling)
└── Parser/
    └── VT100Parser.swift             (Escape sequences)
```

### Phase 0: Basic Window with Glass Effect

#### 1. Create GlassBackgroundView.swift

```swift
import SwiftUI
import AppKit

struct GlassBackgroundView: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}
```

#### 2. Create Basic ContentView.swift

```swift
import SwiftUI

struct ContentView: View {
    @State private var terminalText = "$ "

    var body: some View {
        ZStack {
            // Glass background
            GlassBackgroundView(
                material: .hudWindow,
                blendingMode: .behindWindow
            )

            // Terminal content
            VStack(alignment: .leading, spacing: 0) {
                // Simple text display for now
                Text(terminalText)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
        .frame(minWidth: 600, minHeight: 400)
    }
}
```

#### 3. Update LiquidGlassTerminalApp.swift

```swift
import SwiftUI

@main
struct LiquidGlassTerminalApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 600, minHeight: 400)
        }
        .windowStyle(.hiddenTitleBar)  // Cleaner look
        .commands {
            // Add custom menu commands later
        }
    }
}
```

#### 4. Run the App

Press `Cmd + R` to build and run. You should see:
- A window with a glass/blur effect
- Simple text display
- Semi-transparent background showing desktop

**Troubleshooting:**
- If blur doesn't work, check System Settings > Accessibility > Display > Reduce transparency (should be OFF)
- Make sure you have a wallpaper set (blur won't show on plain backgrounds)

### Phase 1: Add PTY Support

#### 1. Create PTYController.swift

```swift
import Foundation
import Darwin

enum PTYError: Error {
    case openFailed
    case forkFailed
    case execFailed
}

class PTYController: ObservableObject {
    @Published var output: String = ""

    private var masterFD: Int32 = -1
    private var readSource: DispatchSourceRead?

    func start() throws {
        var master: Int32 = -1
        var slave: Int32 = -1
        var slavePath = [CChar](repeating: 0, count: 1024)

        // Open PTY
        guard openpty(&master, &slave, &slavePath, nil, nil) == 0 else {
            throw PTYError.openFailed
        }

        self.masterFD = master

        // Set non-blocking
        fcntl(master, F_SETFL, O_NONBLOCK)

        // Fork and exec shell
        let pid = fork()
        if pid == 0 {
            // Child process
            setsid()
            ioctl(slave, TIOCSCTTY, 0)

            dup2(slave, STDIN_FILENO)
            dup2(slave, STDOUT_FILENO)
            dup2(slave, STDERR_FILENO)

            close(master)
            if slave > 2 { close(slave) }

            // Launch shell
            let shell = getenv("SHELL") ?? "/bin/zsh"
            execl(shell, shell, nil)
            exit(1)
        } else if pid > 0 {
            // Parent process
            close(slave)
            startReading()
        } else {
            throw PTYError.forkFailed
        }
    }

    private func startReading() {
        readSource = DispatchSource.makeReadSource(
            fileDescriptor: masterFD,
            queue: .global(qos: .userInteractive)
        )

        readSource?.setEventHandler { [weak self] in
            guard let self = self else { return }

            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = Darwin.read(self.masterFD, &buffer, buffer.count)

            if bytesRead > 0 {
                let data = Data(buffer[..<bytesRead])
                if let text = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self.output += text
                    }
                }
            }
        }

        readSource?.resume()
    }

    func write(_ string: String) {
        guard let data = string.data(using: .utf8) else { return }
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

#### 2. Update ContentView to use PTY

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var pty = PTYController()

    var body: some View {
        ZStack {
            GlassBackgroundView()

            ScrollView {
                Text(pty.output)
                    .font(.system(size: 14, weight: .regular, design: .monospaced))
                    .foregroundColor(.white)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding()
            }
        }
        .onAppear {
            try? pty.start()
        }
    }
}
```

#### 3. Enable App Sandbox (if needed)

In your project settings:
- Go to "Signing & Capabilities"
- Add "App Sandbox" capability
- Enable "Incoming Connections (Server)"
- Enable "Outgoing Connections (Client)"

### Testing Your Progress

After each phase, test:

1. **Visual Test**: Does the glass effect look good?
2. **Functionality Test**: Can you see shell output?
3. **Performance Test**: Is it smooth? Check Activity Monitor

### Next Steps

Once you have Phase 0 and 1 working:

1. **Add keyboard input handling**
2. **Implement proper text rendering with Metal**
3. **Add VT100 parser for escape sequences**
4. **Implement cursor positioning**
5. **Add split panes**
6. **Add tabs**

### Common Issues

#### Issue: "App crashes on launch"
**Solution**: Check Console.app for crash logs. Common causes:
- PTY permissions
- Sandbox restrictions
- Force unwrapping nil values

#### Issue: "No blur effect visible"
**Solution**:
- Check System Settings > Accessibility > Display
- Disable "Reduce transparency"
- Ensure you have a wallpaper (not solid color)

#### Issue: "Text is hard to read"
**Solution**:
- Add text shadow: `.shadow(color: .black, radius: 2)`
- Reduce blur opacity
- Add semi-transparent background behind text

### Resources

- **Apple Developer Documentation**:
  - [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
  - [Metal Programming Guide](https://developer.apple.com/metal/)
  - [SwiftUI Documentation](https://developer.apple.com/documentation/swiftui)

- **Terminal Emulation**:
  - [VT100 Reference](https://vt100.net/)
  - [xterm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html)

- **Open Source References**:
  - [Alacritty](https://github.com/alacritty/alacritty) - GPU-accelerated terminal
  - [iTerm2](https://github.com/gnachman/iTerm2) - Feature-rich macOS terminal

### Development Tips

1. **Use Git**: Commit frequently as you add features
2. **Profile Early**: Use Instruments to catch performance issues early
3. **Test with Real Tools**: Use vim, tmux, etc. to test compatibility
4. **Iterate on Visuals**: The glass effect should enhance, not distract
5. **Get Feedback**: Show it to others and gather UX feedback

### Debugging Tips

```swift
// Add this to see what escape sequences you're receiving
func debugParser(_ data: Data) {
    let hex = data.map { String(format: "%02x", $0) }.joined(separator: " ")
    print("Received: \(hex)")

    if let text = String(data: data, encoding: .utf8) {
        print("As text: \(text.debugDescription)")
    }
}
```

### Performance Profiling

Use Xcode Instruments:
1. Product > Profile (Cmd + I)
2. Choose "Time Profiler" for CPU usage
3. Choose "Metal System Trace" for GPU usage
4. Choose "Leaks" to find memory leaks

Target metrics:
- 60 FPS minimum (16.67ms per frame)
- < 100MB memory for single terminal session
- < 30% GPU usage when idle

---

## Quick Reference

### Run App
```bash
Cmd + R
```

### Build for Release
```bash
Cmd + Shift + B
```

### Clean Build
```bash
Cmd + Shift + K
```

### Profile Performance
```bash
Cmd + I
```

### Key Files to Start With

1. **LiquidGlassTerminalApp.swift** - App entry point
2. **GlassBackgroundView.swift** - Visual effects
3. **PTYController.swift** - Shell integration
4. **ContentView.swift** - Main UI

Focus on getting these four files working first, then expand from there.

Good luck building your liquid glass terminal!
