// Renders the app icon (napping capybara under a night sky) into an .icns.
// swift tools/make-icon.swift && iconutil -c icns AppIcon.iconset -o Resources/AppIcon.icns
import AppKit

let grid = [
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    ".......................zzzz.....",
    ".........................z......",
    "...................l....z.......",
    "..................l....zzzz.....",
    ".................ooo............",
    "................ooooo...........",
    "..............dd.ooo............",
    "..............dddddddd..........",
    ".............d########dd........",
    "..........ddd#####xx####x.......",
    "......dddd##############d.......",
    "....dd##################d.......",
    "....d###################d.......",
    "....dddddddddddddddddddd........",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
    "................................",
]

func hex(_ s: String) -> NSColor {
    let v = Int(s.dropFirst(), radix: 16)!
    return NSColor(srgbRed: CGFloat(v >> 16 & 255) / 255, green: CGFloat(v >> 8 & 255) / 255, blue: CGFloat(v & 255) / 255, alpha: 1)
}

func color(_ c: Character) -> NSColor {
    switch c {
    case "d": hex("#73492B")
    case "x": hex("#33200F")
    case "o": hex("#FF9F1C")
    case "h": hex("#FFE7A8")
    case "l": hex("#34B24A")
    case "z": hex("#E8E8F0")
    default: hex("#C28C5C")
    }
}

func icon(_ size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let r = NSRect(x: 0, y: 0, width: s, height: s).insetBy(dx: s * 0.1, dy: s * 0.1)  // macOS icon grid
    let shape = NSBezierPath(roundedRect: r, xRadius: r.width * 0.225, yRadius: r.width * 0.225)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = s * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.set()
    NSGradient(starting: hex("#3B3F73"), ending: hex("#171A3A"))!.draw(in: shape, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    NSGraphicsContext.current?.shouldAntialias = false
    hex("#FFE58A").setFill()
    for (x, y, d) in [(0.2, 0.2, 0.02), (0.75, 0.15, 0.025), (0.55, 0.3, 0.015), (0.3, 0.38, 0.012)] as [(CGFloat, CGFloat, CGFloat)] {
        NSRect(x: r.minX + r.width * x, y: r.minY + r.height * (1 - y), width: max(1, r.width * d), height: max(1, r.width * d)).fill()
    }
    let px = r.width * 0.78 / 32
    let ox = r.minX + (r.width - px * 32) / 2, oy = r.maxY - (r.height - px * 32) / 2
    for (y, row) in grid.enumerated() {
        for (x, c) in row.enumerated() where c != "." {
            color(c).setFill()
            NSRect(x: ox + CGFloat(x) * px, y: oy - CGFloat(y + 1) * px, width: ceil(px), height: ceil(px)).fill()
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let dir = URL(fileURLWithPath: "AppIcon.iconset")
try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    try! icon(base).write(to: dir.appendingPathComponent("icon_\(base)x\(base).png"))
    try! icon(base * 2).write(to: dir.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try! icon(512).write(to: URL(fileURLWithPath: "docs/icon.png"))
