// Frames a Mac window capture for the App Store, matching the iPhone set's
// style: dark canvas, large white SF caption on top, screenshot centered
// below with rounded corners and a soft shadow.
//
// Usage:
//   swift scripts/frame_mac_screenshot.swift <window-capture.png> <out.png> "Caption text"
//
// Output is 2880x1800 (Mac App Store 16:10). Captures from `screencapture -o`
// (no OS shadow) work best; the script adds its own consistent corner + shadow.

import AppKit

guard CommandLine.arguments.count >= 4 else {
    FileHandle.standardError.write(Data("usage: frame_mac_screenshot.swift <in.png> <out.png> \"Caption\"\n".utf8))
    exit(2)
}
let inPath = CommandLine.arguments[1]
let outPath = CommandLine.arguments[2]
let caption = CommandLine.arguments[3]

let canvasW: CGFloat = 2880
let canvasH: CGFloat = 1800
let captionTop: CGFloat = 96            // distance from canvas top to caption
let captionFontSize: CGFloat = 96
let shotTopGap: CGFloat = 72            // gap between caption baseline block and shot
let sideMargin: CGFloat = 160
let bottomMargin: CGFloat = 24          // shot may bleed toward the bottom edge
let cornerRadius: CGFloat = 28

guard let src = NSImage(contentsOfFile: inPath),
      let tiff = src.tiffRepresentation,
      let srcRep = NSBitmapImageRep(data: tiff) else {
    FileHandle.standardError.write(Data("could not load \(inPath)\n".utf8))
    exit(1)
}
let srcW = CGFloat(srcRep.pixelsWide)
let srcH = CGFloat(srcRep.pixelsHigh)

guard let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(canvasW), pixelsHigh: Int(canvasH),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
) else { exit(1) }
rep.size = NSSize(width: canvasW, height: canvasH)

NSGraphicsContext.saveGraphicsState()
guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else { exit(1) }
NSGraphicsContext.current = ctx
let cg = ctx.cgContext

// Canvas — same near-black as the iPhone set.
NSColor(calibratedWhite: 0.04, alpha: 1).setFill()
cg.fill(CGRect(x: 0, y: 0, width: canvasW, height: canvasH))

// Caption (top, centered). AppKit's y-axis is bottom-up.
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let captionAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: captionFontSize, weight: .semibold),
    .foregroundColor: NSColor.white,
    .paragraphStyle: paragraph,
]
let captionString = NSAttributedString(string: caption, attributes: captionAttrs)
let captionBounds = captionString.boundingRect(
    with: NSSize(width: canvasW - 2 * sideMargin, height: 400),
    options: [.usesLineFragmentOrigin]
)
let captionHeight = ceil(captionBounds.height)
captionString.draw(
    with: NSRect(x: sideMargin,
                 y: canvasH - captionTop - captionHeight,
                 width: canvasW - 2 * sideMargin,
                 height: captionHeight),
    options: [.usesLineFragmentOrigin]
)

// Screenshot: fit into the remaining area, centered horizontally.
let availableTop = canvasH - captionTop - captionHeight - shotTopGap
let maxW = canvasW - 2 * sideMargin
let maxH = availableTop - bottomMargin
// Never blow a small capture (the menu bar popover) up past 1.25×; it would go soft.
let scale = min(maxW / srcW, maxH / srcH, 1.25)
let shotW = floor(srcW * scale)
let shotH = floor(srcH * scale)
let shotX = (canvasW - shotW) / 2
let shotY = availableTop - shotH   // hang from the caption; extra space stays at the bottom

let shotRect = CGRect(x: shotX, y: shotY, width: shotW, height: shotH)
let path = NSBezierPath(roundedRect: shotRect, xRadius: cornerRadius, yRadius: cornerRadius)

// Soft shadow pass.
cg.saveGState()
cg.setShadow(offset: CGSize(width: 0, height: -18), blur: 60,
             color: NSColor.black.withAlphaComponent(0.55).cgColor)
NSColor(calibratedWhite: 0.1, alpha: 1).setFill()
path.fill()
cg.restoreGState()

// Clipped screenshot pass.
cg.saveGState()
path.addClip()
srcRep.draw(in: shotRect, from: .zero, operation: .sourceOver, fraction: 1.0,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high.rawValue])
cg.restoreGState()

// Hairline border so light window chrome doesn't melt into the canvas edge.
NSColor(calibratedWhite: 1, alpha: 0.08).setStroke()
path.lineWidth = 2
path.stroke()

ctx.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) (2880x1800)")
