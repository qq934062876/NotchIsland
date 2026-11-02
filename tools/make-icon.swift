import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// ---------------------------------------------------------------------------
// App 图标生成器
//
// 产物：Assets/AppIcon.icns（build.sh 会拷进 Contents/Resources）。
// 设计意图与产品一致：深色底上的白色岛体，中央是物理刘海的缺口，下面是波形。
// 纯 CoreGraphics 重画，不依赖外部素材；每个尺寸单独绘制，小图标不糊。
// 用法：swift tools/make-icon.swift
// ---------------------------------------------------------------------------

let root = FileManager.default.currentDirectoryPath
let iconsetPath = root + "/Assets/AppIcon.iconset"
let icnsPath = root + "/Assets/AppIcon.icns"

try? FileManager.default.removeItem(atPath: iconsetPath)
try FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a)
}

/// 只有底部两角是圆角的矩形：白体的下沿要圆，顶边要贴齐
func bottomRoundedPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
    path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                      control: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
    path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                      control: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.closeSubpath()
    return path
}

func draw(size: Int) -> CGImage? {
    let side = CGFloat(size)
    let scale = side / 1024
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        return nil
    }
    ctx.setAllowsAntialiasing(true)
    ctx.interpolationQuality = .high

    // macOS 图标网格：内容区 824/1024，圆角约 185
    let inset = 100 * scale
    let body = CGRect(x: inset, y: inset, width: side - inset * 2, height: side - inset * 2)
    let bodyPath = CGPath(roundedRect: body,
                          cornerWidth: 185 * scale,
                          cornerHeight: 185 * scale,
                          transform: nil)

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()

    if let gradient = CGGradient(colorsSpace: space,
                                 colors: [rgb(44, 44, 48), rgb(9, 9, 11)] as CFArray,
                                 locations: [0, 1]) {
        ctx.drawLinearGradient(gradient,
                              start: CGPoint(x: 0, y: body.maxY),
                              end: CGPoint(x: 0, y: body.minY),
                              options: [])
    }

    // 白色岛体：贴屏幕顶（这里贴内容区顶），底边圆角
    let islandWidth = 600 * scale
    let islandHeight = 150 * scale
    let islandRect = CGRect(x: (side - islandWidth) / 2,
                            y: body.maxY - islandHeight,
                            width: islandWidth,
                            height: islandHeight)
    ctx.setFillColor(rgb(245, 245, 247))
    ctx.addPath(bottomRoundedPath(islandRect, radius: 46 * scale))
    ctx.fillPath()

    // 刘海缺口：从岛体顶边向下挖掉一块，只有底角是圆的
    let notchWidth = 214 * scale
    let notchHeight = 58 * scale
    let notchRect = CGRect(x: (side - notchWidth) / 2,
                           y: body.maxY - notchHeight,
                           width: notchWidth,
                           height: notchHeight)
    ctx.setFillColor(rgb(9, 9, 11))
    ctx.addPath(bottomRoundedPath(notchRect, radius: 26 * scale))
    ctx.fillPath()

    // 波形：4 根黑色圆角柱，高矮错开，落在岛体下半部
    let barWidth = 18 * scale
    let gap = 12 * scale
    let heights: [CGFloat] = [26, 52, 40, 20].map { $0 * scale }
    let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
    var x = (side - totalWidth) / 2
    let baseline = islandRect.minY + 34 * scale
    ctx.setFillColor(rgb(9, 9, 11))
    for height in heights {
        let bar = CGRect(x: x, y: baseline, width: barWidth, height: height)
        ctx.addPath(CGPath(roundedRect: bar,
                           cornerWidth: barWidth / 2,
                           cornerHeight: barWidth / 2,
                           transform: nil))
        x += barWidth + gap
    }
    ctx.fillPath()

    // 底部一条极淡的反射，避免大面积纯黑发闷
    if let glow = CGGradient(colorsSpace: space,
                             colors: [rgb(255, 255, 255, 0.10), rgb(255, 255, 255, 0)] as CFArray,
                             locations: [0, 1]) {
        ctx.drawRadialGradient(glow,
                               startCenter: CGPoint(x: side / 2, y: body.minY),
                               startRadius: 0,
                               endCenter: CGPoint(x: side / 2, y: body.minY),
                               endRadius: 420 * scale,
                               options: [])
    }

    ctx.restoreGState()
    return ctx.makeImage()
}

func writePNG(_ image: CGImage, name: String) {
    let url = URL(fileURLWithPath: iconsetPath + "/" + name) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, UTType.png.identifier as CFString, 1, nil) else {
        return
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

// iconset 需要的尺寸：逻辑尺寸 + @2x
let specs: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (pixels, name) in specs {
    guard let image = draw(size: pixels) else {
        FileHandle.standardError.write("绘制失败：\(name)\n".data(using: .utf8)!)
        exit(1)
    }
    writePNG(image, name: name)
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetPath, "-o", icnsPath]
try process.run()
process.waitUntilExit()
guard process.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil 失败\n".data(using: .utf8)!)
    exit(1)
}
// 只留 .icns，iconset 是中间产物，不进版本库
try? FileManager.default.removeItem(atPath: iconsetPath)
print("已生成 \(icnsPath)")
