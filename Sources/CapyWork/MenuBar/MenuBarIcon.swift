import AppKit
import CapyKit

@MainActor
enum MenuBarIcon {
    static let pixel: CGFloat = 1.5  // 3 device px on Retina, so edges stay crisp
    static let sprite = CGSize(width: 26 * pixel, height: 15 * pixel)
    static let gap: CGFloat = 3
    static let scale = 2  // bitmap pixels per point

    private static var sprites: [Pose: CGImage] = [:]
    private static var images: [Cast: NSImage] = [:]

    static func image(for cast: Cast) -> NSImage {
        if let hit = images[cast] { return hit }
        if images.count > 256 { images.removeAll() }
        let image = compose(cast)
        images[cast] = image
        return image
    }

    /// One finished bitmap per cast, so the status bar just blits it.
    private static func compose(_ cast: Cast) -> NSImage {
        let overflow = cast.overflow > 0 ? "+\(cast.overflow)" as NSString : nil
        let font: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 11, weight: .semibold),
                                                   .foregroundColor: NSColor(white: 0.55, alpha: 1)]
        let overflowWidth = overflow.map { ceil($0.size(withAttributes: font).width) + gap } ?? 0
        let count = CGFloat(cast.poses.count)
        let size = CGSize(width: count * sprite.width + (count - 1) * gap + overflowWidth, height: sprite.height)

        let ctx = bitmapContext(width: Int(size.width * CGFloat(scale)), height: Int(size.height * CGFloat(scale)))
        ctx.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
        ctx.interpolationQuality = .none
        for (i, pose) in cast.poses.enumerated() {
            ctx.draw(rasterized(pose), in: CGRect(origin: CGPoint(x: CGFloat(i) * (sprite.width + gap), y: 0), size: sprite))
        }
        if let overflow {
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            overflow.draw(at: NSPoint(x: size.width - overflowWidth + gap, y: (sprite.height - 14) / 2), withAttributes: font)
            NSGraphicsContext.restoreGraphicsState()
        }
        return NSImage(cgImage: ctx.makeImage()!, size: size)
    }

    private static func bitmapContext(width: Int, height: Int) -> CGContext {
        CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    }

    /// Each pose is painted pixel by pixel once, then reused as a bitmap.
    private static func rasterized(_ pose: Pose) -> CGImage {
        if let hit = sprites[pose] { return hit }
        let unit = Int(pixel * CGFloat(scale))
        let w = 26 * unit, h = 15 * unit
        let ctx = bitmapContext(width: w, height: h)
        func fill(_ x: Int, _ y: Int, _ color: NSColor) {
            ctx.setFillColor(color.cgColor)
            ctx.fill(CGRect(x: x * unit, y: h - (y + 1) * unit, width: unit, height: unit))
        }
        for (y, row) in pose.rows.enumerated() {
            for (x, c) in row.enumerated() where c != "." {
                fill(x, y, pose.flashesRed && c == "O" ? .systemRed : color(c))
            }
        }
        if pose.showsMoon {
            for p in Sprites.moon { fill(p.x, p.y, color("m")) }
        }
        let image = ctx.makeImage()!
        sprites[pose] = image
        return image
    }

    static func color(_ c: Character) -> NSColor {
        switch c {
        case "d": NSColor(srgbRed: 0.45, green: 0.29, blue: 0.17, alpha: 1)
        case "x": NSColor(srgbRed: 0.2, green: 0.12, blue: 0.08, alpha: 1)
        case "o": .systemOrange
        case "O": NSColor(srgbRed: 1, green: 0.42, blue: 0, alpha: 1)
        case "h": NSColor(srgbRed: 1, green: 0.9, blue: 0.6, alpha: 1)
        case "l", "g": .systemGreen
        case "w": .systemTeal
        case "s": NSColor(srgbRed: 1, green: 0.85, blue: 0.3, alpha: 1)
        case "m": NSColor(srgbRed: 0.95, green: 0.68, blue: 0.1, alpha: 1)  // deep enough to read on a white menu bar
        case "z": NSColor(white: 0.6, alpha: 1)  // reads on both light and dark menu bars
        default: NSColor(srgbRed: 0.76, green: 0.55, blue: 0.36, alpha: 1)
        }
    }
}
