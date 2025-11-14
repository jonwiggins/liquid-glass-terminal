//
//  TerminalView.swift
//  LiquidGlassTerminal
//
//  Main terminal view component
//

import SwiftUI
import AppKit
import Combine

/// SwiftUI view for terminal display
struct TerminalView: View {
    @ObservedObject var session: TerminalSession
    @FocusState private var isFocused: Bool

    var body: some View {
        TerminalNSViewWrapper(session: session)
            .background(Color.clear)
            .onAppear {
                // Try to claim focus when view appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isFocused = true
                }
            }
    }
}

/// NSView wrapper for terminal rendering
struct TerminalNSViewWrapper: NSViewRepresentable {
    let session: TerminalSession

    func makeNSView(context: Context) -> TerminalNSView {
        let view = TerminalNSView(session: session)
        view.wantsLayer = true
        view.layer?.isOpaque = false

        // Ensure the view can receive keyboard events
        DispatchQueue.main.async {
            view.window?.makeFirstResponder(view)
        }

        return view
    }

    func updateNSView(_ nsView: TerminalNSView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)

        // Re-assert first responder status on update
        DispatchQueue.main.async {
            if nsView.window?.firstResponder != nsView {
                print("🔄 View lost first responder, reclaiming...")
                nsView.window?.makeFirstResponder(nsView)
            }
        }
    }
}

/// Native NSView for terminal rendering
class TerminalNSView: NSView {
    private let session: TerminalSession
    private var renderer: TerminalRenderer
    private var trackingArea: NSTrackingArea?
    private var cancellables = Set<AnyCancellable>()

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

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        // Automatically become first responder when added to window
        DispatchQueue.main.async { [weak self] in
            guard let self = self, let window = self.window else { return }

            // Make window key and bring to front
            window.makeKeyAndOrderFront(nil)

            // Make this view first responder
            let success = window.makeFirstResponder(self)
            print("🎯 makeFirstResponder success: \(success)")
            print("🎯 Current first responder: \(String(describing: window.firstResponder))")
            print("🎯 Window is key: \(window.isKeyWindow)")
        }
    }

    override func becomeFirstResponder() -> Bool {
        print("🎯 becomeFirstResponder called")
        return super.becomeFirstResponder()
    }

    private func setupObservers() {
        // Observe terminal state changes
        session.terminalState.objectWillChange
            .sink { [weak self] _ in
                print("🔔 TerminalState changed, triggering redraw")
                DispatchQueue.main.async {
                    self?.needsDisplay = true
                    print("🔔 needsDisplay = true")
                }
            }
            .store(in: &cancellables)

        // Also observe the Published properties directly
        session.terminalState.$size
            .sink { [weak self] newSize in
                print("🔔 Terminal size changed: \(newSize)")
                DispatchQueue.main.async {
                    self?.needsDisplay = true
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        updateTrackingAreas()

        // Resize terminal to fit view
        let newSize = renderer.terminalSize(for: bounds.size)
        Task { @MainActor in
            if newSize != session.terminalState.size {
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
        print("🎨 draw() called, dirtyRect: \(dirtyRect)")

        guard let context = NSGraphicsContext.current?.cgContext else {
            print("🎨 No graphics context!")
            return
        }

        // Clear background (transparent for glass effect)
        context.clear(bounds)

        // Render terminal - must be synchronous in draw method
        MainActor.assumeIsolated {
            renderer.draw(in: context, rect: dirtyRect)
        }
        print("🎨 draw() complete")
    }

    override var isFlipped: Bool {
        return true  // Origin at top-left
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        print("🖱️ mouseDown - making first responder")
        window?.makeKeyAndOrderFront(nil)
        let success = window?.makeFirstResponder(self)
        print("🖱️ makeFirstResponder success: \(success ?? false)")
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
        print("🎯 acceptsFirstResponder called, returning true")
        return true
    }

    override func keyDown(with event: NSEvent) {
        print("⌨️ keyDown received! characters: \(event.characters ?? "nil")")
        guard let characters = event.characters else {
            print("⌨️ No characters in event")
            return
        }

        print("⌨️ Sending '\(characters)' to terminal")
        Task {
            await session.sendInput(characters)
        }
    }

    override var canBecomeKeyView: Bool {
        return true
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
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
