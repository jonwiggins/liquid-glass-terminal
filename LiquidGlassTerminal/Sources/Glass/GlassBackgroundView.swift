//
//  GlassBackgroundView.swift
//  LiquidGlassTerminal
//
//  Liquid glass background effect using NSVisualEffectView
//

import SwiftUI
import AppKit

/// SwiftUI wrapper for NSVisualEffectView providing glass effect
struct GlassBackgroundView: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode
    var isEmphasized: Bool

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        isEmphasized: Bool = false
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.isEmphasized = isEmphasized
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = isEmphasized
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.isEmphasized = isEmphasized
    }
}

/// Glass material presets
enum GlassMaterialPreset {
    case minimal
    case standard
    case heavy
    case ultraLight

    var material: NSVisualEffectView.Material {
        switch self {
        case .minimal, .ultraLight:
            return .sidebar
        case .standard:
            return .hudWindow
        case .heavy:
            return .fullScreenUI
        }
    }

    var blendingMode: NSVisualEffectView.BlendingMode {
        return .behindWindow
    }
}

/// Animated glass effect with customizable intensity
struct AnimatedGlassView: View {
    @State private var intensity: Double = 1.0
    let preset: GlassMaterialPreset

    var body: some View {
        GlassBackgroundView(
            material: preset.material,
            blendingMode: preset.blendingMode
        )
        .opacity(intensity)
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: intensity)
    }

    func setIntensity(_ value: Double) {
        intensity = max(0.0, min(1.0, value))
    }
}
