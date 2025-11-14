# Liquid Glass Effects - Technical Implementation

## Overview
This document details the technical implementation of the liquid glass aesthetic for the terminal app.

## Core Visual Principles

### 1. Glassmorphism Stack
```
┌─────────────────────────────────────┐
│  Text Layer (100% opaque)           │  ← Crisp, high-contrast
├─────────────────────────────────────┤
│  Tint Layer (10-30% opacity)        │  ← Subtle color overlay
├─────────────────────────────────────┤
│  Blur Layer (Background blur)       │  ← Gaussian/Box blur
├─────────────────────────────────────┤
│  Desktop/Wallpaper                  │  ← System background
└─────────────────────────────────────┘
```

### 2. Material Properties

#### Glass Material
```swift
struct GlassMaterial {
    var blurRadius: CGFloat = 80.0       // Blur amount
    var saturation: CGFloat = 1.8        // Color saturation boost
    var tintColor: Color = .black        // Base tint
    var tintOpacity: CGFloat = 0.3       // Tint transparency
    var brightness: CGFloat = 1.1        // Brightness adjustment
    var vibrancy: Bool = true            // Use system vibrancy
}
```

## Implementation Approaches

### Approach 1: NSVisualEffectView (Recommended for Start)

**Pros:**
- Native macOS API
- Hardware accelerated
- Automatic system integration
- Handles window movement efficiently
- Respects system preferences

**Code Example:**
```swift
import AppKit

class GlassBackgroundView: NSVisualEffectView {
    override init(frame: NSRect) {
        super.init(frame: frame)

        // Configure glass effect
        self.material = .hudWindow          // Or .popover, .sidebar
        self.blendingMode = .behindWindow
        self.state = .active

        // For more custom look
        self.material = .fullScreenUI

        // Optional: Add subtle tint
        self.wantsLayer = true
        self.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.2).cgColor
    }
}
```

**Available Materials:**
- `.hudWindow` - Dark, high contrast
- `.popover` - Light, subtle
- `.sidebar` - System sidebar appearance
- `.menu` - Menu-like appearance
- `.fullScreenUI` - Fullscreen UI chrome
- `.underWindowBackground` - Behind window content

### Approach 2: Custom Metal Shaders (For Advanced Effects)

**Use Cases:**
- Custom blur algorithms
- Animated glass effects
- Unique visual treatments
- Performance optimization

**Metal Shader Example:**
```metal
// GaussianBlur.metal
#include <metal_stdlib>
using namespace metal;

kernel void gaussianBlur(
    texture2d<float, access::read> inTexture [[texture(0)]],
    texture2d<float, access::write> outTexture [[texture(1)]],
    constant float &blurRadius [[buffer(0)]],
    uint2 gid [[thread_position_in_grid]]
) {
    float4 sum = float4(0.0);
    float totalWeight = 0.0;

    int radius = int(blurRadius);

    for (int y = -radius; y <= radius; y++) {
        for (int x = -radius; x <= radius; x++) {
            uint2 samplePos = uint2(int2(gid) + int2(x, y));

            float dist = length(float2(x, y));
            float weight = exp(-dist * dist / (2.0 * blurRadius * blurRadius));

            float4 sample = inTexture.read(samplePos);
            sum += sample * weight;
            totalWeight += weight;
        }
    }

    outTexture.write(sum / totalWeight, gid);
}
```

**Swift Integration:**
```swift
import Metal
import MetalKit

class GlassRenderer {
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let pipelineState: MTLComputePipelineState

    func applyGlassEffect(to texture: MTLTexture) -> MTLTexture {
        let commandBuffer = commandQueue.makeCommandBuffer()!
        let encoder = commandBuffer.makeComputeCommandEncoder()!

        encoder.setComputePipelineState(pipelineState)
        encoder.setTexture(texture, index: 0)
        encoder.setTexture(outputTexture, index: 1)

        // Dispatch threads
        let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
        let threadGroups = MTLSize(
            width: (texture.width + 15) / 16,
            height: (texture.height + 15) / 16,
            depth: 1
        )

        encoder.dispatchThreadgroups(threadGroups,
                                     threadsPerThreadgroup: threadGroupSize)
        encoder.endEncoding()
        commandBuffer.commit()

        return outputTexture
    }
}
```

### Approach 3: Core Image Filters (Quick Prototyping)

**Use for:**
- Rapid prototyping
- Testing different effects
- Non-performance-critical areas

```swift
import CoreImage

class GlassEffect {
    func applyGlass(to image: CIImage) -> CIImage? {
        // Blur
        let blurred = image.applyingFilter("CIGaussianBlur", parameters: [
            "inputRadius": 80
        ])

        // Saturation boost
        let saturated = blurred.applyingFilter("CIColorControls", parameters: [
            "inputSaturation": 1.8,
            "inputBrightness": 0.1
        ])

        // Tint overlay
        let tint = CIColor(red: 0, green: 0, blue: 0, alpha: 0.3)
        let tinted = saturated.applyingFilter("CIConstantColorGenerator", parameters: [
            "inputColor": tint
        ]).composited(over: saturated)

        return tinted
    }
}
```

## Animation System

### Smooth Transitions

**SwiftUI Animations:**
```swift
struct GlassWindow: View {
    @State private var blurIntensity: CGFloat = 80
    @State private var opacity: CGFloat = 0.3

    var body: some View {
        ZStack {
            GlassBackgroundView()
                .blur(radius: blurIntensity)
                .opacity(opacity)
                .animation(.spring(response: 0.6, dampingFraction: 0.8), value: blurIntensity)
        }
    }
}
```

### Physics-Based Animations

**Spring Animations:**
```swift
// Responsive spring for quick interactions
Animation.spring(response: 0.3, dampingFraction: 0.7)

// Smooth spring for morphing transitions
Animation.spring(response: 0.6, dampingFraction: 0.8)

// Bouncy spring for playful effects
Animation.spring(response: 0.5, dampingFraction: 0.6)
```

**Fluid Morphing:**
```swift
// Tab switching animation
.matchedGeometryEffect(id: "glass-background", in: namespace)
.animation(.spring(response: 0.5, dampingFraction: 0.75))
```

## Dynamic Effects

### 1. Adaptive Blur Based on Content

```swift
class AdaptiveGlassController {
    func calculateOptimalBlur(for terminalContent: TerminalBuffer) -> CGFloat {
        // Analyze background complexity
        let backgroundComplexity = analyzeComplexity()

        // Analyze text density
        let textDensity = calculateTextDensity(terminalContent)

        // More blur for complex backgrounds
        // Less blur for sparse text (better visibility)
        let blurRadius = baseBlur * backgroundComplexity * (1.0 - textDensity * 0.3)

        return blurRadius
    }

    func analyzeComplexity() -> CGFloat {
        // Sample background pixels
        // Calculate variance/edge detection
        // Return 0.5-1.5 multiplier
        return 1.0
    }
}
```

### 2. Context-Aware Opacity

```swift
func calculateReadableOpacity(backgroundColor: NSColor, textColor: NSColor) -> CGFloat {
    let contrast = calculateContrast(backgroundColor, textColor)

    // Reduce glass opacity if contrast is poor
    if contrast < 4.5 { // WCAG AA threshold
        return 0.1 // More opaque for better readability
    }

    return 0.3 // Standard glass opacity
}
```

### 3. Glow Effects for Cursor and Selection

**Cursor Glow:**
```metal
// CursorGlow.metal
fragment float4 cursorFragment(
    VertexOut in [[stage_in]],
    constant float &time [[buffer(0)]]
) {
    float2 center = float2(0.5, 0.5);
    float dist = distance(in.texCoord, center);

    // Pulsing glow
    float pulse = 0.5 + 0.5 * sin(time * 2.0);
    float glow = exp(-dist * 8.0) * pulse;

    float4 cursorColor = float4(0.3, 0.6, 1.0, 1.0); // Blue
    return cursorColor * glow;
}
```

**Selection Glass Effect:**
```swift
struct SelectionOverlay: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(Color.blue.opacity(0.3))
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.blue.opacity(0.5), lineWidth: 1)
            )
    }
}
```

## Performance Optimization

### 1. Blur Optimization

**Strategy:**
- Use downsampled texture for blur (1/4 resolution)
- Cache blurred background when static
- Reduce blur quality during scrolling
- Use box blur instead of Gaussian for speed

```swift
class OptimizedBlur {
    var isAnimating = false
    var cachedBlur: MTLTexture?

    func blur(_ texture: MTLTexture) -> MTLTexture {
        // Use cache if not animating
        if !isAnimating, let cached = cachedBlur {
            return cached
        }

        // Downsample for blur
        let downsampled = downsample(texture, factor: 4)

        // Fast box blur instead of Gaussian
        let blurred = isAnimating ?
            fastBoxBlur(downsampled) :
            qualityGaussianBlur(downsampled)

        // Upsample back
        let result = upsample(blurred)

        if !isAnimating {
            cachedBlur = result
        }

        return result
    }
}
```

### 2. Smart Invalidation

```swift
class GlassInvalidationManager {
    func shouldUpdateBlur(event: WindowEvent) -> Bool {
        switch event {
        case .moved:
            return true  // Background changed
        case .resized:
            return true  // Need new blur texture
        case .terminalOutput:
            return false // Terminal content doesn't affect blur
        case .focused:
            return true  // May change vibrancy
        default:
            return false
        }
    }
}
```

### 3. Texture Pooling

```swift
class TexturePool {
    private var pool: [MTLTexture] = []

    func acquire(size: MTLSize) -> MTLTexture {
        // Reuse existing texture if available
        if let texture = pool.first(where: {
            $0.width == size.width && $0.height == size.height
        }) {
            return texture
        }

        // Create new texture
        return createTexture(size)
    }

    func release(_ texture: MTLTexture) {
        pool.append(texture)
    }
}
```

## Visual Effect Presets

### Preset 1: Minimal Glass
```swift
GlassMaterial(
    blurRadius: 40,
    saturation: 1.2,
    tintColor: .black,
    tintOpacity: 0.15,
    brightness: 1.05,
    vibrancy: true
)
```

### Preset 2: Standard Glass (Default)
```swift
GlassMaterial(
    blurRadius: 80,
    saturation: 1.8,
    tintColor: .black,
    tintOpacity: 0.3,
    brightness: 1.1,
    vibrancy: true
)
```

### Preset 3: Heavy Glass
```swift
GlassMaterial(
    blurRadius: 120,
    saturation: 2.0,
    tintColor: .black,
    tintOpacity: 0.45,
    brightness: 1.15,
    vibrancy: true
)
```

### Preset 4: Colored Glass
```swift
GlassMaterial(
    blurRadius: 80,
    saturation: 2.2,
    tintColor: .blue,  // or .purple, .green, etc.
    tintOpacity: 0.2,
    brightness: 1.2,
    vibrancy: true
)
```

## Text Rendering Over Glass

### Challenge: Readability

**Solution 1: Text Shadow/Glow**
```swift
Text("Terminal Output")
    .shadow(color: .black.opacity(0.8), radius: 2, x: 0, y: 0)
    .shadow(color: .black.opacity(0.4), radius: 8, x: 0, y: 0)
```

**Solution 2: Subtle Background**
```swift
// Add semi-transparent background behind text area
Rectangle()
    .fill(Color.black.opacity(0.1))
    .background(.ultraThinMaterial)
```

**Solution 3: Contrast Boost**
```metal
// Boost text contrast in shader
fragment float4 textFragment(
    VertexOut in [[stage_in]],
    texture2d<float> glyphTexture [[texture(0)]]
) {
    float alpha = glyphTexture.sample(sampler, in.texCoord).r;

    // Boost alpha for better contrast
    alpha = pow(alpha, 0.8);

    float4 textColor = float4(1.0, 1.0, 1.0, alpha);
    return textColor;
}
```

## Testing & Iteration

### Visual Tests
1. **Wallpaper Stress Test**: Test with various wallpapers (light, dark, colorful, busy)
2. **Content Test**: Ensure readability with different text densities
3. **Animation Test**: Verify smooth 60 FPS during all animations
4. **Edge Cases**: Test with extreme blur values, opacity settings

### Performance Tests
1. **FPS Monitoring**: Maintain 60 FPS minimum, 120 FPS on ProMotion
2. **GPU Usage**: Keep below 30% for static content
3. **Memory**: Monitor texture memory usage
4. **Battery Impact**: Test power consumption vs. standard terminal

### User Experience Tests
1. **Readability**: WCAG contrast ratios
2. **Eye Strain**: Long-term usage comfort
3. **Aesthetics**: Subjective beauty across different setups
4. **Distraction**: Ensure glass doesn't distract from content

## References

- [Apple Human Interface Guidelines - Materials](https://developer.apple.com/design/human-interface-guidelines/materials)
- [NSVisualEffectView Documentation](https://developer.apple.com/documentation/appkit/nsvisualeffectview)
- [Metal Shading Language Specification](https://developer.apple.com/metal/Metal-Shading-Language-Specification.pdf)
- [Core Image Filter Reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/)
