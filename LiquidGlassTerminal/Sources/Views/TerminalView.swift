//
//  TerminalView.swift
//  LiquidGlassTerminal
//
//  Main terminal view component
//

import SwiftUI
import AppKit

/// SwiftUI view for terminal display
struct TerminalView: View {
    @ObservedObject var session: TerminalSession

    var body: some View {
        TerminalNSViewWrapper(session: session)
            .background(Color.clear)
    }
}

/// NSView wrapper for terminal rendering
struct TerminalNSViewWrapper: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(session: session)
        view.wantsLayer = true
        view.layer?.isOpaque = false
        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }
}

/// Native NSView for terminal rendering
class TerminalNSView: NSView {
    private let session: TerminalSession
    private var renderer: TerminalRenderer
    private var trackingArea: NSTrackingArea?

    // MARK: - Initialization

    init(session: TerminalSession) {
        self.session = session
        self.renderer = TerminalRenderer(
            terminalState: session.terminalState,
            font: NSFont.monospacedSystemFont(ofSize: 14, weight: .regular)
        )

        super.init(frame: .zero)

        setupView()
        setupObservers()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupView() {
        wantsLayer = true
        layer?.isOpaque = false

        // Accept first responder for keyboard input
        acceptsTouchEvents = true
    }

    private func setupObservers() {
        // Observe terminal state changes
        session.terminalState.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async {
                self?.needsDisplay = true
            }
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateTrackingAreas()

        // Resize terminal to fit view
        let newSize = renderer.terminalSize(for: bounds.size)
        if newSize != session.terminalState.size {
            Task { @MainActor in
                session.resize(to: newSize)
            }
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow],
            owner: self,
            userInfo: nil
        )

        if let trackingArea = trackingArea {
            addTrackingArea(trackingArea)
        }
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        guard let context = NSGraphicsContext.current?.cgContext else { return }

        // Clear background (transparent for glass effect)
        context.clear(bounds)

        // Render terminal
        Task { @MainActor in
            renderer.draw(in: context, rect: dirtyRect)
        }
    }

    override var isFlipped: Bool {
        return true  // Origin at top-left
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // TODO: Implement selection start
    }

    override func mouseDragged(with event: NSEvent) {
        // TODO: Implement selection drag
    }

    override func mouseUp(with event: NSEvent) {
        // TODO: Implement selection end
    }

    // MARK: - Keyboard Events

    override var acceptsFirstResponder: Bool {
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.characters else { return }

        Task {
            await session.sendInput(characters)
        }
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Handle command keys, etc.
        if event.modifierFlags.contains(.command) {
            return false  // Let system handle Cmd+C, Cmd+V, etc.
        }

        keyDown(with: event)
        return true
    }
}
