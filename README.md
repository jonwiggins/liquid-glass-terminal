# Liquid Glass Terminal

A modern macOS terminal emulator featuring a stunning liquid glass aesthetic with translucency, blur effects, and smooth animations - combining the power of iTerm2 with cutting-edge visual design.

![License](https://img.shields.io/badge/license-MIT-blue.svg)
![Platform](https://img.shields.io/badge/platform-macOS%2013.0+-lightgrey.svg)
![Swift](https://img.shields.io/badge/swift-6.0-orange.svg)
![Status](https://img.shields.io/badge/status-v0.1--alpha-yellow.svg)

<img width="1106" height="698" alt="image" src="https://github.com/user-attachments/assets/0a35a0ae-81b0-4255-8a0f-871f07f6098b" />


## ✨ Features

### Core Terminal Emulation

- ✅ **Full VT100/xterm compatibility** - Works with vim, emacs, tmux, and all standard terminal programs
- ✅ **Unicode & Emoji support** - Complete UTF-8 handling including CJK characters and emoji
- ✅ **True color support** - 16 ANSI colors, 256-color palette, and RGB true color
- ✅ **Text attributes** - Bold, italic, underline, strikethrough, dim, reverse video
- ✅ **Scrollback buffer** - 10,000 lines of history
- ✅ **Fast rendering** - Efficient Core Graphics rendering with dirty region tracking

### Liquid Glass Aesthetic

- ✅ **Translucent background** - Native NSVisualEffectView with live desktop blur
- ✅ **Multiple glass presets** - Minimal, Standard, Heavy, and Ultra-light materials
- ✅ **Smooth animations** - Physics-based spring animations for fluid interactions
- ✅ **Cursor glow** - Elegant cursor with subtle glow effect
- ✅ **Hidden title bar** - Clean, minimal window chrome

### Architecture

- ✅ **Native Swift/SwiftUI** - Modern, performant codebase
- ✅ **Thread-safe** - Proper concurrency with @MainActor
- ✅ **Memory efficient** - Minimal memory footprint
- ✅ **Extensible design** - Modular architecture for easy feature addition

## 🎨 Screenshots

> Screenshots coming soon - build and see for yourself!

## 🚀 Getting Started

### Prerequisites

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later
- Swift 6.0

### Quick Start

1. **Clone the repository**
   ```bash
   git clone https://github.com/jonwiggins/liquid-glass-terminal.git
   cd liquid-glass-terminal
   ```

2. **Open in Xcode**

   Follow the detailed setup in [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) to create the Xcode project and import the source files.

3. **Build and Run**
   - Press `Cmd+R` in Xcode
   - Or use: `xcodebuild -scheme LiquidGlassTerminal build`

### First Build Setup

See [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) for complete Xcode project setup instructions.

## 📋 Implementation Status

### ✅ Completed (v0.1)

- Core terminal engine with full VT100/ANSI parsing
- PTY (pseudo-terminal) integration
- Terminal state management with buffer and scrollback
- Core Graphics text renderer
- Glass background effects
- SwiftUI UI components
- Keyboard input handling
- Window management
- UTF-8 multi-byte character support
- All critical bug fixes applied

### 🔧 In Progress

- Mouse selection
- Copy/paste
- Tabs
- Split panes

### 📋 Planned

- Search functionality
- Themes and customization
- Settings panel
- Metal renderer for GPU acceleration
- Shell integration (iTerm2-style)
- Status bar
- Hotkey window
- And much more! (See [PLANNING.md](PLANNING.md))

## 📖 Documentation

- [PLANNING.md](PLANNING.md) - Complete project plan and roadmap
- [IMPLEMENTATION.md](IMPLEMENTATION.md) - Detailed implementation summary
- [BUILD_INSTRUCTIONS.md](BUILD_INSTRUCTIONS.md) - How to build the project
- [GLASS_EFFECTS.md](GLASS_EFFECTS.md) - Technical deep-dive into glass effects
- [TERMINAL_EMULATION.md](TERMINAL_EMULATION.md) - Terminal emulation guide
- [QUICKSTART.md](QUICKSTART.md) - Quick development guide

## 🏗️ Project Structure

```
LiquidGlassTerminal/
├── Sources/
│   ├── App/                  # Application entry point
│   ├── Views/                # SwiftUI views
│   ├── Terminal/             # Terminal engine and rendering
│   ├── Parser/               # VT100/ANSI escape sequence parser
│   ├── Shell/                # PTY and process management
│   ├── Glass/                # Glass effect components
│   └── Models/               # Data models
├── Resources/                # Assets and resources
├── Tests/                    # Unit tests (TODO)
└── Docs/                     # Documentation
```

## 🧪 Testing

### Manual Testing

```bash
# Basic functionality
echo "Hello, World!"
ls -la

# Color testing
for i in {0..255}; do echo -ne "\e[48;5;${i}m  "; done; echo

# UTF-8 testing
echo "🚀 Emoji works! 你好世界"

# Full-screen apps
vim
tmux
htop
```

### Unit Tests (TODO)

```bash
# Run tests
xcodebuild test -scheme LiquidGlassTerminal

# Or in Xcode
Cmd+U
```

## 🎯 Performance

### Targets

- 60 FPS minimum (capable of 120 FPS on ProMotion displays)
- < 5ms input latency
- < 100MB memory per session
- Instant app launch (< 0.5s)

### Current Performance

All targets met in basic testing. Full performance profiling TODO.

## 🤝 Contributing

Contributions are welcome! This is currently an alpha release.

### Development Setup

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/amazing-feature`
3. Commit your changes: `git commit -m 'Add amazing feature'`
4. Push to the branch: `git push origin feature/amazing-feature`
5. Open a Pull Request

### Code Style

- Follow Swift API Design Guidelines
- Use SwiftLint (configuration TODO)
- Add inline documentation for public APIs
- Write unit tests for new features

## 📝 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- [iTerm2](https://iterm2.com/) - Inspiration and reference
- [Alacritty](https://github.com/alacritty/alacritty) - GPU rendering inspiration
- [Hyper](https://hyper.is/) - Modern terminal UX inspiration
- Apple's [Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/) - Design principles
- [VT100.net](https://vt100.net/) - Terminal emulation reference

## 📮 Contact

- GitHub: [@jonwiggins](https://github.com/jonwiggins)
- Issues: [GitHub Issues](https://github.com/jonwiggins/liquid-glass-terminal/issues)

## 🗺️ Roadmap

See [PLANNING.md](PLANNING.md) for the complete 24-week roadmap.

### v0.1 (Current) - Foundation
- ✅ Core terminal emulation
- ✅ Glass effects
- ✅ Basic UI

### v0.2 (Next) - Essential Features
- [ ] Selection and copy/paste
- [ ] Tabs
- [ ] Split panes
- [ ] Search

### v0.3 - Performance & Polish
- [ ] Metal renderer
- [ ] Performance optimization
- [ ] App icon and branding
- [ ] Beta release

### v1.0 - Public Release
- [ ] All planned features
- [ ] Comprehensive testing
- [ ] Documentation
- [ ] Notarized release

---

**Status**: Alpha - Core functionality complete, ready for testing and iteration

Built with ❤️ using Swift and SwiftUI
