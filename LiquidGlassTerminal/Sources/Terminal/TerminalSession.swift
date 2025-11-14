//
//  TerminalSession.swift
//  LiquidGlassTerminal
//
//  Coordinates terminal state, PTY, and parser
//

import Foundation
import Combine

/// Manages a complete terminal session
@MainActor
class TerminalSession: ObservableObject {
    // MARK: - Published Properties

    @Published private(set) var isRunning: Bool = false
    @Published private(set) var title: String = "Terminal"

    // MARK: - Components

    let terminalState: TerminalState
    private let pty: PTYController
    private let parser: VT100Parser

    // MARK: - Cancellables

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(
        rows: Int = 24,
        cols: Int = 80,
        shell: String? = nil,
        workingDirectory: String? = nil
    ) {
        self.terminalState = TerminalState(size: TerminalSize(rows: rows, cols: cols))
        self.pty = PTYController(
            shellPath: shell,
            workingDirectory: workingDirectory
        )
        self.parser = VT100Parser()

        setupPTYCallbacks()
    }

    // MARK: - Setup

    private func setupPTYCallbacks() {
        // Handle data from PTY
        pty.onDataReceived = { [weak self] data in
            guard let self = self else { return }

            Task { @MainActor in
                // Parse and update terminal state
                self.parser.parse(data, terminal: self.terminalState)
            }
        }

        // Handle process exit
        pty.onProcessExit = { [weak self] exitCode in
            guard let self = self else { return }

            Task { @MainActor in
                self.isRunning = false

                if exitCode != 0 {
                    self.title = "Terminal (Exit: \(exitCode))"
                }
            }
        }
    }

    // MARK: - Lifecycle

    func start() throws {
        guard !isRunning else { return }

        try pty.start(
            rows: terminalState.size.rows,
            cols: terminalState.size.cols
        )

        isRunning = true
    }

    func stop() {
        guard isRunning else { return }

        pty.stop()
        isRunning = false
    }

    // MARK: - Input

    func sendInput(_ string: String) async {
        guard isRunning else { return }

        do {
            // Handle special keys
            var output = string

            // Convert newline to carriage return for terminals
            output = output.replacingOccurrences(of: "\n", with: "\r")

            try pty.write(output)
        } catch {
            print("Failed to send input: \(error)")
        }
    }

    func sendBytes(_ data: Data) async {
        guard isRunning else { return }

        do {
            try pty.write(data)
        } catch {
            print("Failed to send bytes: \(error)")
        }
    }

    // MARK: - Terminal Control

    func resize(to newSize: TerminalSize) {
        guard newSize != terminalState.size else { return }

        terminalState.resize(to: newSize)

        if isRunning {
            do {
                try pty.resize(rows: newSize.rows, cols: newSize.cols)
            } catch {
                print("Failed to resize PTY: \(error)")
            }
        }
    }

    func clear() {
        terminalState.eraseInDisplay(mode: 2)
        terminalState.moveCursor(to: .zero())
    }

    // MARK: - Text Operations

    func getSelectedText(selection: TerminalSelection) -> String {
        return terminalState.getText(in: selection)
    }

    // MARK: - Cleanup

    deinit {
        stop()
    }
}
