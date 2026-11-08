import AppKit
import Foundation

let output = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Design"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let base = NSBezierPath(roundedRect: NSRect(x: 45, y: 45, width: 934, height: 934), xRadius: 215, yRadius: 215)
NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.37, blue: 0.29, alpha: 1), ending: NSColor(calibratedRed: 0.055, green: 0.13, blue: 0.10, alpha: 1))!.draw(in: base, angle: -65)
NSColor.white.withAlphaComponent(0.18).setStroke(); base.lineWidth = 2; base.stroke()

func photo(x: CGFloat, y: CGFloat, angle: CGFloat, front: Bool) {
    NSGraphicsContext.saveGraphicsState()
    let transform = AffineTransform(translationByX: x, byY: y)
    (transform as NSAffineTransform).concat()
    let rotate = NSAffineTransform(); rotate.rotate(byDegrees: angle); rotate.concat()
    let rect = NSRect(x: -226, y: -270, width: 452, height: 540)
    let path = NSBezierPath(roundedRect: rect, xRadius: 68, yRadius: 68)
    let shadow = NSShadow(); shadow.shadowColor = .black.withAlphaComponent(0.3); shadow.shadowBlurRadius = 36; shadow.shadowOffset = NSSize(width: 0, height: -14); shadow.set()
    if front {
        NSGradient(starting: NSColor(calibratedRed: 0.76, green: 0.93, blue: 0.76, alpha: 1), ending: NSColor(calibratedRed: 0.33, green: 0.65, blue: 0.46, alpha: 1))!.draw(in: path, angle: -70)
    } else {
        NSColor(calibratedRed: 0.36, green: 0.52, blue: 0.41, alpha: 1).setFill(); path.fill()
    }
    NSShadow().set()
    NSColor.white.withAlphaComponent(front ? 0.55 : 0.28).setStroke(); path.lineWidth = 5; path.stroke()
    if front {
        let check = NSBezierPath(); check.move(to: NSPoint(x: -92, y: -4)); check.line(to: NSPoint(x: -22, y: -74)); check.line(to: NSPoint(x: 106, y: 79))
        check.lineWidth = 32; check.lineCapStyle = .round; check.lineJoinStyle = .round
        NSColor(calibratedRed: 0.12, green: 0.30, blue: 0.20, alpha: 1).setStroke(); check.stroke()
        let highlight = NSBezierPath(); highlight.move(to: NSPoint(x: -155, y: 205)); highlight.line(to: NSPoint(x: 145, y: 205)); highlight.lineWidth = 3
        NSColor.white.withAlphaComponent(0.35).setStroke(); highlight.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
}
photo(x: 408, y: 535, angle: 15, front: false)
photo(x: 586, y: 484, angle: -10, front: true)
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output).appendingPathComponent("Still-1024.png"))
