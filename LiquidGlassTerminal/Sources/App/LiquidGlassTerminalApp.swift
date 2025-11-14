//
//  LiquidGlassTerminalApp.swift
//  LiquidGlassTerminal
//
//  Main application entry point
//

import SwiftUI

@main
struct LiquidGlassTerminalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            TerminalWindowView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Terminal") {
                    openNewTerminal()
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandGroup(after: .newItem) {
                Button("New Tab") {
                    // TODO: Implement tabs
                }
                .keyboardShortcut("t", modifiers: .command)

                Divider()

                Button("Split Horizontally") {
                    // TODO: Implement split panes
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("Split Vertically") {
                    // TODO: Implement split panes
                }
                .keyboardShortcut("d", modifiers: .command)
            }

            CommandGroup(after: .textEditing) {
                Button("Clear Terminal") {
                    // TODO: Get active session and clear
                }
                .keyboardShortcut("k", modifiers: .command)
            }
        }
    }

    private func openNewTerminal() {
        NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
    }
}

/// Application delegate for app-wide configuration
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Configure window appearance
        configureAppearance()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        return true
    }

    private func configureAppearance() {
        // Ensure transparency is enabled
        if let window = NSApp.windows.first {
            window.backgroundColor = .clear
            window.isOpaque = false
            window.titlebarAppearsTransparent = true
        }
    }
}
