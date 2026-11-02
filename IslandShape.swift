import SwiftUI

// ---------------------------------------------------------------------------
// 岛体轮廓：顶边比身体宽 2×topFlare，顶部两角向外翻出
//
// 以右侧为例：身体右边界 x = maxX，外弧终点在 (maxX + topFlare, 0)，
// 弧心在 (maxX + topFlare, topFlare)。所以顶边比身体宽、往下收进去，
// 贴在屏幕顶沿时像从顶边长出来的喇叭口，而不是普通的圆角。
//
// 轮廓画在 rect 之外（左右各溢出 topFlare）：rect 始终等于身体宽，
// 内容行宽、命中区、档位宽度都不受外翻影响，只有视觉多出一圈。
// 阴影与描边都作用在整条路径上一次，避免分两段画出现叠影。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct IslandShape: Shape {
    /// 顶边单侧外翻宽度
    var topFlare: CGFloat
    /// 底部两角圆角
    var bottomRadius: CGFloat

    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        // 外翻与圆角都不能超过半个身体，否则路径会自交
        let f = min(max(topFlare, 0), min(w / 3, h / 2))
        let r = min(max(bottomRadius, 0), min(w / 2, h / 2))
        // 三次贝塞尔近似四分之一圆的标准系数
        let k: CGFloat = 0.5523

        var path = Path()
        path.move(to: CGPoint(x: rect.minX - f, y: rect.minY))
        // 左上外翻：从顶边外端收到身体左侧
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.minY + f),
                      control1: CGPoint(x: rect.minX - f + k * f, y: rect.minY),
                      control2: CGPoint(x: rect.minX, y: rect.minY + f - k * f))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - r))
        // 左下圆角
        path.addCurve(to: CGPoint(x: rect.minX + r, y: rect.maxY),
                      control1: CGPoint(x: rect.minX, y: rect.maxY - r + k * r),
                      control2: CGPoint(x: rect.minX + r - k * r, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - r, y: rect.maxY))
        // 右下圆角
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - r),
                      control1: CGPoint(x: rect.maxX - r + k * r, y: rect.maxY),
                      control2: CGPoint(x: rect.maxX, y: rect.maxY - r + k * r))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + f))
        // 右上外翻：从身体右侧向外收到顶边外端，终点在垂直侧线右边
        path.addCurve(to: CGPoint(x: rect.maxX + f, y: rect.minY),
                      control1: CGPoint(x: rect.maxX, y: rect.minY + f - k * f),
                      control2: CGPoint(x: rect.maxX + f - k * f, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

/// 边缘柔化描边：只有底边一小段淡白线，轻微模糊后当作「光线吃掉边缘」
/// 顶部与两侧保持 0（岛体边缘要纯黑，顶部一亮就成了白边，2026-11-03 用户反馈）；
/// 用三段 stop 而不是两段：两段线性渐变会让左右两侧也带上约 0.02 的白，仍看得出白边
/// 单独成视图，调用方只在岛体上叠一层，不加高光、不做第二圈
struct IslandEdgeStroke: View {
    let shape: IslandShape

    var body: some View {
        shape
            .stroke(
                LinearGradient(
                    stops: [
                        .init(color: .white.opacity(IslandSizeTable.edgeStrokeTopOpacity), location: 0),
                        .init(color: .white.opacity(IslandSizeTable.edgeStrokeTopOpacity),
                              location: IslandSizeTable.edgeStrokeVisibleStart),
                        .init(color: .white.opacity(IslandSizeTable.edgeStrokeBottomOpacity), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: IslandSizeTable.edgeStrokeWidth
            )
            .blur(radius: IslandSizeTable.edgeStrokeBlur)
            // 描边不是内容，别把点击热区撑到岛外
            .allowsHitTesting(false)
    }
}