// Renders the app icon (1024×1024): deep-blue gradient, a white rail-and-dot mark.
// Run: DEVELOPER_DIR=… swift Tools/render-icon.swift Assets.xcassets/AppIcon.appiconset/icon-1024.png
import AppKit

let size = CGSize(width: 1024, height: 1024)
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon-1024.png"
// Draw into an explicit 1024-px bitmap so the file is not doubled for Retina.
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 3,
                           hasAlpha: false, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
guard let ctx = NSGraphicsContext.current?.cgContext else { exit(1) }

let colors = [NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.55, alpha: 1).cgColor,
              NSColor(calibratedRed: 0.10, green: 0.45, blue: 0.95, alpha: 1).cgColor] as CFArray
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: size.width, y: size.height), options: [])

// Three horizontal "rails" (blocks of the day) and a filled dot on the middle one = "now".
ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
ctx.setLineCap(.round)
ctx.setLineWidth(70)
let ys: [CGFloat] = [312, 512, 712]
let widths: [CGFloat] = [520, 640, 440]
for (y, w) in zip(ys, widths) {
    ctx.move(to: CGPoint(x: 192, y: y))
    ctx.addLine(to: CGPoint(x: 192 + w, y: y))
    ctx.strokePath()
}
ctx.setFillColor(NSColor(calibratedRed: 1.0, green: 0.80, blue: 0.20, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: 192 + 640 - 60, y: 512 - 60, width: 120, height: 120))
ctx.setFillColor(NSColor(calibratedRed: 0.05, green: 0.20, blue: 0.55, alpha: 1).cgColor)
ctx.fillEllipse(in: CGRect(x: 192 + 640 - 28, y: 512 - 28, width: 56, height: 56))

NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
// App Store icons must not have an alpha channel. Strip it afterwards:
//   sips -s format jpeg -s formatOptions 100 icon-1024.png --out /tmp/icon.jpg
//   sips -s format png /tmp/icon.jpg --out Assets.xcassets/AppIcon.appiconset/icon-1024.png
