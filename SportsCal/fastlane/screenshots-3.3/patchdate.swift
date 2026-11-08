// swift patchdate.swift in.png out.png "Sat Nov 7" patchX patchY patchW patchH srcDY centerY fontSize
import AppKit
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
let text = a[3]
let (px, py, pw, ph, dy) = (Double(a[4])!, Double(a[5])!, Double(a[6])!, Double(a[7])!, Double(a[8])!)
let centerY = Double(a[9])!, size = Double(a[10])!
let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil)!
let W = cg.width, H = cg.height
let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
// Copy wallpaper from dy pixels above the patch (top-left coords → CG bottom-left).
let src = cg.cropping(to: CGRect(x: px, y: py - dy, width: pw, height: ph))!
ctx.draw(src, in: CGRect(x: px, y: Double(H) - py - ph, width: pw, height: ph))
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
let attrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: size, weight: .semibold),
    .foregroundColor: NSColor(srgbRed: 0.80, green: 0.79, blue: 0.87, alpha: 0.92)]
let str = NSAttributedString(string: text, attributes: attrs)
let b = str.size()
str.draw(at: NSPoint(x: (Double(W) - b.width) / 2, y: Double(H) - centerY - b.height / 2))
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: a[2]))
print("ok")
