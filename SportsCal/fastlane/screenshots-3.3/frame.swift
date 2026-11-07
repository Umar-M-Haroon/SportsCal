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
    let maxW = W * 0.86
    let bounds = str.boundingRect(with: NSSize(width: maxW, height: 1000), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.saveGraphicsState()
    let flipped = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = flipped
    str.draw(with: NSRect(x: (W - maxW) / 2, y: top, width: maxW, height: bounds.height), options: [.usesLineFragmentOrigin])
    NSGraphicsContext.restoreGraphicsState()
    return bounds.height
}

let scale = W / 1320
var y = H * 0.055
y += drawText(headline, size: 96 * scale, weight: .bold, color: .white, top: y)
y += 18 * scale
y += drawText(subline, size: 46 * scale, weight: .regular, color: color("D6D3D1"), top: y)

// Device screenshot: rounded, with a thin bezel + shadow, bleeding off the bottom.
let devW = W * 0.82
let devH = devW * shot.size.height / shot.size.width
let devX = (W - devW) / 2, devY = max(y + 70 * scale, H * 0.2)
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

NSGraphicsContext.restoreGraphicsState()
// App Store rejects alpha: flatten to opaque RGB.
let cgOut = rep.cgImage!
let opaque = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
opaque.draw(cgOut, in: CGRect(x: 0, y: 0, width: W, height: H))
let final = NSBitmapImageRep(cgImage: opaque.makeImage()!)
try! final.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
