# Build Instructions for Liquid Glass Terminal

## Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 6.0

## Method 1: Xcode Project Setup

### Step 1: Create Xcode Project

1. Open Xcode
2. File > New > Project
3. Select "macOS" > "App"
4. Configure:
   - Product Name: `LiquidGlassTerminal`
   - Team: Your development team
   - Organization Identifier: `com.yourname`
   - Interface: `SwiftUI`
   - Language: `Swift`
   - Use Core Data: **No**
   - Include Tests: **Yes**

### Step 2: Add Source Files

1. Delete the default `ContentView.swift` created by Xcode
2. Add all source files from `LiquidGlassTerminal/Sources/` to your project:
   - Drag the entire `Sources` folder into the project navigator
   - Ensure "Copy items if needed" is **checked**
   - Ensure "Create groups" is selected
   - Add to target: `LiquidGlassTerminal`

### Step 3: Configure Project Settings

1. Select project in navigator
2. Go to "Signing & Capabilities"
   - Disable App Sandbox (or configure for terminal access)
   - Enable "Incoming Connections (Server)" if using sandbox
   - Enable "Outgoing Connections (Client)" if using sandbox

3. Go to "Build Settings"
   - Deployment Target: macOS 13.0
   - Swift Language Version: Swift 6

4. Go to "Info"
   - Add `LSApplicationCategoryType`: `public.app-category.developer-tools`

### Step 4: Build and Run

```bash
# Via Xcode: Press Cmd+R

# Via command line:
xcodebuild -scheme LiquidGlassTerminal -configuration Debug build
```

## Method 2: Swift Package Manager (Experimental)

> Note: SPM for macOS apps is less common. Xcode project recommended.

```bash
cd LiquidGlassTerminal

# Build
swift build

# Run
swift run
```

## Common Build Issues

### Issue 1: "Cannot find LiquidGlassTerminalApp in scope"

**Solution**: Ensure `@main` is present in `LiquidGlassTerminalApp.swift`

### Issue 2: "No such module 'Darwin'"

**Solution**: Set deployment target to macOS 13.0+

### Issue 3: "'closefrom' is unavailable"

**Solution**: Already handled with `#if os(macOS)` check

### Issue 4: Crash on launch with PTY error

**Solution**:
- Check sandbox settings
- Ensure shell path is valid (`/bin/zsh` or `/bin/bash`)
- Verify app has permission to spawn processes

## Development Tips

### Live Preview in Xcode

SwiftUI previews may not work perfectly for PTY components. For best results:
1. Build and run the full app
2. Use breakpoints for debugging
3. Check console output for PTY/parser issues

### Debugging Terminal Emulation

Add this to see raw escape sequences:

```swift
// In VT100Parser.swift, parse() method:
print("Byte: \(String(format: "%02X", byte)) Char: \(Character(UnicodeScalar(byte)))")
```

### Performance Profiling

1. Product > Profile (Cmd+I)
2. Choose "Time Profiler"
3. Run terminal with heavy output: `cat large_file.txt`
4. Look for hotspots in rendering or parsing

## Building for Release

### Create Archive

1. Product > Archive
2. Distribute App > Copy App
3. Sign with Developer ID (for distribution outside App Store)

### Notarize (for distribution)

```bash
# Create app bundle
xcodebuild archive -scheme LiquidGlassTerminal \
  -archivePath LiquidGlassTerminal.xcarchive

# Notarize
xcrun notarytool submit LiquidGlassTerminal.xcarchive \
  --keychain-profile "AC_PASSWORD"

# Staple
xcrun stapler staple LiquidGlassTerminal.app
```

## Testing

### Manual Testing Checklist

- [ ] App launches without crash
- [ ] Glass effect is visible
- [ ] Terminal displays shell prompt
- [ ] Keyboard input works
- [ ] Text output renders correctly
- [ ] Colors (ANSI, 256, RGB) display properly
- [ ] Scrollback works
- [ ] Window resize updates terminal size
- [ ] Cursor is visible and positioned correctly
- [ ] UTF-8 characters (emoji, CJK) render
- [ ] Vim/Emacs/tmux work correctly

### Automated Tests

Run unit tests:

```bash
# Via Xcode
Cmd+U

# Via command line
xcodebuild test -scheme LiquidGlassTerminal
```

## Next Steps After Building

1. **Customize glass effect**: Edit `GlassBackgroundView.swift`
2. **Change font**: Edit `TerminalRenderer.swift`, modify font initialization
3. **Add themes**: Create color scheme system
4. **Implement tabs**: Add tab bar UI component
5. **Add splits**: Implement pane splitting
6. **Shell integration**: Add iTerm2-style shell integration

## Getting Help

Common issues and solutions documented in:
- `PLANNING.md` - Architecture decisions
- `TERMINAL_EMULATION.md` - Parser details
- `GLASS_EFFECTS.md` - Visual effects guide

## File Structure

```
LiquidGlassTerminal/
├── Sources/
│   ├── App/
│   │   └── LiquidGlassTerminalApp.swift  ← Entry point
│   ├── Views/
│   │   ├── TerminalView.swift            ← Main terminal view
│   │   └── TerminalWindowView.swift      ← Window with glass
│   ├── Terminal/
│   │   ├── TerminalState.swift           ← Buffer management
│   │   ├── TerminalSession.swift         ← Session coordinator
│   │   └── TerminalRenderer.swift        ← Drawing logic
│   ├── Parser/
│   │   └── VT100Parser.swift             ← Escape sequences
│   ├── Shell/
│   │   └── PTYController.swift           ← PTY/process
│   ├── Glass/
│   │   └── GlassBackgroundView.swift     ← Glass effects
│   └── Models/
│       ├── TerminalColor.swift           ← Color system
│       ├── TerminalCell.swift            ← Cell attributes
│       └── TerminalSize.swift            ← Dimensions
├── Resources/
│   └── Assets/                           ← App icon, etc.
├── Info.plist                            ← App metadata
└── Tests/                                ← Unit tests
```
