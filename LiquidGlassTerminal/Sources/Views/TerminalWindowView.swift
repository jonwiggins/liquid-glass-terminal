//
//  TerminalWindowView.swift
//  LiquidGlassTerminal
//
//  Main window view with glass effect
//

import SwiftUI

/// Main terminal window with liquid glass effect
struct TerminalWindowView: View {
    @StateObject private var session: TerminalSession
    @State private var showingSettings = false

    init(session: TerminalSession? = nil) {
        _session = StateObject(wrappedValue: session ?? TerminalSession())
    }

    var body: some View {
        ZStack {
            // Glass background layer
            GlassBackgroundView(
                material: .underWindowBackground,
                blendingMode: .behindWindow
            )
            .opacity(0.75)
            .ignoresSafeArea()

            // Terminal content layer
            TerminalView(session: session)
                .padding(8)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            startSession()

            // Ensure app is activated when window appears
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NSApp.activate(ignoringOtherApps: true)
                print("🔥 Re-activated app from onAppear")
            }
        }
        .onDisappear {
            session.stop()
        }
    }

    private func startSession() {
        do {
            try session.start()
            print("✅ Terminal session started successfully")
        } catch {
            print("❌ Failed to start terminal session: \(error)")
            if let ptyError = error as? PTYError {
                print("   Error details: \(ptyError.localizedDescription)")
            }
        }
    }
}

/// Preview provider
struct TerminalWindowView_Previews: PreviewProvider {
    static var previews: some View {
        TerminalWindowView()
            .frame(width: 800, height: 600)
    }
}
