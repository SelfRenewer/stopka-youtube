// Стопка: рисует иконку приложения для macOS во всех размерах.
// Запуск: swift safari/app/make-icon.swift safari/app
//
// Дизайн тот же, что у icons/icon-128.png: тёмная плашка и три полосы.
// Разница только в форме: плашка — суперэллипс по сетке иконок macOS
// (тело 824 из 1024, поле 100 по краям), иначе система обрамляет иконку
// своей серой подложкой. Всё векторное, поэтому чётко в любом размере.

import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func rgb(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

// Цвета и пропорции сняты с icons/icon-128.png (в единицах исходных 128 px).
let plate = rgb(0x131610)
let bars: [(color: NSColor, top: CGFloat)] = [(rgb(0xDDF15C), 30), (rgb(0x8A9181), 54), (rgb(0x575E53), 78)]
let barLeft: CGFloat = 23, barRight: CGFloat = 105, barHeight: CGFloat = 15

// Суперэллипс |x|^n + |y|^n = 1 с n = 5 — близко к форме иконок macOS.
func squircle(in r: CGRect, n: CGFloat = 5, steps: Int = 720) -> NSBezierPath {
    let p = NSBezierPath()
    let a = r.width / 2, b = r.height / 2, cx = r.midX, cy = r.midY
    for i in 0...steps {
        let t = CGFloat(i) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = cx + a * (c < 0 ? -1 : 1) * pow(abs(c), 2 / n)
        let y = cy + b * (s < 0 ? -1 : 1) * pow(abs(s), 2 / n)
        i == 0 ? p.move(to: NSPoint(x: x, y: y)) : p.line(to: NSPoint(x: x, y: y))
    }
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let k = CGFloat(px) / 1024
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)

    // Тень как у системных иконок: мягкая, вниз.
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = 20 * k
    shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
    shadow.set()
    plate.setFill()
    squircle(in: body).fill()
    NSGraphicsContext.restoreGraphicsState()

    // Полосы: координаты исходных 128 px → тело 824. Y в AppKit растёт вверх.
    let u = body.width / 128
    for bar in bars {
        let r = CGRect(x: body.minX + barLeft * u,
                       y: body.maxY - (bar.top + barHeight) * u,
                       width: (barRight - barLeft) * u, height: barHeight * u)
        bar.color.setFill()
        NSBezierPath(roundedRect: r, xRadius: r.height / 2, yRadius: r.height / 2).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

// Набор для AppIcon.appiconset: точки × масштаб = пиксели.
let set: [(pt: Int, scale: Int)] = [(16,1),(16,2),(32,1),(32,2),(128,1),(128,2),(256,1),(256,2),(512,1),(512,2)]
let iconset = outDir.appendingPathComponent("AppIcon.appiconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
var images: [String] = []
for s in set {
    let name = "mac-icon-\(s.pt)@\(s.scale)x.png"
    try! render(s.pt * s.scale).write(to: iconset.appendingPathComponent(name))
    images.append("""
        { "filename" : "\(name)", "idiom" : "mac", "scale" : "\(s.scale)x", "size" : "\(s.pt)x\(s.pt)" }
    """)
}
let json = "{\n  \"images\" : [\n" + images.joined(separator: ",\n") + "\n  ],\n  \"info\" : { \"author\" : \"xcode\", \"version\" : 1 }\n}\n"
try! json.write(to: iconset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

// Картинка в окне приложения: 128 точек, рисуем вдвое крупнее для Retina.
try! render(256).write(to: outDir.appendingPathComponent("Icon.png"))
print("готово: \(set.count) размеров + Icon.png → \(outDir.path)")
