import SwiftUI

// ---------------------------------------------------------------------------
// 托盘场景：刚收进托盘的文件列表
//
// 尺寸与主页/媒体完全一致（同为 448×封面行），切场景时岛体不跳。
// 只露两条：行高 20 + 间距 4 正好等于封面行 44，其余折进底部一行计数。
// 文件可拖出到别的应用、点一下在 Finder 显示、底部一键清空。
// 不做单条删除：需求只要求「拖出 / 显示 / 清空」，多一个 14pt 的 x
// 既放不进 18pt 行高，也拿不到 28×28 的点击热区。
// 构建：./build.sh（源文件清单见 build.sh 的 SOURCES）
// ---------------------------------------------------------------------------

struct TrayScene: View {
    let width: CGFloat
    let rowHeight: CGFloat
    let footerHeight: CGFloat
    let items: [TrayItem]
    let notice: String?

    let onClear: () -> Void
    let onReveal: (TrayItem) -> Void

    /// 只露两条，其余折成一行计数
    private static let visibleCount = 2

    var body: some View {
        VStack(spacing: IslandSizeTable.progressGap) {
            list
                .frame(height: rowHeight, alignment: .top)
            footer
                .frame(height: footerHeight)
        }
        .frame(width: width)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: IslandSizeTable.trayRowSpacing) {
            if items.isEmpty {
                Text("拖文件进来暂存")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(height: IslandSizeTable.trayRowHeight)
            } else {
                ForEach(items.prefix(Self.visibleCount)) { item in
                    row(for: item)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// 整行是一个按钮：点一下在 Finder 显示；拖动则由 onDrag 接管，给原文件 URL
    private func row(for item: TrayItem) -> some View {
        Button {
            onReveal(item)
        } label: {
            HStack(spacing: 8) {
                if let icon = item.icon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: "doc.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 14)
                }
                Text(item.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .frame(height: IslandSizeTable.trayRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(IslandPressStyle())
        .onDrag { NSItemProvider(contentsOf: item.url) ?? NSItemProvider() }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(footerText)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
            Spacer(minLength: 0)
            if !items.isEmpty {
                Button {
                    onClear()
                } label: {
                    Text("清空")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .padding(.horizontal, 6)
                        .frame(minHeight: 28)   // 文字只有 14 高，补到 28 才够点
                        .contentShape(Rectangle())
                }
                .buttonStyle(IslandPressStyle())
            }
        }
    }

    /// 超限与复制失败的提示优先；没有提示时显示取出方式，超出两条补一句计数
    private var footerText: String {
        if let notice = notice { return notice }
        let hidden = items.count - Self.visibleCount
        return hidden > 0 ? "还有 \(hidden) 个 · 拖到别处即可取出" : "拖到别处即可取出"
    }
}