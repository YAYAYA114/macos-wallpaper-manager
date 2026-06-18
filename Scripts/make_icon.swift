import AppKit

// 生成 1024x1024 应用图标:Apple 风「白底玻璃感」圆角方块 + photo.on.rectangle.angled
// 用法: swift make_icon.swift <输出.png> [color|graphite]
//   color    — 字形用 蓝→紫→粉 柔和渐变填充(默认)
//   graphite — 字形为石墨灰单色,极简
//
// 用现代的 NSImage(size:flipped:drawingHandler:) 绘制(替代已弃用的 lockFocus)。

let canvas: CGFloat = 1024
// Apple 官方图标网格:1024 画布中图形占 824,圆角约 185
let plateSize: CGFloat = 824
let cornerRadius: CGFloat = 185

let args = CommandLine.arguments
guard args.count >= 2 else { fatalError("用法: make_icon.swift <输出.png> [color|graphite]") }
let output = URL(fileURLWithPath: args[1])
let style = args.count >= 3 ? args[2] : "color"
let isGraphite = style == "graphite"

let plateRect = NSRect(x: (canvas - plateSize) / 2, y: (canvas - plateSize) / 2,
                       width: plateSize, height: plateSize)

// SF Symbol 字形(彩色变体用白色作为渐变蒙版,石墨变体直接上石墨灰)
let symbolColor: NSColor = isGraphite
    ? NSColor(calibratedRed: 0.27, green: 0.30, blue: 0.35, alpha: 1)
    : .white
let config = NSImage.SymbolConfiguration(pointSize: 430, weight: .regular)
    .applying(.init(paletteColors: [symbolColor]))
guard let symbol = NSImage(systemSymbolName: "photo.on.rectangle.angled",
                           accessibilityDescription: nil)?
    .withSymbolConfiguration(config) else {
    fatalError("无法加载 SF Symbol")
}

let symbolAspect = symbol.size.width / symbol.size.height
let glyphWidth = plateSize * 0.72
let glyphSize = NSSize(width: glyphWidth, height: glyphWidth / symbolAspect)
let glyphRect = NSRect(x: (canvas - glyphSize.width) / 2,
                       y: (canvas - glyphSize.height) / 2,
                       width: glyphSize.width, height: glyphSize.height)

// 彩色变体:用字形 alpha 作蒙版,填入 蓝→紫→粉 渐变
let glyphImage: NSImage = {
    guard !isGraphite else { return symbol }
    let grad = NSGradient(colorsAndLocations:
        (NSColor(calibratedRed: 0.29, green: 0.56, blue: 1.00, alpha: 1), 0.0),  // 蓝
        (NSColor(calibratedRed: 0.55, green: 0.45, blue: 0.98, alpha: 1), 0.5),  // 紫蓝
        (NSColor(calibratedRed: 1.00, green: 0.52, blue: 0.72, alpha: 1), 1.0)   // 粉
    )!
    return NSImage(size: glyphSize, flipped: false) { rect in
        grad.draw(in: rect, angle: -45)
        // destinationIn:只保留字形覆盖处的渐变,其余变透明
        symbol.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
        return true
    }
}()

let icon = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { _ in
    guard let ctx = NSGraphicsContext.current else { return false }
    let plate = NSBezierPath(roundedRect: plateRect, xRadius: cornerRadius, yRadius: cornerRadius)

    // 柔和落影(比旧版更轻,贴近白底玻璃质感)
    ctx.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
    shadow.shadowBlurRadius = 22
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    shadow.set()
    NSColor.white.setFill()
    plate.fill()
    ctx.restoreGraphicsState()

    // 白底上叠极淡竖向渐变 + 顶部高光,制造玻璃体积感
    ctx.saveGraphicsState()
    plate.addClip()
    NSGradient(colorsAndLocations:
        (NSColor.white, 0.0),
        (NSColor(calibratedWhite: 0.95, alpha: 1), 1.0)
    )!.draw(in: plateRect, angle: -90)

    let sheen = NSGradient(colorsAndLocations:
        (NSColor.white.withAlphaComponent(0.9), 0.0),
        (NSColor.white.withAlphaComponent(0.0), 1.0)
    )!
    let sheenRect = NSRect(x: plateRect.minX, y: plateRect.midY,
                           width: plateSize, height: plateSize / 2)
    sheen.draw(in: sheenRect, angle: -90)
    ctx.restoreGraphicsState()

    // 玻璃边缘:内描一圈极淡灰
    ctx.saveGraphicsState()
    let inset = plateRect.insetBy(dx: 1.5, dy: 1.5)
    let strokePath = NSBezierPath(roundedRect: inset,
                                  xRadius: cornerRadius - 1.5, yRadius: cornerRadius - 1.5)
    strokePath.lineWidth = 3
    NSColor(calibratedWhite: 0.0, alpha: 0.06).setStroke()
    strokePath.stroke()
    ctx.restoreGraphicsState()

    // 字形(彩色变体带一点柔影,增加层次;石墨变体保持纯净不加影)
    ctx.saveGraphicsState()
    if !isGraphite {
        let glyphShadow = NSShadow()
        glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.12)
        glyphShadow.shadowBlurRadius = 10
        glyphShadow.shadowOffset = NSSize(width: 0, height: -4)
        glyphShadow.set()
    }
    glyphImage.draw(in: glyphRect)
    ctx.restoreGraphicsState()

    return true
}

guard let tiff = icon.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("渲染失败")
}
try! png.write(to: output)
print("已生成 \(style) 图标 → \(output.path)")
