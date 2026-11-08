// swift frame.swift <raw.png> <out.png> <headline> <subline> [W H] [accentHex]
import AppKit

let a = CommandLine.arguments
let raw = a[1], out = a[2], headline = a[3], subline = a[4]
let W = a.count > 5 ? CGFloat(Double(a[5])!) : 1320
let H = a.count > 6 ? CGFloat(Double(a[6])!) : 2868
let accentHex = a.count > 7 ? a[7] : "E11D48"

func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = UInt32(hex, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

guard let shot = NSImage(contentsOfFile: raw) else { fatalError("no image \(raw)") }
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
// Flip to top-left origin for layout math.
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1)

// Background: near-black with an accent glow at the top.
color("0B0B0D").setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
let glow = NSGradient(colors: [color(accentHex, 0.55), color(accentHex, 0.0)])!
glow.draw(fromCenter: NSPoint(x: W / 2, y: 0), radius: 0, toCenter: NSPoint(x: W / 2, y: 0), radius: W * 1.05, options: [])

func drawText(_ s: String, size: CGFloat, weight: NSFont.Weight, color c: NSColor, top: CGFloat) -> CGFloat {
    let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byWordWrapping
    let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight),
                                                .foregroundColor: c, .paragraphStyle: para, .kern: -size * 0.01]
    let str = NSAttributedString(string: s, attributes: attrs)
    let maxW = W * 0.9
    let bounds = str.boundingRect(with: NSSize(width: maxW, height: 1000), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.saveGraphicsState()
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped
    str.draw(with: NSRect(x: (W - maxW) / 2, y: top, width: maxW, height: bounds.height), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
    return bounds.height
}

let scale = W / 1320
var y = H * 0.045
// Shrink the headline until it fits one line so every frame in the set lines up.
var headSize = 112 * scale
while headSize > 80 * scale {
    let w = NSAttributedString(string: headline, attributes: [.font: NSFont.systemFont(ofSize: headSize, weight: .heavy)]).size().width
    if w <= W * 0.9 { break }
    headSize -= 2 * scale
}
y += drawText(headline, size: headSize, weight: .heavy, color: .white, top: y)
y += 22 * scale
y += drawText(subline, size: 52 * scale, weight: .medium, color: color("E7E5E4"), top: y)

// Device screenshot: rounded, with a thin bezel + shadow, bleeding off the bottom.
let devW = W * 0.86
let devH = devW * shot.size.height / shot.size.width
let devX = (W - devW) / 2, devY = max(y + 60 * scale, H * 0.17)
let radius = 64 * scale
let bezel = 14 * scale
let outer = CGRect(x: devX - bezel, y: devY - bezel, width: devW + bezel * 2, height: devH + bezel * 2)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: 30 * scale), blur: 80 * scale, color: NSColor.black.withAlphaComponent(0.7).cgColor)
ctx.addPath(CGPath(roundedRect: outer, cornerWidth: radius + bezel, cornerHeight: radius + bezel, transform: nil))
ctx.setFillColor(color("2A2A2E").cgColor); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
let inner = CGRect(x: devX, y: devY, width: devW, height: devH)
ctx.addPath(CGPath(roundedRect: inner, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.clip()
// Draw image un-flipped inside the flipped context.
ctx.translateBy(x: 0, y: devY * 2 + devH); ctx.scaleBy(x: 1, y: -1)
if let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) { ctx.draw(cg, in: inner) }
ctx.restoreGState()

// Optional callout: arg 8 = "x,y,w,h" in screenshot pixels, arg 9 = zoom (default 1.14).
// Redraws that region larger, floating over the device, to make a small detail legible.
if a.count > 8, let cg = shot.cgImage(forProposedRect: nil, context: nil, hints: nil) {
    let r = a[8].split(separator: ",").compactMap { Double($0) }.map { CGFloat($0) }
    let zoom = a.count > 9 ? CGFloat(Double(a[9]) ?? 1.14) : 1.14
    if r.count == 4, let crop = cg.cropping(to: CGRect(x: r[0], y: r[1], width: r[2], height: r[3])) {
        let k = devW / CGFloat(cg.width)               // screenshot px → canvas px
        let w = min(r[2] * k * zoom, W * 0.94), h = w * r[3] / r[2]
        let cx = devX + (r[0] + r[2] / 2) * k
        let cy = devY + (r[1] + r[3] / 2) * k
        let rect = CGRect(x: max(W * 0.03, min(cx - w / 2, W * 0.97 - w)), y: cy - h / 2, width: w, height: h)
        let corner = 46 * scale * zoom
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 24 * scale), blur: 70 * scale,
                      color: NSColor.black.withAlphaComponent(0.8).cgColor)
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil))
        ctx.setFillColor(NSColor.black.cgColor); ctx.fillPath()
        ctx.restoreGState()
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: corner, cornerHeight: corner, transform: nil)); ctx.clip()
        ctx.translateBy(x: 0, y: rect.minY * 2 + rect.height); ctx.scaleBy(x: 1, y: -1)
        ctx.draw(crop, in: rect)
        ctx.restoreGState()
    }
}

NSGraphicsContext.restoreGraphicsState()
// App Store rejects alpha: flatten to opaque RGB.
let cgOut = rep.cgImage!
let opaque = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(cgOut, in: CGRect(x: 0, y: 0, width: W, height: H))
let final = NSBitmapImageRep(cgImage: opaque.makeImage()!)
try! final.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
