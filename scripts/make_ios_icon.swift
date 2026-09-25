// Renders CanvasiOS/Resources/Assets.xcassets/AppIcon.appiconset (one 1024 px universal iOS icon) from AppArt:
// the Brass dark plate (full bleed; iOS applies the corner mask) with the mark in accent + signal, as on the Mac.
// Usage: scripts/make_ios_icon.sh (compiles this with the app's AppArt.swift and AppArtSource.swift).
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let out = URL(fileURLWithPath: CommandLine.arguments[1])
func hex(_ s: String) -> CGColor {
    var v: UInt64 = 0; Scanner(string: String(s.dropFirst())).scanHexInt64(&v)
    return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let bg = hex("#090b11"), panel = hex("#0e1219"), accent = hex("#e0b15c"), signal = hex("#74d6c4")

let px = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let cg = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                   bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
cg.translateBy(x: 0, y: CGFloat(px)); cg.scaleBy(x: 1, y: -1)
let full = CGRect(x: 0, y: 0, width: px, height: px)
cg.setFillColor(bg); cg.fill(full)
// The whole icon is the Mac icon's dark plate (iOS masks the corners); the mark keeps the Mac proportion.
let mark = CGFloat(px) * 0.6
AppArt.draw(in: cg, rect: CGRect(x: full.midX - mark / 2, y: full.midY - mark / 2, width: mark, height: mark)) { role in
    switch role {
    case .accentStroke, .accentFill: return accent
    case .signalStroke, .signalFill: return signal
    case .panelFill: return panel
    case .bgFill: return bg
    }
}
let image = cg.makeImage()!
let file = out.appendingPathComponent("AppIcon-1024.png")
let destination = CGImageDestinationCreateWithURL(file as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, image, nil)
CGImageDestinationFinalize(destination)
let json: [String: Any] = [
    "images": [["filename": "AppIcon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"]],
    "info": ["author": "xcode", "version": 1],
]
try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]).write(to: out.appendingPathComponent("Contents.json"))
print("wrote \(file.path)")
