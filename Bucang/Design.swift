import SwiftUI

// MARK: - 年轻化设计系统（全 App 共用一套，不许每个屏换一个主色）
// 暗黑模式修复：以前 background/card/accentSoft 写死浅色，
// 而文字用系统自适应 .primary/.secondary，暗黑下变白字，
// 白字配白底/浅底就看不见了。现在全部改成自适应系统色，
// 浅色下仍是暖灰白底 + 白卡片，暗黑下自动变深灰底 + 深灰卡片，
// 文字 .primary/.secondary 在两种模式下都可读。不强制浅色模式。
// 全部用 iOS 16 已有 API：Color(UIColor)、cornerRadius、shadow、
// foregroundColor（不用 iOS 17 的 新版前景样式 API）。

enum Design {
    // 系统分组背景：浅色 #F2F2F7 左右，深色接近黑色，自动适配。
    static let background = Color(UIColor.systemGroupedBackground)
    // 系统二级分组背景：浅色纯白，深色深灰，和 background 有明确分层。
    static let card = Color(UIColor.secondarySystemGroupedBackground)
    // V8 默认主色：#3A6DCC（V1 说明指定）。
    static let accent = Color(red: 0.23, green: 0.43, blue: 0.80)
    // 赭橙：价格与售出金额的强调色（V8）。暗黑下仍可读。
    static let priceAccent = Color(red: 0.77, green: 0.42, blue: 0.17)
    // 自适应柔和主色底：浅色浅蓝，深色深蓝底。
    static let accentSoft = Color(UIColor { trait in
        if trait.userInterfaceStyle == .dark {
            return UIColor(red: 0.13, green: 0.20, blue: 0.35, alpha: 1.0)
        } else {
            return UIColor(red: 0.90, green: 0.94, blue: 1.0, alpha: 1.0)
        }
    })
    static let corner: CGFloat = 18
    static let smallCorner: CGFloat = 12
}

// MARK: - 个性化主题（设置 > 个性化）
// 主色跟随设置里的主题名；默认深蓝。统计卡、FAB、顶栏下划线、
// 状态胶囊、卡片进度条等关键位置用主题色，其余次要按钮仍用默认深蓝，
// 避免一次全量替换带来的回归风险（见报告）。
enum ThemeHelper {
    static let options = ["深蓝", "珊瑚", "绿色", "紫色", "橙色", "粉色"]
    static func accent(_ themeName: String) -> Color {
        switch themeName {
        case "珊瑚": return Color(red: 0.95, green: 0.45, blue: 0.35)
        case "绿色": return Color(red: 0.20, green: 0.65, blue: 0.35)
        case "紫色": return Color(red: 0.55, green: 0.35, blue: 0.85)
        case "橙色": return Color(red: 0.95, green: 0.55, blue: 0.15)
        case "粉色": return Color(red: 0.90, green: 0.45, blue: 0.65)
        default: return Color(red: 0.23, green: 0.43, blue: 0.80) // V8 默认 #3A6DCC
        }
    }
    static func accentSoft(_ themeName: String) -> Color {
        accent(themeName).opacity(0.15)
    }
}

// 主题图：只用在统计卡背景（图片 + 深色遮罩，保证白字可读），
// 不做全屏背景，避免可读性风险。文件固定为 Documents/bucang-theme/theme.jpg。
enum ThemeImageStore {
    static func fileURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-theme").appendingPathComponent("theme.jpg")
    }
    static func exists() -> Bool {
        guard let url = fileURL() else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }
    static func load() -> UIImage? {
        guard let url = fileURL(), let data = try? Data(contentsOf: url) else { return nil }
        return UIImage(data: data)
    }
    @discardableResult
    static func save(_ image: UIImage) -> Bool {
        guard let url = fileURL() else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard let data = image.jpegData(compressionQuality: 0.85) else { return false }
        do { try data.write(to: url, options: .atomic); return true } catch { return false }
    }
    static func clear() {
        guard let url = fileURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// 统计卡背景：有主题图时图片 + 深色遮罩，否则纯主题色。
struct ThemeStatsBackground: View {
    var themeName: String
    var body: some View {
        ZStack {
            ThemeHelper.accent(themeName)
            if let uiImage = ThemeImageStore.load() {
                Image(uiImage: uiImage).resizable().scaledToFill()
                Color.black.opacity(0.45)
            }
        }
    }
}

// 白色圆角卡片：首页、统计、我的页共用。
struct CardView<Content: View>: View {
    var content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(16)
            .background(Design.card)
            .cornerRadius(Design.corner)
            .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }
}

// 胶囊筛选 chip：选中是主色底白字（白字配珊瑚色，浅深色都可读），
// 未选中是自适应卡片底 + 自适应 .primary 字，暗黑下不再是白底白字。
struct ChipButton: View {
    var title: String
    var selected: Bool
    var accent: Color = Design.accent
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(selected ? .semibold : .regular)
                .foregroundColor(selected ? .white : .primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(selected ? accent : Design.card)
                .cornerRadius(20)
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(selected ? Color.clear : Color.gray.opacity(0.25), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

// 剩余长度进度条：fraction 0…1，超出范围会被 clamp。
struct ProgressBarView: View {
    var fraction: Double
    var height: CGFloat = 8
    var accent: Color = Design.accent
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.15))
                    .frame(height: height)
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(accent)
                    .frame(width: geo.size.width * max(0, min(1, fraction)), height: height)
            }
        }
        .frame(height: height)
    }
}

// 首页 / 统计用的小统计卡。
struct StatCardView: View {
    var icon: String
    var title: String
    var value: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(Design.accent)
                    .font(.subheadline)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value)
                .font(.title3)
                .fontWeight(.bold)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }
}

// 首页快捷操作格子按钮。
struct QuickActionButton: View {
    var icon: String
    var title: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(Design.accent)
                    .frame(width: 44, height: 44)
                    .background(Design.accentSoft)
                    .cornerRadius(14)
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Design.card)
            .cornerRadius(Design.corner)
            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

// 自定义横向条形（不用 图表框架，避免 iOS 16 构建风险）：
// label + 数值 + 按最大值归一化的主色条。
struct BarRowView: View {
    var label: String
    var valueText: String
    var fraction: Double
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            ProgressBarView(fraction: fraction, height: 8)
        }
    }
}

// 自定义圆环（Circle.trim，iOS 13+ 就有）：用于作品平均进度等。
struct RingView: View {
    var fraction: Double
    var centerText: String
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.15), lineWidth: 10)
            Circle()
                .trim(from: 0, to: max(0, min(1, fraction)))
                .stroke(Design.accent, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(centerText)
                .font(.headline)
        }
    }
}

// 空态占位（不用 iOS 17 的 新版空态视图）。
struct EmptyPlaceholderView: View {
    var icon: String
    var title: String
    var subtitle: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }
}

// 小标题行：首页 / 统计 / 我的页共用。
struct SectionHeaderView: View {
    var title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.headline)
            if !subtitle.isEmpty {
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
