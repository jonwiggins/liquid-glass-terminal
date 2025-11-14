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
                material: .hudWindow,
                blendingMode: .behindWindow
            )
            .ignoresSafeArea()

            // Terminal content layer
            TerminalView(session: session)
                .padding(8)
        }
        .frame(minWidth: 600, minHeight: 400)
        .onAppear {
            startSession()
        }
        .onDisappear {
            session.stop()
        }
    }

    private func startSession() {
        do {
            try session.start()
        } catch {
            print("Failed to start terminal session: \(error)")
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
