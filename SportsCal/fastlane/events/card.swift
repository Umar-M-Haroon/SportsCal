// swift card.swift <out.png> <sfSymbol> <accentHex> <tagline> <iconPath> [W H]
// In-app event card art (1920×1080 card, 3840×2160 for the event page image).
// Apple overlays the event name + short description bottom-left, so keep the
// lower-left third free of anything important.
import AppKit

let a = CommandLine.arguments
let out = a[1], symbol = a[2], accentHex = a[3], tagline = a[4], iconPath = a[5]
let W = a.count > 6 ? CGFloat(Double(a[6])!) : 1920
let H = a.count > 7 ? CGFloat(Double(a[7])!) : 1080
let s = W / 1920

func color(_ hex: String, _ alpha: CGFloat = 1) -> NSColor {
    let v = UInt32(hex, radix: 16) ?? 0
    return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                   blue: CGFloat(v & 0xff) / 255, alpha: alpha)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Background: near-black, accent glow from the upper right, faint yard lines.
color("0B0B0D").setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()
NSGradient(colors: [color(accentHex, 0.75), color(accentHex, 0.0)])!
    .draw(fromCenter: NSPoint(x: W * 0.78, y: H * 0.62), radius: 0,
          toCenter: NSPoint(x: W * 0.78, y: H * 0.62), radius: W * 0.62, options: [])
color("FFFFFF", 0.06).setFill()
for i in 0..<13 { NSRect(x: CGFloat(i) * W / 12 - 2 * s, y: 0, width: 4 * s, height: H).fill() }
// Darken the lower-left where Apple's text overlay sits.
NSGradient(colors: [color("000000", 0.55), color("000000", 0.0)])!
    .draw(in: NSRect(x: 0, y: 0, width: W, height: H * 0.5), angle: 90)

// Big sport glyph, right side.
let cfg = NSImage.SymbolConfiguration(pointSize: 560 * s, weight: .bold)
    .applying(.init(paletteColors: [color("FFFFFF", 0.95)]))
if let sym = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(cfg) {
    let r = NSRect(x: W * 0.78 - sym.size.width / 2, y: H * 0.56 - sym.size.height / 2,
                   width: sym.size.width, height: sym.size.height)
    sym.draw(in: r)
}

// App icon + tagline, upper left.
if let icon = NSImage(contentsOfFile: iconPath) {
    let sz = 200 * s, x = 110 * s, y = H - 110 * s - sz
    let path = NSBezierPath(roundedRect: NSRect(x: x, y: y, width: sz, height: sz), xRadius: sz * 0.225, yRadius: sz * 0.225)
    NSGraphicsContext.saveGraphicsState(); path.addClip()
    icon.draw(in: NSRect(x: x, y: y, width: sz, height: sz)); NSGraphicsContext.restoreGraphicsState()
}
let para = NSMutableParagraphStyle(); para.alignment = .left
let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 92 * s, weight: .heavy),
                                            .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: -1.5 * s]
NSAttributedString(string: tagline, attributes: attrs)
    .draw(with: NSRect(x: 110 * s, y: H - 740 * s, width: W * 0.52, height: 380 * s),
          options: [.usesLineFragmentOrigin])

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(Int(W))x\(Int(H))")
