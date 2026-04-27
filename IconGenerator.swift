import SwiftUI

// App Icon Generator
struct AppIconView: View {
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [
                    Color(NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1.0)),
                    Color(NSColor(red: 0.88, green: 0.84, blue: 0.78, alpha: 1.0))
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Inner glow
            RoundedRectangle(cornerRadius: 22)
                .stroke(Color.white.opacity(0.5), lineWidth: 2)
                .padding(2)
            
            // Sparkles icon
            Image(systemName: "sparkles")
                .font(.system(size: 140, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            Color(NSColor(red: 0.42, green: 0.36, blue: 0.30, alpha: 1.0)),
                            Color(NSColor(red: 0.52, green: 0.46, blue: 0.40, alpha: 1.0))
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        }
        .frame(width: 1024, height: 1024)
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

// Run this to generate the icon
import AppKit

let view = AppIconView()
let controller = NSHostingController(rootView: view)
controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 1024)

// Render to image
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let context = NSGraphicsContext(bitmapImageRep: bitmap)
NSGraphicsContext.current = context
controller.view.layer?.render(in: context!.cgContext)

// Save
let data = bitmap.representation(using: .png, properties: [:])!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try! data.write(to: url)
print("Icon saved to: \(url.path)")
