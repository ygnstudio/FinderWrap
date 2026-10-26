import AppKit
import Foundation

// Original vector geometry; no external artwork, fonts or SF Symbol assets.
let destination = URL(fileURLWithPath: "Resources/Assets.xcassets/AppIcon.appiconset")
let variants = [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)]
var entries: [[String: String]] = []
for (size, scale) in variants {
    let pixels = size * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!.cgContext
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    let background = CGPath(roundedRect: CGRect(x: 56, y: 56, width: 912, height: 912), cornerWidth: 210, cornerHeight: 210, transform: nil)
    context.addPath(background); context.clip()
    let colors = [CGColor(red: 0.15, green: 0.45, blue: 0.87, alpha: 1), CGColor(red: 0.20, green: 0.63, blue: 0.91, alpha: 1)]
    let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 60), end: CGPoint(x: 512, y: 964), options: [])
    context.setFillColor(CGColor(gray: 1, alpha: 0.36))
    for x in [CGFloat(230), 412, 594] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: 645, width: 124, height: 124), cornerWidth: 28, cornerHeight: 28, transform: nil))
        context.fillPath()
    }
    for x in [CGFloat(412), 594] {
        context.addPath(CGPath(roundedRect: CGRect(x: x, y: 245, width: 124, height: 124), cornerWidth: 28, cornerHeight: 28, transform: nil))
        context.fillPath()
    }
    context.setStrokeColor(CGColor(gray: 1, alpha: 1)); context.setLineWidth(66)
    context.setLineCap(.round); context.setLineJoin(.round)
    context.move(to: CGPoint(x: 796, y: 706)); context.addLine(to: CGPoint(x: 796, y: 570))
    context.addQuadCurve(to: CGPoint(x: 724, y: 498), control: CGPoint(x: 796, y: 498))
    context.addLine(to: CGPoint(x: 304, y: 498))
    context.addQuadCurve(to: CGPoint(x: 266, y: 460), control: CGPoint(x: 266, y: 498))
    context.addLine(to: CGPoint(x: 266, y: 285)); context.strokePath()
    context.move(to: CGPoint(x: 190, y: 363)); context.addLine(to: CGPoint(x: 266, y: 285))
    context.addLine(to: CGPoint(x: 342, y: 363)); context.strokePath()
    let filename = "icon_\(size)x\(size)@\(scale)x.png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: destination.appendingPathComponent(filename))
    entries.append(["idiom": "mac", "size": "\(size)x\(size)", "scale": "\(scale)x", "filename": filename])
}
let json: [String: Any] = ["images": entries, "info": ["author": "FinderWrap", "version": 1]]
try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: destination.appendingPathComponent("Contents.json"))
