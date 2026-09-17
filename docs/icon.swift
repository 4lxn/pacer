import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let s = CGFloat(size)

// Background: deep blue → bright blue diagonal gradient (same family as the accent).
let colors = [CGColor(srgbRed: 0.05, green: 0.30, blue: 0.75, alpha: 1), CGColor(srgbRed: 0.12, green: 0.55, blue: 0.98, alpha: 1)] as CFArray
let gradient = CGGradient(colorsSpace: cs, colors: colors, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: 0), end: CGPoint(x: s, y: s), options: [])

let center = CGPoint(x: s / 2, y: s / 2)
let radius: CGFloat = 330
let width: CGFloat = 96

// Track: faint full ring.
ctx.setLineWidth(width)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22))
ctx.addArc(center: center, radius: radius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
ctx.strokePath()

// Pace so far: bright arc from 12 o'clock, clockwise, ~70 % of the way round.
let start = CGFloat.pi / 2
let sweep = 2 * CGFloat.pi * 0.70
ctx.setStrokeColor(CGColor(srgbRed: 0.94, green: 0.96, blue: 1, alpha: 1))
ctx.addArc(center: center, radius: radius, startAngle: start, endAngle: start - sweep, clockwise: true)
ctx.strokePath()

// The pacer: yellow dot with a blue core at the head of the arc.
let head = CGPoint(x: center.x + radius * cos(start - sweep), y: center.y + radius * sin(start - sweep))
ctx.setFillColor(CGColor(srgbRed: 1.0, green: 0.82, blue: 0.20, alpha: 1))
ctx.fillEllipse(in: CGRect(x: head.x - 84, y: head.y - 84, width: 168, height: 168))
ctx.setFillColor(CGColor(srgbRed: 0.05, green: 0.28, blue: 0.70, alpha: 1))
ctx.fillEllipse(in: CGRect(x: head.x - 40, y: head.y - 40, width: 80, height: 80))

let image = ctx.makeImage()!
let out = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(out as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
