import SwiftUI
import PhotosUI
import UIKit
import AVKit

// MARK: - V3 布料卡片 / 详情 / 编辑 / 使用 / 出售 / 拍照找相似
// 卡片：无图时剪刀占位约占卡片一半高度；有图保持原高度。
// 编号小字在照片下方（名称不再显示）；信息条为用户自选字段
// （store.cardDisplayFields，见本文件 cardDisplayFields(of:) 的兼容读取），
// 每个字段是淡底小盒（label 上 + value 下），列表模式流式换行、
// 两列模式横向滚动；进度条为双色堆叠（已用主色 + 已售橙色，灰底为剩余）+
// 百分比；右侧一个圆形 + 按钮，点开 action sheet 选"记一次使用 / 登记出售"。
// 详情：基础信息去标题（只留收起钮）；照片头去左上星标；摘要卡收藏改星标、
// 总价下加单价小字；编号行去 chevron；子编号自动续号 + 关联布料；
// 颜色行改为色系图标单选（同步编号体系色系段）；图片板块仅展示；
// 使用/出售只留入口卡，点击进专属记录页；脑洞与备注加"关联脑洞"多选；
// 拍照找相似移到照片头正下方。

@MainActor
enum FabricStatusLabel {
    // V8 七级状态胶囊（Store.statusCapsules）：
    // 全部 / 收藏 / 未使用 / 使用中 / 已用完 / 部分出售 / 已出售。
    // 布料自身状态取 store.status(for:)；兜底保证永远返回胶囊表里的值。
    static func text(store: Store, fabric: Fabric) -> String {
        let s = store.status(for: fabric)
        return Store.statusCapsules.contains(s) ? s : "未使用"
    }
}

// MARK: - 卡片 / 记录页共用小件

/// 用户自选的卡片字段（`Store.cardDisplayFields`，@Published，持久化于 StoreData）。
/// 为空时回落到默认 5 项（与 Store 端"空视为未设置"的迁移口径一致）。
@MainActor
private func cardDisplayFields(of store: Store) -> [String] {
    let v = store.cardDisplayFields
    return v.isEmpty ? ["material", "width", "length", "unitPrice", "remaining"] : v
}

/// 简单流式布局（iOS 16 Layout）：子视图按行排列、行内居左，用于卡片信息条。
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    private struct Row {
        var indices: [Int]
        var width: CGFloat
        var height: CGFloat
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = []
        var cur: [Int] = []
        var curW: CGFloat = 0
        var curH: CGFloat = 0
        for (i, sv) in subviews.enumerated() {
            let s = sv.sizeThatFits(.unspecified)
            let w = cur.isEmpty ? s.width : curW + spacing + s.width
            if !cur.isEmpty && w > maxWidth {
                rows.append(Row(indices: cur, width: curW, height: curH))
                cur = [i]; curW = s.width; curH = s.height
            } else {
                cur.append(i); curW = w; curH = max(curH, s.height)
            }
        }
        if !cur.isEmpty { rows.append(Row(indices: cur, width: curW, height: curH)) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = arrange(proposal: proposal, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for idx in row.indices {
                let size = subviews[idx].sizeThatFits(.unspecified)
                subviews[idx].place(
                    at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                    proposal: .unspecified
                )
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }
}

/// 双色堆叠进度条：已用（主色）+ 已售（橙色），灰底代表剩余。
/// fractions 按总长度归一化，内部 clamp 防越界；份数出售不进 sold（store.soldLength 已只计长度）。
struct DualProgressBarView: View {
    var usedFraction: Double
    var soldFraction: Double
    var height: CGFloat = 8
    var usedColor: Color = Design.accent
    var soldColor: Color = Design.priceAccent

    private func clamp01(_ v: Double) -> CGFloat { max(0, min(1, v)) }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: height / 2)
                    .fill(Color.gray.opacity(0.15))
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(usedColor)
                        .frame(width: geo.size.width * clamp01(usedFraction))
                    RoundedRectangle(cornerRadius: height / 2)
                        .fill(soldColor)
                        .frame(width: geo.size.width * clamp01(soldFraction))
                    Spacer(minLength: 0)
                }
            }
            .clipped() // 数据异常（已用+已售>总长）时不溢出轨道
        }
        .frame(height: height)
    }
}

/// 记录类表单 / 记录页的图标盒：44pt 圆角正方形淡主色底 + 主色 SF 图标。
struct RecordIconBox: View {
    var icon: String
    var accent: Color = Design.accent
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(accent.opacity(0.12))
                .frame(width: 44, height: 44)
            Image(systemName: icon)
                .foregroundColor(accent)
                .font(.headline)
        }
    }
}

/// 显示用数字：去多余小数点后 0（"2.00"→"2"，"1.50"→"1.5"）。
private func displayNum(_ v: Double) -> String {
    if v.truncatingRemainder(dividingBy: 1) == 0 { return String(format: "%.0f", v) }
    var s = String(format: "%.2f", v)
    while s.hasSuffix("0") { s.removeLast() }
    if s.hasSuffix(".") { s.removeLast() }
    return s
}

struct FabricCardView: View {
    @EnvironmentObject private var store: Store
    var fabric: Fabric
    var onAddUsage: () -> Void
    var onAddSale: () -> Void = {}
    var compact: Bool = false
    @State private var showingAddSheet = false
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var sold: Double { store.soldLength(for: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    private var statusText: String { store.status(for: fabric) }
    private var isSoldOut: Bool { statusText == "已出售" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let first = fabric.imageFileNames.first,
                   let uiImage = FabricImageStore.loadImage(named: first) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(height: compact ? 110 : 150)
                        .clipped()
                } else {
                    // 无图占位：剪刀图标，占位高度大于照片高度（列表约 220 / 两列约 140），
                    // 让无图卡片在视觉上占卡片高度的一半以上。
                    Rectangle()
                        .fill(Design.accentSoft)
                        .frame(height: compact ? 140 : 220)
                        .overlay(Image(systemName: "scissors").foregroundColor(Design.accent).font(.title))
                }
                Button(action: {
                    fabric.isFavorite.toggle()
                    fabric.updatedAt = Date()
                    store.save()
                }) {
                    Image(systemName: fabric.isFavorite ? "star.fill" : "star")
                        .foregroundColor(fabric.isFavorite ? .yellow : .white)
                        .padding(6)
                        .background(Circle().fill(Color.black.opacity(0.35)))
                }
                .buttonStyle(.plain)
                .padding(8)
                HStack {
                    Spacer()
                    Text(statusText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.45))
                        .cornerRadius(10)
                        .padding(8)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                // 名称不再显示；编号小字在照片下方左对齐。
                if !fabric.code.isEmpty {
                    Text(fabric.code)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                // 用户自选字段：两列模式卡片窄，信息盒横向滚动；
                // 列表模式用流式布局换行（每行 2–3 个）。
                if compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) { infoBoxes }
                    }
                } else {
                    FlowLayout(spacing: 8) { infoBoxes }
                }
                if fabric.hasPurchaseLength && fabric.length > 0 {
                    // 双色堆叠进度条（已用主色 + 已售橙色）+ 剩余百分比 + 右侧圆形 + 按钮。
                    let usedFrac = fabric.usedLength / fabric.length
                    let soldFrac = sold / fabric.length
                    HStack(spacing: 8) {
                        DualProgressBarView(usedFraction: usedFrac, soldFraction: soldFrac, height: 8, usedColor: themeAccent)
                        Text("\(Int(remaining / fabric.length * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        addRecordButton
                    }
                } else if !fabric.hasPurchaseLength {
                    // 买入长度留空时仍可记使用/出售（不显示进度条，但入口保留）。
                    HStack {
                        Spacer()
                        addRecordButton
                    }
                }
            }
            .padding(12)
        }
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // 卡片右下单一入口：圆形 + 按钮，点开 action sheet 选"记一次使用 / 登记出售"。
    // 已售出（剩余 0 且有售出）时置灰不可点。两种卡片分支（有/无买入长度）共用。
    private var addRecordButton: some View {
        Button(action: { showingAddSheet = true }) {
            Image(systemName: "plus")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(isSoldOut ? Color.gray : themeAccent)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(isSoldOut)
        .accessibilityLabel("记录使用或出售")
        .confirmationDialog("记录", isPresented: $showingAddSheet, titleVisibility: .hidden) {
            // iOS 16 上从 action sheet 里直接 present 另一个 sheet 会撞车白屏，等 dialog 收起再弹。
            Button("记一次使用") { DispatchQueue.main.async { onAddUsage() } }
            Button("登记出售") { DispatchQueue.main.async { onAddSale() } }
            Button("取消", role: .cancel) {}
        }
    }

    /// 用户自选字段的信息盒（与设置页 `Store.cardDisplayFields` 共用同一份 key→label/value 约定）。
    /// key 去重，避免 ForEach(id: \.self) 遇到重复 key。
    @ViewBuilder
    private var infoBoxes: some View {
        ForEach(uniqueCardFields, id: \.self) { key in
            if let field = cardFieldValue(key: key) {
                infoBox(label: field.label, value: field.value, accent: key == "unitPrice" ? Design.priceAccent : nil)
            }
        }
    }

    private var uniqueCardFields: [String] {
        var seen = Set<String>()
        return cardDisplayFields(of: store).filter { seen.insert($0).inserted }
    }

    /// key → (label, value)，value 格式与设置页约定完全一致。
    private func cardFieldValue(key: String) -> (label: String, value: String)? {
        switch key {
        case "material":
            return ("材质", fabric.materialName.isEmpty ? "—" : fabric.materialName)
        case "width":
            return ("宽幅", fabric.width > 0 ? "\(String(format: "%.0f", fabric.widthCm))厘米" : "—")
        case "length":
            return ("米数", fabric.hasPurchaseLength
                ? "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))"
                : "—")
        case "unitPrice":
            return ("单价", fabric.unitPrice.map { "¥\(String(format: "%.2f", $0))" } ?? "—")
        case "remaining":
            return ("剩余数", fabric.hasPurchaseLength
                ? "\(LengthUnitHelper.format(remaining, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))"
                : "—")
        case "totalPrice":
            return ("总价", fabric.purchasePrice > 0 ? "¥\(String(format: "%.2f", fabric.purchasePrice))" : "—")
        case "color":
            if fabric.colorName.isEmpty { return ("颜色", "—") }
            if let item = store.colorItem(forName: fabric.colorName), !item.code.isEmpty {
                return ("颜色", "\(fabric.colorName)/\(item.code)")
            }
            return ("颜色", fabric.colorName)
        case "channel":
            return ("渠道", fabric.channelName.isEmpty ? "—" : fabric.channelName)
        case "tags":
            let names = store.tags(for: fabric).map { $0.name }
            return ("标签", names.isEmpty ? "—" : names.joined(separator: "、"))
        default:
            return nil
        }
    }

    private func infoBox(label: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundColor(.secondary)
            Text(value)
                .font(.subheadline).fontWeight(.semibold)
                .foregroundColor(accent ?? .primary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// V8 布料详情（原版布局）：顶部照片头（4:3 全宽 Tab + 放大按钮 +
// 多图页码，无左上星标）/ 视频条 / 拍照找相似入口，摘要卡（编号 / 名称 /
// 收藏星标 / 状态胶囊 / 已用 / 可用大数字 / 进度条 / 布长幅宽总价三列，
// 总价下带单价小字）；下方 7 个可折叠板块（图片 / 基础信息 /
// 布料信息 / 其他信息 / 消耗记录 / 出售记录 / 脑洞与备注），收起状态存在
// fabric.collapsedSections。"基础信息"板块只留收起钮、不显示标题文字。
// 图片板块为纯展示（增删改走右上 … → 编辑）；使用/出售板块只显示入口卡，
// 点进专属记录页（UsageRecordsPageView / SaleRecordsPageView）；
// 脑洞与备注保留备注 inline 编辑 + 关联脑洞多选。
// 注意：Fabric.brainstorm 旧文本字段已从全部 UI 移除（模型字段保留），
// 脑洞板块只展示关联的 Brainstorm 实体（经 BrainstormDetailView 进入）。
// 本详情页不加任何悬浮 + 按钮（tab 的 FAB 由路径隐藏逻辑控制）。
struct FabricDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingSimilar = false
    @State private var showingLongImage = false
    @State private var longImage: UIImage?
    // 子编号关联布料：linkingSubCode 为正在关联的子编号，sheet 里选布料。
    @State private var showingSubCodePicker = false
    @State private var linkingSubCode: String?
    // 脑洞与备注：多选关联脑洞。
    @State private var showingBrainstormPicker = false
    // 原版详情头：照片 Tab 索引 / 全屏预览图名 / 播放中的视频 / 备注 inline 编辑
    @State private var headerPhotoIndex = 0
    @State private var previewName: String?
    @State private var playingURL: URL?
    @State private var editingNote = ""
    @State private var isEditingNote = false

    private var usageRecords: [UsageRecord] { store.usageRecords(for: fabric.id) }
    private var saleRecords: [SaleRecord] { store.saleRecords(for: fabric.id) }
    private var linkedWorks: [Work] { store.works(for: fabric.id) }
    private var linkedBrainstorms: [Brainstorm] { store.brainstorms(forFabric: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    private var sold: Double { store.soldLength(for: fabric.id) }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private let sectionKeys = ["images", "basic", "fabric", "other", "usage", "sale", "brainstorm"]
    private var allCollapsed: Bool { Set(sectionKeys).isSubset(of: Set(fabric.collapsedSections)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // 顶：全部收起 / 展开
                HStack {
                    Spacer()
                    Button(action: toggleAllSections) {
                        HStack(spacing: 6) {
                            Image(systemName: allCollapsed ? "arrow.up.circle" : "arrow.down.circle")
                            Text(allCollapsed ? "全部展开" : "全部收起")
                        }
                        .font(.subheadline)
                        .foregroundColor(Design.accent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 10)

                // 基础信息：只留收起钮（标题文字已去掉）；内容是照片头 + 视频条 +
                // 拍照找相似入口 + 摘要卡。
                HStack {
                    Spacer()
                    collapseToggleButton(key: "basic")
                }
                .padding(.bottom, 8)
                photoHeader
                if !fabric.videoFileNames.isEmpty {
                    videoStrip
                        .padding(.top, 10)
                }
                // 拍照找相似：紧贴照片头下方（原在页面最底部）。
                Button(action: { showingSimilar = true }) {
                    HStack {
                        Spacer()
                        Image(systemName: "camera.viewfinder")
                        Text("拍照找相似")
                        Spacer()
                    }
                    .font(.subheadline)
                    .foregroundColor(Design.accent)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Design.accent, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.top, 10)
                if fabric.collapsedSections.contains("basic") {
                    CardView {
                        collapsedSummary(key: "basic")
                    }
                    .padding(.top, 10)
                } else {
                    summaryCard
                        .padding(.top, 10)
                }

                // 其余可折叠板块
                VStack(alignment: .leading, spacing: 20) {
                    // 图片板块：纯展示（增删改走右上 … → 编辑里的图片板块）。
                    // 缩略图点进全屏预览（复用 photoHeader 的 previewName 机制），
                    // 视频点播放（复用 videoStrip）。
                    collapsibleSection(key: "images", title: "图片") {
                        VStack(alignment: .leading, spacing: 12) {
                            if !fabric.imageFileNames.isEmpty {
                                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                                    ForEach(fabric.imageFileNames, id: \.self) { name in
                                        Button(action: { previewName = name }) {
                                            Group {
                                                if let uiImage = FabricImageStore.loadImage(named: name) {
                                                    Image(uiImage: uiImage)
                                                        .resizable()
                                                        .scaledToFill()
                                                } else {
                                                    Color.gray.opacity(0.15)
                                                }
                                            }
                                            .frame(height: 100)
                                            .clipped()
                                            .cornerRadius(10)
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("查看大图")
                                    }
                                }
                            }
                            if !fabric.videoFileNames.isEmpty {
                                videoStrip
                            }
                            if fabric.imageFileNames.isEmpty && fabric.videoFileNames.isEmpty {
                                Text("暂无图片").font(.subheadline).foregroundColor(.secondary)
                            }
                        }
                    }
                    collapsibleSection(key: "fabric", title: "布料信息") { fabricInfoCard }
                    collapsibleSection(key: "other", title: "其他信息") { otherInfoCard }
                    collapsibleSection(key: "usage", title: "消耗记录") { usageCard }
                    collapsibleSection(key: "sale", title: "出售记录") { saleCard }
                    collapsibleSection(key: "brainstorm", title: "脑洞与备注") { brainstormCard }
                }
                .padding(.top, 20)
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle(fabric.displayName)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("编辑", action: { showingEdit = true })
                    ShareLink(item: fabricSummary, preview: SharePreview(fabric.displayName)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button("生成长图", action: { generateLongImage() })
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: {
                    Image(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $showingEdit) { NavigationStack { FabricEditView(fabric: fabric) } }
        .sheet(isPresented: $showingSimilar) { NavigationStack { SimilarSearchView() } }
        .sheet(isPresented: $showingSubCodePicker) {
            NavigationStack { SubCodeFabricPickerView(fabric: fabric, subCode: linkingSubCode ?? "") }
        }
        .sheet(isPresented: $showingBrainstormPicker) {
            NavigationStack { FabricBrainstormLinkPickerView(fabric: fabric) }
        }
        .sheet(isPresented: $showingLongImage) {
            if let longImage {
                NavigationStack {
                    VStack {
                        Image(uiImage: longImage).resizable().scaledToFit().padding()
                        ShareLink(item: Image(uiImage: longImage), preview: SharePreview("布料长图")) {
                            Label("分享长图", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent).tint(themeAccent)
                        Text("从分享表里可保存到相册或发给朋友。").font(.caption).foregroundColor(.secondary)
                    }
                    .navigationTitle("长图")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingLongImage = false } } }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { playingURL != nil },
            set: { if !$0 { playingURL = nil } }
        )) {
            if let url = playingURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
        }
        .fullScreenCover(item: Binding(
            get: { previewName.map { DetailPreviewItem(name: $0) } },
            set: { previewName = $0?.name }
        )) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let uiImage = FabricImageStore.loadImage(named: item.name) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
                Button(action: { previewName = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
        .alert("删除确认", isPresented: $showingDelete) {
            Button("删除", role: .destructive) { store.deleteFabric(fabric); dismiss() }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后无法恢复，同时会删除它的使用与出售记录。") }
    }

    // MARK: - 折叠

    private func toggleSection(_ key: String) {
        if fabric.collapsedSections.contains(key) {
            fabric.collapsedSections.removeAll { $0 == key }
        } else {
            fabric.collapsedSections.append(key)
        }
        fabric.updatedAt = Date()
        store.save()
    }

    private func toggleAllSections() {
        if allCollapsed {
            fabric.collapsedSections.removeAll()
        } else {
            fabric.collapsedSections = sectionKeys
        }
        fabric.updatedAt = Date()
        store.save()
    }

    /// 圆形收起 / 展开钮（各板块标题行共用）。
    private func collapseToggleButton(key: String) -> some View {
        let collapsed = fabric.collapsedSections.contains(key)
        return Button(action: { toggleSection(key) }) {
            Image(systemName: collapsed ? "chevron.down" : "chevron.up")
                .font(.footnote)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 30, height: 30)
                .background(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(collapsed ? "展开" : "收起")
    }

    private func collapsibleSection<Content: View>(key: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        let collapsed = fabric.collapsedSections.contains(key)
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                collapseToggleButton(key: key)
            }
            if collapsed {
                collapsedSummary(key: key)
            } else {
                content()
            }
        }
    }

    @ViewBuilder
    private func collapsedSummary(key: String) -> some View {
        // 图片收起时显示计数；基础信息在收起时保留关键值（编号、名称、可用米数、总价），其余只留标题。
        if key == "images" {
            Text("\(fabric.imageFileNames.count) 张照片 · \(fabric.videoFileNames.count) 个视频")
                .font(.subheadline)
                .foregroundColor(.secondary)
        } else if key == "basic" {
            VStack(alignment: .leading, spacing: 5) {
                if !fabric.code.isEmpty {
                    Text("编号：\(fabric.code)").font(.subheadline)
                }
                Text("名称：\(fabric.displayName)").font(.subheadline)
                if fabric.hasPurchaseLength {
                    Text("可用：\(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                        .font(.subheadline).foregroundColor(.secondary)
                }
                if fabric.hasTotalPrice {
                    Text("总价：¥\(String(format: "%.2f", fabric.purchasePrice))")
                        .font(.subheadline).foregroundColor(Design.priceAccent)
                }
            }
        }
    }

    // MARK: - 原版布局共用小件

    private func toggleFavorite() {
        fabric.isFavorite.toggle()
        fabric.updatedAt = Date()
        store.save()
    }

    /// 44pt 圆角正方形淡主色底 + 主色 SF 图标（布料信息 / 其他信息卡的行首）。
    private func iconBox(_ icon: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(themeAccent.opacity(0.12))
                .frame(width: 44, height: 44)
            Image(systemName: icon)
                .foregroundColor(themeAccent)
                .font(.headline)
        }
    }

    /// 图标盒行：图标盒 + 灰色 label + 右侧加粗 value（"未填"显示次级灰），
    /// 可选商家二级文本与右侧 chevron。
    private func iconInfoRow(icon: String, label: String, value: String, valueColor: Color? = nil, subtext: String? = nil, showChevron: Bool = false) -> some View {
        HStack(spacing: 12) {
            iconBox(icon)
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(valueColor ?? (value == "未填" ? .secondary : .primary))
                    .multilineTextAlignment(.trailing)
                if let subtext, !subtext.isEmpty {
                    Text(subtext)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    /// 状态胶囊（描边风格）：小圆圈 + 状态文字，主色。
    private var statusCapsule: some View {
        HStack(spacing: 4) {
            Circle()
                .stroke(themeAccent, lineWidth: 1.5)
                .frame(width: 8, height: 8)
            Text(store.status(for: fabric))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(themeAccent)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(themeAccent, lineWidth: 1)
        )
    }

    /// 摘要卡底部三列：图标 + 灰 label + 加粗 value，可选 value 下方的小字 subtext。
    private func summaryStat(icon: String, label: String, value: String, valueColor: Color = .primary, subtext: String? = nil) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(.secondary)
                .font(.subheadline)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(valueColor)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let subtext {
                Text(subtext)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private struct DetailPreviewItem: Identifiable {
        var name: String
        var id: String { name }
    }

    // MARK: - 一、基础信息（原版头：照片头 + 视频条 + 摘要卡）

    /// 照片头：全宽 4:3，多图可横滑（TabView，不显示系统页码，右下角自绘 "N / M"），
    /// 右上放大进全屏预览（点图片本身也进）；无图时剪刀占位。左上不再放收藏星标
    ///（收藏只在摘要卡里用星标切换）。
    private var photoHeader: some View {
        ZStack(alignment: .topLeading) {
            if fabric.imageFileNames.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Design.accentSoft)
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(
                        Image(systemName: "scissors")
                            .font(.largeTitle)
                            .foregroundColor(Design.accent)
                    )
            } else {
                TabView(selection: $headerPhotoIndex) {
                    ForEach(Array(fabric.imageFileNames.enumerated()), id: \.element) { idx, name in
                        Group {
                            if let uiImage = FabricImageStore.loadImage(named: name) {
                                Image(uiImage: uiImage)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Color.gray.opacity(0.15)
                            }
                        }
                        .tag(idx)
                        .onTapGesture { previewName = name }
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .aspectRatio(4 / 3, contentMode: .fit)
                .cornerRadius(16)
                .clipped()
            }
            // 右上：放大按钮（当前页进全屏预览）
            if !fabric.imageFileNames.isEmpty {
                HStack {
                    Spacer()
                    Button(action: {
                        let idx = min(headerPhotoIndex, fabric.imageFileNames.count - 1)
                        if idx >= 0 { previewName = fabric.imageFileNames[idx] }
                    }) {
                        Image(systemName: "arrow.up.left.and.down.right")
                            .foregroundColor(.white)
                            .padding(8)
                            .background(Circle().fill(Color.black.opacity(0.35)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("放大看图")
                }
                .padding(12)
            }
            // 多图页码
            if fabric.imageFileNames.count > 1 {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Text("\(min(headerPhotoIndex, fabric.imageFileNames.count - 1) + 1) / \(fabric.imageFileNames.count)")
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.45)))
                    }
                }
                .padding(12)
            }
        }
        .onChange(of: fabric.imageFileNames) { names in
            if headerPhotoIndex >= names.count {
                headerPhotoIndex = max(0, names.count - 1)
            }
        }
    }

    /// 视频条：横向小缩略图 + 播放徽，点击用 VideoPlayer 播放（与视频编辑器同链路）。
    private var videoStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(fabric.videoFileNames, id: \.self) { name in
                    Button(action: {
                        if let url = FabricVideoStore.fileURL(for: name) { playingURL = url }
                    }) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.75))
                                .frame(width: 96, height: 60)
                            Image(systemName: "play.circle.fill")
                                .font(.title2)
                                .foregroundColor(.white)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("播放视频")
                }
            }
        }
    }

    /// 摘要卡：编号 caption + 名称 / 右侧星标收藏 + 状态胶囊；已使用 X 米 · P% /
    /// 右侧可用大数字；细进度条；布长 / 幅宽 / 总价三列（总价下带单价小字）。
    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    if !fabric.code.isEmpty {
                        Text(fabric.code)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(fabric.displayName)
                        .font(.title2)
                        .fontWeight(.bold)
                        .lineLimit(2)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    // 收藏：星标（已收藏为黄色），与卡片左上星标一致。
                    Button(action: toggleFavorite) {
                        Image(systemName: fabric.isFavorite ? "star.fill" : "star")
                            .font(.title3)
                            .foregroundColor(fabric.isFavorite ? .yellow : .gray)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("收藏")
                    statusCapsule
                }
            }
            HStack(alignment: .bottom) {
                Text(usedSummaryText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeAccent)
                Spacer()
                if fabric.hasPurchaseLength {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(LengthUnitHelper.format(remaining, unit: store.lengthUnit))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text(LengthUnitHelper.suffix(unit: store.lengthUnit))
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Text("可用")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("未填")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
            }
            if fabric.hasPurchaseLength && fabric.length > 0 {
                ProgressBarView(fraction: remaining / fabric.length, height: 6, accent: themeAccent)
            }
            Divider()
            HStack(spacing: 0) {
                summaryStat(icon: "ruler", label: "布长",
                            value: fabric.hasPurchaseLength
                                ? "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))"
                                : "未填")
                summaryStat(icon: "arrow.left.arrow.right", label: "幅宽",
                            value: fabric.width > 0 ? "\(String(format: "%.0f", fabric.widthCm))厘米" : "未填")
                summaryStat(icon: "yensign", label: "总价",
                            value: fabric.hasTotalPrice ? "¥\(String(format: "%.2f", fabric.purchasePrice))" : "—",
                            valueColor: Design.priceAccent,
                            subtext: fabric.unitPrice.map { "单价 ¥\(String(format: "%.2f", $0))/米" })
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    /// "已使用 X 米 · P%"（P = 已用 / 买入；未填买入时不带百分比）。
    private var usedSummaryText: String {
        let base = "已使用 \(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))"
        if fabric.hasPurchaseLength && fabric.length > 0 {
            return "\(base) · \(Int(fabric.usedLength / fabric.length * 100))%"
        }
        return base
    }

    // MARK: - 二、布料信息（图标盒卡）

    /// 子编号↔布料的关联是派生的（模型没有专门的关联表）：
    /// 关联操作 = 把该子编号追加到被选布料的 subCodes（去重）。
    /// 这里展示除本布料外、subCodes 里含有该子编号的第一块布料名。
    private func linkedFabricName(forSubCode sub: String) -> String? {
        store.fabrics.first { $0.id != fabric.id && $0.subCodes.contains(sub) }?.displayName
    }

    private var fabricInfoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                iconInfoRow(icon: "barcode", label: "编号",
                            value: fabric.code.isEmpty ? "未填" : fabric.code)
                // 子编号：点"＋加子编号"直接自动续号（无输入框）；每行右侧
                // "关联"按钮选一块布料，把该子编号追加到对方 subCodes（去重），
                // 实现子编号↔布料的关联；已关联的布料名显示在子编号下方。
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("子编号").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Button("＋加子编号") {
                            let next = store.nextSubCode(for: fabric)
                            if !next.isEmpty && !fabric.subCodes.contains(next) {
                                fabric.subCodes.append(next)
                                fabric.updatedAt = Date()
                                store.save()
                            }
                        }
                        .font(.subheadline)
                        .foregroundColor(Design.accent)
                        .buttonStyle(.plain)
                    }
                    ForEach(fabric.subCodes, id: \.self) { sub in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(sub).font(.subheadline)
                                if let linkedName = linkedFabricName(forSubCode: sub) {
                                    Text("已关联：\(linkedName)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button("关联") {
                                linkingSubCode = sub
                                showingSubCodePicker = true
                            }
                            .font(.caption)
                            .foregroundColor(Design.accent)
                            .buttonStyle(.plain)
                            Button(action: {
                                fabric.subCodes.removeAll { $0 == sub }
                                fabric.updatedAt = Date()
                                store.save()
                            }) {
                                Image(systemName: "trash").foregroundColor(.red).font(.footnote)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.leading, 56)
                .padding(.vertical, 8)
                Divider()
                iconInfoRow(icon: "cube", label: "材质",
                            value: fabric.materialName.isEmpty ? "未填" : fabric.materialName)
                Divider()
                colorRow
                Divider()
                iconInfoRow(icon: "bag", label: "渠道",
                            value: fabric.channelName.isEmpty ? "未填" : fabric.channelName,
                            subtext: fabric.merchantName.isEmpty ? nil : "商家：\(fabric.merchantName)")
                Divider()
                let tagNames = store.tags(for: fabric).map { $0.name }
                iconInfoRow(icon: "tag", label: "标签",
                            value: tagNames.isEmpty ? "未填" : tagNames.joined(separator: "、"))
                Divider()
                HStack(spacing: 12) {
                    iconBox("briefcase")
                    Text("关联成品").font(.subheadline).foregroundColor(.secondary)
                    Spacer()
                    Text(linkedWorks.isEmpty ? "暂无" : "\(linkedWorks.count) 个")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(linkedWorks.isEmpty ? .secondary : .primary)
                }
                .padding(.vertical, 6)
                if !linkedWorks.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(linkedWorks) { work in
                            Text(work.name.isEmpty ? "未命名成品" : work.name)
                                .font(.subheadline)
                        }
                    }
                    .padding(.leading, 56)
                    .padding(.bottom, 4)
                }
            }
        }
    }

    /// 颜色行：图标盒 + 名称，下方是色系图标单选（与表单网格同渲染，
    /// 含"其他"的色轮图标）；点选即写回 fabric.colorName，并同步
    /// codeSegments 的色系级（与布料表单同逻辑）。
    private var colorRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(themeAccent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    colorSwatchView
                }
                Text("颜色").font(.subheadline).foregroundColor(.secondary)
                Spacer()
                Text(fabric.colorName.isEmpty ? "未填" : fabric.colorName)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(fabric.colorName.isEmpty ? .secondary : .primary)
            }
            let items = (store.levelOrder().first(where: { $0.kind == "color" })?.items ?? [])
                .filter { $0.enabled }
            if !items.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            let selected = fabric.colorName == item.name
                            Button(action: { applyColor(item) }) {
                                VStack(spacing: 4) {
                                    CodeItemIconView(icon: item.icon, size: 30)
                                    Text(item.name)
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(6)
                                .background(selected ? themeAccent.opacity(0.12) : Color.clear)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(selected ? themeAccent : Color.gray.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("颜色 \(item.name)")
                        }
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }

    /// 点选色系图标：写回颜色名，并把该色的 code 写进 codeSegments 的色系级
    ///（与 FabricEditView 表单里"颜色单选联动编号体系"的逻辑一致）。
    private func applyColor(_ item: CodeItem) {
        fabric.colorName = item.name
        if let idx = store.levelOrder().firstIndex(where: { $0.kind == "color" }) {
            var segs = fabric.codeSegments.isEmpty ? store.parseSegments(code: fabric.code) : fabric.codeSegments
            while segs.count <= idx { segs.append("") }
            segs[idx] = item.code
            fabric.codeSegments = segs
        }
        fabric.updatedAt = Date()
        store.save()
    }

    @ViewBuilder
    private var colorSwatchView: some View {
        if !fabric.colorName.isEmpty, let item = store.colorItem(forName: fabric.colorName) {
            if item.code == "M" {
                ColorWheelIcon(size: 24)
            } else if let c = Design.fabricColor(item.code) {
                Circle()
                    .fill(c)
                    .frame(width: 24, height: 24)
                    .overlay(Circle().stroke(Color.gray.opacity(0.35), lineWidth: 1))
            } else {
                Image(systemName: "tag").foregroundColor(themeAccent).font(.headline)
            }
        } else {
            Image(systemName: "tag").foregroundColor(themeAccent).font(.headline)
        }
    }

    // MARK: - 三、其他信息（图标盒卡）

    private var otherInfoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                iconInfoRow(icon: "doc.text", label: "成分",
                            value: fabric.composition.isEmpty ? "未填" : fabric.composition)
                Divider()
                iconInfoRow(icon: "scalemass", label: "克重",
                            value: fabric.weightGsm.map { "\(String(format: "%.0f", $0)) g/m²" } ?? "未填")
                Divider()
                iconInfoRow(icon: "drop", label: "缩水率",
                            value: fabric.shrinkagePct.map { "\(String(format: "%.1f", $0))%" } ?? "未填")
                Divider()
                iconInfoRow(icon: "sparkles", label: "洗涤方式",
                            value: fabric.washing.isEmpty ? "未填" : fabric.washing.joined(separator: "、"))
                Divider()
                if fabric.usageNotes.isEmpty {
                    iconInfoRow(icon: "note.text", label: "用途备注", value: "未填")
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 12) {
                            iconBox("note.text")
                            Text("用途备注").font(.subheadline).foregroundColor(.secondary)
                        }
                        Text(fabric.usageNotes).font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }
                Divider()
                if let unit = fabric.unitPrice {
                    iconInfoRow(icon: "yensign", label: "单价",
                                value: "¥\(String(format: "%.2f", unit)) 元/米",
                                valueColor: Design.priceAccent)
                    Divider()
                }
                iconInfoRow(icon: "calendar", label: "购买日期",
                            value: fabric.purchaseDate.map { CSVValues.dateString($0) } ?? "未填")
                Divider()
                iconInfoRow(icon: "calendar.badge.plus", label: "创建时间",
                            value: CSVValues.dateString(fabric.createdAt))
            }
        }
    }

    // MARK: - 四、消耗记录（入口卡：点整卡进专属记录页；明细行/编辑/删除都在记录页里）

    private var usageCard: some View {
        CardView {
            NavigationLink(destination: UsageRecordsPageView(fabric: fabric)) {
                HStack(spacing: 12) {
                    RecordIconBox(icon: "scissors", accent: themeAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用记录").font(.headline).foregroundColor(.primary)
                        Text("共 \(usageRecords.count) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Text("记一笔")
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeAccent)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 五、出售记录（入口卡：点整卡进专属记录页；明细行/编辑/删除都在记录页里）

    private var saleCard: some View {
        CardView {
            NavigationLink(destination: SaleRecordsPageView(fabric: fabric)) {
                HStack(spacing: 12) {
                    RecordIconBox(icon: "yensign", accent: themeAccent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("出售记录").font(.headline).foregroundColor(.primary)
                        Text("共 \(saleRecords.count) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 2) {
                        Text("登记出售")
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeAccent)
                }
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - 六、脑洞与备注（备注 inline 编辑 + 关联的 Brainstorm 实体）

    private var brainstormCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("备注").font(.headline)
                    Spacer()
                    Button(action: {
                        editingNote = fabric.note
                        isEditingNote = true
                    }) {
                        Image(systemName: "pencil")
                            .font(.subheadline)
                            .foregroundColor(themeAccent)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(themeAccent.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("编辑备注")
                }
                .padding(.bottom, 6)
                if isEditingNote {
                    TextEditor(text: $editingNote)
                        .frame(minHeight: 90)
                        .padding(6)
                        .background(Color(UIColor.tertiarySystemGroupedBackground))
                        .cornerRadius(8)
                    HStack {
                        Button("取消") { isEditingNote = false }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("保存") {
                            fabric.note = editingNote
                            fabric.updatedAt = Date()
                            store.save()
                            isEditingNote = false
                        }
                        .buttonStyle(.plain)
                        .fontWeight(.semibold)
                        .foregroundColor(themeAccent)
                    }
                    .font(.subheadline)
                    .padding(.top, 6)
                } else {
                    Text(fabric.note.isEmpty ? "暂无备注" : fabric.note)
                        .font(.subheadline)
                        .foregroundColor(fabric.note.isEmpty ? .secondary : .primary)
                        .padding(.bottom, 4)
                }
                // 关联脑洞：多选（store.brainstorms 全量列表，不限数量），
                // 选中即把本布料 id 写入 Brainstorm.linkedFabricIds（去重）。
                Button(action: { showingBrainstormPicker = true }) {
                    HStack {
                        Image(systemName: "lightbulb")
                        Text(linkedBrainstorms.isEmpty ? "关联脑洞" : "关联脑洞（已关联 \(linkedBrainstorms.count) 个）")
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                    }
                    .font(.subheadline)
                    .foregroundColor(themeAccent)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关联脑洞")
                if !linkedBrainstorms.isEmpty {
                    Divider()
                        .padding(.vertical, 8)
                    ForEach(linkedBrainstorms) { b in
                        NavigationLink(destination: BrainstormDetailView(brainstorm: b)) {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(b.title.isEmpty ? "未命名脑洞" : b.title).font(.subheadline)
                                    Text(b.status).font(.caption).foregroundColor(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 7)
                        }
                        .buttonStyle(.plain)
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - 分享 / 长图

    private var fabricSummary: String {
        var lines: [String] = []
        if !fabric.code.isEmpty { lines.append("编号：\(fabric.code)") }
        lines.append("名称：\(fabric.displayName)")
        lines.append("已消耗：\(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
        lines.append("已售出：\(LengthUnitHelper.format(sold, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
        if fabric.hasPurchaseLength { lines.append("剩余：\(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))") }
        if !fabric.materialName.isEmpty { lines.append("材质：\(fabric.materialName)") }
        if !fabric.channelName.isEmpty { lines.append("渠道：\(fabric.channelName)") }
        if !fabric.note.isEmpty { lines.append("备注：\(fabric.note)") }
        return lines.joined(separator: "\n")
    }

    @MainActor
    private func generateLongImage() {
        let view = LongDetailSummaryView(fabric: fabric, store: store)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.uiImage {
            longImage = image
            showingLongImage = true
        }
    }
}

// MARK: - 专属记录页（REQ 5）：从详情入口卡经 NavigationLink 推进来，
// 跑在已有的 NavigationStack 里。添加表单用 NavigationLink push
//（标题"添加使用记录/添加出售记录"，返回键回到记录页）；
// 编辑用 sheet（复用 UsageFormView / SaleFormView 的 record: 初始化）。

/// 子编号"关联"用的布料选择器：点一块布料，把 subCode 追加到对方 subCodes
///（去重），双方 updatedAt 刷新后 store.save() 一次落盘。
struct SubCodeFabricPickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    var subCode: String

    var body: some View {
        List {
            ForEach(store.fabrics.filter { $0.id != fabric.id }) { other in
                Button(action: {
                    if !subCode.isEmpty && !other.subCodes.contains(subCode) {
                        other.subCodes.append(subCode)
                        other.updatedAt = Date()
                    }
                    fabric.updatedAt = Date()
                    store.save()
                    dismiss()
                }) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(other.displayName).foregroundColor(.primary)
                            if !other.code.isEmpty {
                                Text(other.code).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        Spacer()
                        if !subCode.isEmpty && other.subCodes.contains(subCode) {
                            Image(systemName: "checkmark").foregroundColor(Design.accent)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .navigationTitle("关联布料")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
        }
    }
}

/// 脑洞与备注 → 关联脑洞：store.brainstorms 全量多选（不限数量），
/// 勾选即把本布料 id 写入 Brainstorm.linkedFabricIds（去重），取消勾选即移除。
struct FabricBrainstormLinkPickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    var body: some View {
        List {
            if store.brainstorms.isEmpty {
                Text("还没有脑洞，去脑洞 Tab 先记一条").foregroundColor(.secondary)
            } else {
                ForEach(store.brainstorms) { b in
                    let linked = b.linkedFabricIds.contains(fabric.id)
                    Button(action: {
                        if linked {
                            b.linkedFabricIds.removeAll { $0 == fabric.id }
                        } else {
                            b.linkedFabricIds.append(fabric.id)
                        }
                        store.save()
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(b.title.isEmpty ? "未命名脑洞" : b.title).foregroundColor(.primary)
                                Text(b.status).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            if linked {
                                Image(systemName: "checkmark").foregroundColor(themeAccent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle("关联脑洞")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
    }
}

/// 使用记录专属页：摘要卡（名称/状态/已用/可用大数字/共长/进度条）+
/// 记录行（日期/长度/备注/删除，点行进编辑 sheet）+ 空态；
/// 右上 + 与空态大按钮都 push 添加页。
struct UsageRecordsPageView: View {
    @EnvironmentObject private var store: Store
    var fabric: Fabric
    @State private var editingUsage: UsageRecord?
    private var records: [UsageRecord] { store.usageRecords(for: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var usedSummary: String {
        let base = "已使用 \(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))"
        if fabric.hasPurchaseLength && fabric.length > 0 {
            return "\(base) · \(Int(fabric.usedLength / fabric.length * 100))%"
        }
        return base
    }

    /// 灰底状态胶囊（与原型一致）。
    private var statusCapsule: some View {
        HStack(spacing: 4) {
            Circle()
                .stroke(Color.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
            Text(store.status(for: fabric))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.gray.opacity(0.12)))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fabric.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                statusCapsule
            }
            Text(usedSummary)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(themeAccent)
            if fabric.hasPurchaseLength {
                HStack(alignment: .bottom) {
                    HStack(alignment: .lastTextBaseline, spacing: 3) {
                        Text(LengthUnitHelper.format(remaining, unit: store.lengthUnit))
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundColor(themeAccent)
                        Text("\(LengthUnitHelper.suffix(unit: store.lengthUnit))可用")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("共 \(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                if fabric.length > 0 {
                    ProgressBarView(fraction: remaining / fabric.length, height: 8, accent: themeAccent)
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeAccent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "scissors")
                    .font(.title)
                    .foregroundColor(themeAccent)
            }
            .padding(.top, 24)
            Text("还没有使用记录")
                .font(.headline)
            Text("添加记录后，布长和使用状态会自动更新")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink(destination: UsageFormView(fabric: fabric)) {
                HStack {
                    Spacer()
                    Image(systemName: "plus")
                    Text("添加第一条记录").fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .background(themeAccent)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                if records.isEmpty {
                    emptyState
                } else {
                    CardView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(records) { record in
                                HStack(alignment: .top, spacing: 8) {
                                    Button(action: { editingUsage = record }) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(CSVValues.dateString(record.date)).font(.subheadline)
                                                Spacer()
                                                Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                            }
                                            if !record.note.isEmpty {
                                                Text(record.note).font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { store.removeUsageAndRestore(record) }) {
                                        Image(systemName: "trash").foregroundColor(.red).font(.footnote)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 8)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle("使用记录")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: UsageFormView(fabric: fabric)) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加使用记录")
            }
        }
        .sheet(item: $editingUsage) { record in
            NavigationStack { UsageFormView(fabric: fabric, record: record) }
        }
    }
}

/// 出售记录专属页：摘要卡（名称/状态/已售米·件/实收/双色进度条）+
/// 记录行（日期/长度或份数·金额/渠道/备注/删除，点行进编辑 sheet）+ 空态；
/// 右上 + 与空态大按钮都 push 添加页。
struct SaleRecordsPageView: View {
    @EnvironmentObject private var store: Store
    var fabric: Fabric
    @State private var editingSale: SaleRecord?
    private var records: [SaleRecord] { store.saleRecords(for: fabric.id) }
    private var sold: Double { store.soldLength(for: fabric.id) }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var totalPieces: Int { records.filter { $0.isPieces }.reduce(0) { $0 + $1.pieces } }
    private var totalRevenue: Double { records.reduce(0) { $0 + $1.price } }

    private var statusCapsule: some View {
        HStack(spacing: 4) {
            Circle()
                .stroke(Color.secondary, lineWidth: 1.5)
                .frame(width: 8, height: 8)
            Text(store.status(for: fabric))
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Capsule().fill(Color.gray.opacity(0.12)))
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(fabric.displayName)
                    .font(.headline)
                    .lineLimit(2)
                Spacer()
                statusCapsule
            }
            HStack(alignment: .bottom) {
                Text("已售出 \(LengthUnitHelper.format(sold, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit)) · \(totalPieces) 件")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(themeAccent)
                Spacer()
                Text("实收 ¥\(String(format: "%.2f", totalRevenue))")
                    .font(.subheadline)
                    .fontWeight(.bold)
                    .foregroundColor(Design.priceAccent)
            }
            if fabric.hasPurchaseLength && fabric.length > 0 {
                DualProgressBarView(
                    usedFraction: fabric.usedLength / fabric.length,
                    soldFraction: sold / fabric.length,
                    height: 8,
                    usedColor: themeAccent
                )
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(themeAccent.opacity(0.12))
                    .frame(width: 72, height: 72)
                Image(systemName: "scissors")
                    .font(.title)
                    .foregroundColor(themeAccent)
            }
            .padding(.top, 24)
            Text("还没有出售记录")
                .font(.headline)
            Text("添加记录后，售出数量和布料状态会自动更新")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            NavigationLink(destination: SaleFormView(fabric: fabric)) {
                HStack {
                    Spacer()
                    Image(systemName: "plus")
                    Text("添加第一条记录").fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.white)
                .padding(.vertical, 14)
                .background(themeAccent)
                .cornerRadius(14)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .padding(20)
        .background(Color(.systemBackground))
        .cornerRadius(16)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                if records.isEmpty {
                    emptyState
                } else {
                    CardView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(records) { record in
                                HStack(alignment: .top, spacing: 8) {
                                    Button(action: { editingSale = record }) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack {
                                                Text(CSVValues.dateString(record.date)).font(.subheadline)
                                                Spacer()
                                                if record.isPieces {
                                                    Text("\(record.pieces) 件 · ¥\(String(format: "%.2f", record.price))")
                                                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                                                } else {
                                                    Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit)) · ¥\(String(format: "%.2f", record.price))")
                                                        .font(.subheadline).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                                                }
                                            }
                                            if !record.channel.isEmpty {
                                                Text(record.channel).font(.caption).foregroundColor(.secondary)
                                            }
                                            if !record.note.isEmpty {
                                                Text(record.note).font(.caption).foregroundColor(.secondary)
                                            }
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    Button(action: { store.deleteSaleRecord(record) }) {
                                        Image(systemName: "trash").foregroundColor(.red).font(.footnote)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.top, 8)
                                }
                                .padding(.vertical, 8)
                                Divider()
                            }
                        }
                    }
                }
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle("出售记录")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink(destination: SaleFormView(fabric: fabric)) {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("添加出售记录")
            }
        }
        .sheet(item: $editingSale) { record in
            NavigationStack { SaleFormView(fabric: fabric, record: record) }
        }
    }
}

// 长图渲染用视图（固定宽度，竖向长摘要；不依赖屏幕尺寸）。
struct LongDetailSummaryView: View {
    var fabric: Fabric
    var store: Store
    private var sold: Double { store.soldLength(for: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("布仓 · 布料详情").font(.headline)
            if !fabric.code.isEmpty { Text("编号：\(fabric.code)") }
            Text("名称：\(fabric.displayName)")
            Text("已消耗：\(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
            Text("已售出：\(LengthUnitHelper.format(sold, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
            if fabric.hasPurchaseLength { Text("剩余：\(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))") }
            if fabric.hasPurchaseLength { Text("布长：\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))") }
            if fabric.width > 0 { Text("幅宽：\(String(format: "%.0f", fabric.widthCm)) 厘米") }
            if fabric.hasTotalPrice { Text("总价：¥\(String(format: "%.2f", fabric.purchasePrice))") }
            if let unit = fabric.unitPrice { Text("单价：¥\(String(format: "%.2f", unit)) / 米") }
            if !fabric.materialName.isEmpty { Text("材质：\(fabric.materialName)") }
            if !fabric.channelName.isEmpty { Text("渠道：\(fabric.channelName)") }
            let tagNames = store.tags(for: fabric).map { $0.name }
            if !tagNames.isEmpty { Text("标签：\(tagNames.joined(separator: "、"))") }
            if !fabric.note.isEmpty { Text("备注：\(fabric.note)") }
            Spacer()
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.white)
    }
}

struct FabricEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric?
    @State private var code: String
    @State private var name: String
    @State private var material: String
    @State private var customMaterial: String
    @State private var composition: String
    @State private var colorName: String
    @State private var widthCmText: String
    @State private var lengthText: String
    @State private var priceText: String
    @State private var weightText: String
    @State private var shrinkageText: String
    @State private var washing: Set<String>
    @State private var channel: String
    @State private var merchantName: String
    @State private var usageNotes: String
    @State private var note: String
    @State private var subCodes: [String]
    @State private var codeSegments: [String]
    @State private var purchaseDate: Date
    @State private var fillPurchaseDate: Bool
    @State private var isFavorite: Bool
    @State private var selectedTagIDs: Set<UUID>
    @State private var imageNames: [String]
    @State private var videoNames: [String]
    @State private var errorMessage: String?
    @State private var lengthInitialized = false
    @State private var showingCodeGenerator = false
    @State private var codeGenTargetSubIndex: Int?
    private let editingId: UUID
    private let originalImageNames: [String]
    private let originalVideoNames: [String]
    private let washingOptions = ["水洗", "干洗", "可熨烫", "不可熨烫", "低温水洗", "阴干"]

    init(fabric: Fabric?) {
        self.fabric = fabric
        self.editingId = fabric?.id ?? UUID()
        self.originalImageNames = fabric?.imageFileNames ?? []
        self.originalVideoNames = fabric?.videoFileNames ?? []
        _code = State(initialValue: fabric?.code ?? "")
        _name = State(initialValue: fabric?.name ?? "")
        _material = State(initialValue: fabric?.materialName ?? "")
        _customMaterial = State(initialValue: "")
        _composition = State(initialValue: fabric?.composition ?? "")
        _colorName = State(initialValue: fabric?.colorName ?? "")
        _widthCmText = State(initialValue: fabric == nil || fabric!.width == 0 ? "" : String(format: "%.0f", fabric!.widthCm))
        // 长度初始值先按米填，body 的 onAppear 会按当前设置单位换算一次
        //（init 里读不到 store，只能先占位，不能在 init 里直接换算）。
        _lengthText = State(initialValue: fabric == nil || !fabric!.hasPurchaseLength ? "" : String(fabric!.length))
        _priceText = State(initialValue: fabric == nil || !fabric!.hasTotalPrice ? "" : String(fabric!.purchasePrice))
        _weightText = State(initialValue: fabric?.weightGsm.map { String($0) } ?? "")
        _shrinkageText = State(initialValue: fabric?.shrinkagePct.map { String($0) } ?? "")
        _washing = State(initialValue: Set(fabric?.washing ?? []))
        _channel = State(initialValue: fabric?.channelName ?? "")
        _merchantName = State(initialValue: fabric?.merchantName ?? "")
        _usageNotes = State(initialValue: fabric?.usageNotes ?? "")
        _note = State(initialValue: fabric?.note ?? "")
        _subCodes = State(initialValue: fabric?.subCodes ?? [])
        _codeSegments = State(initialValue: fabric?.codeSegments ?? [])
        _purchaseDate = State(initialValue: fabric?.purchaseDate ?? Date())
        _fillPurchaseDate = State(initialValue: fabric?.purchaseDate != nil)
        _isFavorite = State(initialValue: fabric?.isFavorite ?? false)
        _selectedTagIDs = State(initialValue: Set(fabric?.tagIds ?? []))
        _imageNames = State(initialValue: fabric?.imageFileNames ?? [])
        _videoNames = State(initialValue: fabric?.videoFileNames ?? [])
    }

    private func save() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        let selfId = fabric?.id ?? UUID()
        // 主编号 + 每个子编号，对照全部其他布料的主编号与子编号（不含自身）。
        var codesToCheck = [trimmedCode] + subCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        codesToCheck = Array(Set(codesToCheck))
        for candidate in codesToCheck where !candidate.isEmpty {
            if let conflict = store.codeConflict(code: candidate, excluding: selfId) {
                errorMessage = "编号重复，禁止保存：编号 \(candidate) 已被「\(conflict.fabric.displayName)」使用（主编号/子编号冲突）"
                return
            }
        }
        // 同一块布料内主编号与子编号也不能重复。
        if !trimmedCode.isEmpty && subCodes.contains(trimmedCode) {
            errorMessage = "编号重复，禁止保存：子编号不能与主编号相同"; return
        }
        let materialValue = customMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? material.trimmingCharacters(in: .whitespacesAndNewlines) : customMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
        // 长度输入按当前设置单位换算回米；留空 = 未填，不显示进度条。
        let lengthDisplay = Double(lengthText) ?? 0
        let lengthMetres = lengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0 : LengthUnitHelper.fromDisplay(lengthDisplay, unit: store.lengthUnit)
        let widthCm = Double(widthCmText) ?? 0
        let widthMetres = widthCm / 100
        let price = Double(priceText) ?? 0
        if lengthMetres < 0 || widthMetres < 0 || price < 0 {
            errorMessage = "长度、幅宽、价格不能为负数"; return
        }
        if let existing = fabric, lengthMetres < existing.usedLength && !lengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = "买入长度不能小于已用长度"; return
        }
        if !materialValue.isEmpty && !store.materialOptions.contains(materialValue) {
            store.materialOptions.append(materialValue)
        }
        if !channel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.channelOptions.contains(channel) {
            store.channelOptions.append(channel)
        }
        let tagIDsArray = store.tags.filter { selectedTagIDs.contains($0.id) }.map { $0.id }
        if let existing = fabric {
            existing.code = trimmedCode; existing.name = name; existing.materialName = materialValue
            existing.composition = composition; existing.colorName = colorName
            existing.width = widthMetres; existing.length = lengthMetres
            existing.hasPurchaseLength = !lengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            existing.purchasePrice = price; existing.hasTotalPrice = !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            existing.pricePerMeter = (existing.hasPurchaseLength && lengthMetres > 0) ? price / lengthMetres : 0
            existing.weightGsm = Double(weightText); existing.shrinkagePct = Double(shrinkageText)
            existing.washing = Array(washing); existing.channelName = channel
            existing.merchantName = merchantName
            existing.subCodes = subCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
            existing.codeSegments = codeSegments
            existing.usageNotes = usageNotes; existing.note = note
            existing.purchaseDate = fillPurchaseDate ? purchaseDate : nil; existing.isFavorite = isFavorite
            existing.tagIds = tagIDsArray; existing.updatedAt = Date()
            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
            existing.imageFileNames = imageNames
            for oldName in originalVideoNames where !videoNames.contains(oldName) { FabricVideoStore.delete(named: oldName) }
            existing.videoFileNames = videoNames
            store.save()
        } else {
            let newFabric = Fabric(
                name: name, length: lengthMetres, width: widthMetres,
                purchasePrice: price, pricePerMeter: 0, purchaseDate: fillPurchaseDate ? purchaseDate : nil,
                note: note, tagIds: tagIDsArray, imageFileNames: imageNames,
                code: trimmedCode, materialName: materialValue, composition: composition,
                colorName: colorName, weightGsm: Double(weightText), shrinkagePct: Double(shrinkageText),
                washing: Array(washing), usageNotes: usageNotes, channelName: channel,
                merchantName: merchantName,
                subCodes: subCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                videoFileNames: videoNames, codeSegments: codeSegments,
                hasTotalPrice: !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                hasPurchaseLength: !lengthText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            )
            newFabric.isFavorite = isFavorite
            if newFabric.hasPurchaseLength && lengthMetres > 0 { newFabric.pricePerMeter = price / lengthMetres }
            store.addFabric(newFabric)
        }
        dismiss()
    }

    private func cancelEditing() {
        for name in imageNames where !originalImageNames.contains(name) { FabricImageStore.delete(named: name) }
        for name in videoNames where !originalVideoNames.contains(name) { FabricVideoStore.delete(named: name) }
        dismiss()
    }

    /// 生成表要覆盖的目标编号：子编号行的生成对应那一行，主编号的生成对应主编号框。
    private var currentGeneratorTargetCode: String {
        if let idx = codeGenTargetSubIndex, subCodes.indices.contains(idx) { return subCodes[idx] }
        return code
    }

    var body: some View {
        Form {
            // (1) 图片板块：照片 + 视频（相册选视频，详情里可播放）
            Section("图片板块") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
                FabricVideoEditor(videoNames: $videoNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            // (2) 基础信息卡片
            Section("基础信息卡片（全部可留空，编号唯一）") {
                LabeledTextField(label: "编号", placeholder: "选填", text: $code)
                Button("生成编号") { codeGenTargetSubIndex = nil; showingCodeGenerator = true }
                Text("编号体系：设置 > 编号体系里定颜色体系与纹样；生成时选颜色与纹样，序号按该组合递增。").font(.caption).foregroundColor(.secondary)
                LabeledTextField(label: "名称", placeholder: "选填", text: $name)
                LabeledTextField(label: "幅宽", placeholder: "点击输入", text: $widthCmText, keyboardType: .decimalPad, unit: "厘米")
                LabeledTextField(label: "长度", placeholder: "留空=未填", text: $lengthText, keyboardType: .decimalPad, unit: store.lengthUnit)
                HStack {
                    Text("子编号").font(.subheadline)
                    Spacer()
                    Button("新增子编号") { subCodes.append("") }
                    Button("＋加子编号") {
                        let next = store.nextSubCode(for: Fabric(id: editingId, code: code.trimmingCharacters(in: .whitespacesAndNewlines)))
                        if !next.isEmpty && !subCodes.contains(next) { subCodes.append(next) }
                    }
                }
                if subCodes.isEmpty {
                    Text("暂无子编号。子编号也可关联布料，同样唯一。").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(subCodes.indices, id: \.self) { idx in
                        HStack {
                            LabeledTextField(label: "子编号", placeholder: "选填", text: $subCodes[idx])
                            Button("生成") { codeGenTargetSubIndex = idx; showingCodeGenerator = true }
                            Button(action: { subCodes.remove(at: idx) }) { Image(systemName: "trash") }.foregroundColor(.red)
                        }
                    }
                }
                if store.tags.isEmpty {
                    Text("还没有标签，去设置里先加标签").foregroundColor(.secondary)
                } else {
                    ForEach(store.tags.sorted { $0.sortOrder < $1.sortOrder }) { tag in
                        Button(action: {
                            if selectedTagIDs.contains(tag.id) { selectedTagIDs.remove(tag.id) } else { selectedTagIDs.insert(tag.id) }
                        }) {
                            HStack { Text(tag.name); Spacer(); if selectedTagIDs.contains(tag.id) { Image(systemName: "checkmark") } }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            // (3) 购买信息
            Section("购买信息") {
                Picker("渠道", selection: $channel) {
                    Text("未填").tag("")
                    ForEach(store.channelOptions, id: \.self) { Text($0).tag($0) }
                }
                LabeledTextField(label: "商家", placeholder: "选填", text: $merchantName)
                LabeledTextField(label: "总价", placeholder: "留空=不计入", text: $priceText, keyboardType: .decimalPad, unit: "元")
                Toggle("填写购买日期", isOn: $fillPurchaseDate)
                if fillPurchaseDate {
                    DatePicker("购入日期", selection: $purchaseDate, displayedComponents: .date)
                } else {
                    Text("购买日期未填，详情显示“未填”。").font(.caption).foregroundColor(.secondary)
                }
            }
            // 更多
            Section("更多") {
                Picker("材质", selection: $material) {
                    Text("未填").tag("")
                    ForEach(store.materialOptions, id: \.self) { Text($0).tag($0) }
                }
                LabeledTextField(label: "自定义材质", placeholder: "选填", text: $customMaterial)
                LabeledTextField(label: "成分", placeholder: "如 棉80%/涤纶20%", text: $composition)
                Text("颜色（单选，来自设置 > 编号体系 > 色系）").font(.caption).foregroundColor(.secondary)
                let colorItems = (store.levelOrder().first(where: { $0.kind == "color" })?.items ?? []).filter { $0.enabled }
                if colorItems.isEmpty {
                    Text("色系表为空，去设置 > 编号体系里添加").foregroundColor(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
                        ForEach(colorItems) { item in
                            Button(action: {
                                colorName = item.name
                                // 颜色单选联动编号体系：把选中色的代码写进待定 codeSegments
                                // 的色系级位置，生成器预填时就能延续该色的序号规则。
                                if let idx = store.levelOrder().firstIndex(where: { $0.kind == "color" }) {
                                    var segs = codeSegments.isEmpty ? store.parseSegments(code: code) : codeSegments
                                    while segs.count <= idx { segs.append("") }
                                    segs[idx] = item.code
                                    codeSegments = segs
                                }
                            }) {
                                VStack(spacing: 4) {
                                    CodeItemIconView(icon: item.icon, size: 32)
                                    Text(item.name).font(.caption).foregroundColor(colorName == item.name ? Design.accent : .primary)
                                    if !item.code.isEmpty {
                                        Text(item.code).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(6)
                                .background(colorName == item.name ? Design.accentSoft : Color.clear)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(colorName == item.name ? Design.accent : Color.gray.opacity(0.25), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if !colorName.isEmpty {
                    Button("清除颜色") { colorName = "" }
                }
                LabeledTextField(label: "克重", placeholder: "选填", text: $weightText, keyboardType: .decimalPad, unit: "g/m²")
                LabeledTextField(label: "缩水率", placeholder: "选填", text: $shrinkageText, keyboardType: .decimalPad, unit: "%")
                ForEach(washingOptions, id: \.self) { option in
                    Button(action: {
                        if washing.contains(option) { washing.remove(option) } else { washing.insert(option) }
                    }) {
                        HStack { Text(option); Spacer(); if washing.contains(option) { Image(systemName: "checkmark") } }
                    }
                    .foregroundColor(.primary)
                }
                LabeledMultilineField(label: "用途备注", text: $usageNotes)
                LabeledMultilineField(label: "备注", text: $note)
                Toggle(isOn: $isFavorite) {
                    Label("收藏", systemImage: isFavorite ? "star.fill" : "star")
                }
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .sheet(isPresented: $showingCodeGenerator) {
            NavigationStack {
                CodeGeneratorSheet(
                    fabric: Fabric(id: editingId, code: code.trimmingCharacters(in: .whitespacesAndNewlines), codeSegments: codeSegments),
                    currentCode: currentGeneratorTargetCode,
                    onConfirm: { generated, segments, colorNameValue in
                        if let idx = codeGenTargetSubIndex, subCodes.indices.contains(idx) {
                            subCodes[idx] = generated
                        } else {
                            code = generated
                            codeSegments = segments
                            if !colorNameValue.isEmpty { colorName = colorNameValue }
                        }
                        showingCodeGenerator = false
                    }
                )
            }
        }
        .navigationTitle(fabric == nil ? "新增布料" : "编辑布料")
        .onAppear {
            if !lengthInitialized, let f = fabric, f.hasPurchaseLength {
                lengthText = String(format: "%.2f", f.length * LengthUnitHelper.factorToDisplay(unit: store.lengthUnit))
                lengthInitialized = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消", action: cancelEditing) }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
    }
}

// V8 多级编号生成表（重写）：按设置 > 编号体系里的启用层级顺序逐步选择。
// 色系 / 纹样 / 幅宽从条目表单选（只显示 enabled 条目）；序号按
// 色系+纹样+幅宽 范围自动取下一个空号，也可在 01–99 里手动点选
// （已占用置灰）；99 个全满时可手动输入 ≥1 的序号。
// 幅宽在序号之后选：换幅宽后若已选序号被新范围占用，自动顺延并提示
// 「已按 {色}{纹}-*-{宽} 调整为 {nn}」。
// 确认时：编号冲突（store.codeConflict）直接拦截并点名冲突布料；
// 若目标已有非空且不同的编号，先弹确认框再覆盖；
// 同时把选中的颜色名回填给布料（colorName 联动）。
struct CodeGeneratorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    var currentCode: String
    /// (生成的编号, 各段数组, 选中的颜色名)
    var onConfirm: (String, [String], String) -> Void

    @State private var values: [UUID: String] = [:]
    @State private var selectedColorName: String = ""
    @State private var sequenceNumber: Int?
    @State private var sequenceAutoPicked: Bool = false
    @State private var adjustNote: String?
    @State private var manualSequenceText: String = ""
    @State private var didInit = false
    @State private var errorMessage: String?
    @State private var showingOverwriteAlert = false

    init(fabric: Fabric, currentCode: String = "", onConfirm: @escaping (String, [String], String) -> Void) {
        self.fabric = fabric
        self.currentCode = currentCode
        self.onConfirm = onConfirm
    }

    private var levels: [CodeLevel] { store.levelOrder() }
    private func level(kind: String) -> CodeLevel? { levels.first { $0.kind == kind } }
    private var sequenceLevel: CodeLevel? { level(kind: "sequence") }
    private func codeFor(kind: String) -> String {
        guard let lv = level(kind: kind) else { return "" }
        return values[lv.id] ?? ""
    }
    private var scopeReady: Bool {
        !codeFor(kind: "color").isEmpty && !codeFor(kind: "pattern").isEmpty && !codeFor(kind: "width").isEmpty
    }

    /// 当前 色系+纹样+幅宽 范围的已占序号（当前布料自身的旧编号若落在此范围则排除）。
    private func occupiedForCurrentScope() -> Set<Int> {
        let cc = codeFor(kind: "color"), pc = codeFor(kind: "pattern"), wc = codeFor(kind: "width")
        var occ = store.occupiedSequences(colorCode: cc, patternCode: pc, widthCode: wc)
        if store.segmentForKind(fabric, kind: "color") == cc,
           store.segmentForKind(fabric, kind: "pattern") == pc,
           store.segmentForKind(fabric, kind: "width") == wc,
           let own = Int(store.segmentForKind(fabric, kind: "sequence")) {
            occ.remove(own)
        }
        return occ
    }

    private func nextFree(_ occ: Set<Int>) -> Int {
        var n = 1
        while occ.contains(n) { n += 1 }
        return n
    }

    private func formattedSequence(_ n: Int) -> String {
        let digits = sequenceLevel?.digits ?? 2
        return String(format: "%0\(digits)d", n)
    }

    private func pickValue(_ lv: CodeLevel, _ value: String, colorName: String? = nil) {
        values[lv.id] = value
        if let colorName { selectedColorName = colorName }
        errorMessage = nil
        if lv.kind == "color" || lv.kind == "pattern" || lv.kind == "width" {
            refreshSequenceAfterScopeChange()
        }
    }

    /// 色系/纹样/幅宽变化后刷新序号：自动选号的重算；手动选号若被新范围占用则顺延并提示。
    private func refreshSequenceAfterScopeChange() {
        guard let seqLevel = sequenceLevel, scopeReady else { return }
        let cc = codeFor(kind: "color"), pc = codeFor(kind: "pattern"), wc = codeFor(kind: "width")
        let occ = occupiedForCurrentScope()
        if let n = sequenceNumber {
            if sequenceAutoPicked {
                sequenceNumber = nextFree(occ)
            } else if occ.contains(n) {
                let bumped = nextFree(occ)
                sequenceNumber = bumped
                adjustNote = "已按 \(cc)\(pc)-*-\(wc) 调整为 \(formattedSequence(bumped))"
            } else {
                adjustNote = nil
            }
        } else {
            sequenceNumber = nextFree(occ)
            sequenceAutoPicked = true
            adjustNote = nil
        }
        values[seqLevel.id] = sequenceNumber.map { formattedSequence($0) } ?? ""
    }

    private func pickManualSequence(_ n: Int) {
        guard let seqLevel = sequenceLevel else { return }
        sequenceNumber = n
        sequenceAutoPicked = false
        adjustNote = nil
        values[seqLevel.id] = formattedSequence(n)
        errorMessage = nil
    }

    private var previewResult: (code: String, segments: [String]) {
        var vals = values
        if let seqLevel = sequenceLevel, let n = sequenceNumber {
            vals[seqLevel.id] = formattedSequence(n)
        }
        return store.generateCode(values: vals)
    }

    private var missingLevels: [String] {
        var vals = values
        if let seqLevel = sequenceLevel, let n = sequenceNumber {
            vals[seqLevel.id] = formattedSequence(n)
        }
        return levels.filter { (vals[$0.id] ?? "").isEmpty }.map { $0.name }
    }

    private func confirm() {
        errorMessage = nil
        let missing = missingLevels
        if !missing.isEmpty {
            errorMessage = "还有未选的层级：\(missing.joined(separator: "、"))"
            return
        }
        let (preview, segs) = previewResult
        if let conflict = store.codeConflict(code: preview, excluding: fabric.id) {
            errorMessage = "编号 \(preview) 已被「\(conflict.fabric.displayName)」使用（主编号/子编号冲突），请换个序号"
            return
        }
        let trimmedCurrent = currentCode.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCurrent.isEmpty && trimmedCurrent != preview {
            showingOverwriteAlert = true
            return
        }
        onConfirm(preview, segs, selectedColorName)
        dismiss()
    }

    var body: some View {
        Form {
            ForEach(Array(levels.enumerated()), id: \.element.id) { idx, lv in
                levelSection(index: idx, level: lv)
            }
            Section("预览") {
                let (preview, _) = previewResult
                Text(preview.isEmpty ? "（按上面顺序选完各层级）" : preview)
                    .font(.headline)
                    .foregroundColor(preview.isEmpty ? .secondary : .primary)
                if let note = adjustNote {
                    Text(note).font(.caption).foregroundColor(.orange)
                }
                if !missingLevels.isEmpty {
                    Text("待选：\(missingLevels.joined(separator: "、"))").font(.caption).foregroundColor(.secondary)
                }
                if let errorMessage {
                    Text(errorMessage).font(.caption).foregroundColor(.red)
                }
            }
        }
        .navigationTitle("生成编号")
        .onAppear(perform: prefillFromFabric)
        .alert("覆盖已有编号？", isPresented: $showingOverwriteAlert) {
            Button("覆盖", role: .destructive) {
                let (preview, segs) = previewResult
                onConfirm(preview, segs, selectedColorName)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("当前编号为 \(currentCode)，将替换为 \(previewResult.code)。")
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("确认填入", action: confirm) }
        }
    }

    /// 打开时按布料现有编号预填各段（颜色段同时回填颜色名）；序号无预填时等范围齐了再自动取号。
    private func prefillFromFabric() {
        if didInit { return }
        didInit = true
        let segs = store.segments(of: fabric)
        for (idx, lv) in levels.enumerated() {
            let v = idx < segs.count ? segs[idx] : ""
            switch lv.kind {
            case "color":
                if !v.isEmpty, let item = lv.items.first(where: { $0.code == v || $0.name == v }) {
                    values[lv.id] = item.code
                    selectedColorName = item.name
                } else if let item = store.colorItem(forName: fabric.colorName) {
                    values[lv.id] = item.code
                    selectedColorName = item.name
                }
            case "sequence":
                if let n = Int(v), n > 0 {
                    sequenceNumber = n
                    sequenceAutoPicked = false
                    values[lv.id] = formattedSequence(n)
                }
            case "note":
                values[lv.id] = v
            default: // pattern / width
                if !v.isEmpty { values[lv.id] = v }
            }
        }
        if sequenceNumber == nil { refreshSequenceAfterScopeChange() }
    }

    @ViewBuilder
    private func levelSection(index: Int, level lv: CodeLevel) -> some View {
        Section("第 \(index + 1) 级：\(lv.name)") {
            switch lv.kind {
            case "color":
                itemGrid(level: lv, showIcon: true, isColor: true)
            case "pattern":
                itemGrid(level: lv, showIcon: false, isColor: false)
            case "sequence":
                sequencePicker(level: lv)
            case "width":
                itemGrid(level: lv, showIcon: false, isColor: false)
            case "note":
                LabeledTextField(label: "备注文字", placeholder: "选填", text: Binding(
                    get: { values[lv.id] ?? "" },
                    set: { values[lv.id] = $0; errorMessage = nil }
                ))
            default:
                LabeledTextField(label: lv.name.isEmpty ? "该段" : lv.name, placeholder: "点击输入", text: Binding(
                    get: { values[lv.id] ?? "" },
                    set: { values[lv.id] = $0; errorMessage = nil }
                ))
            }
        }
    }

    private func itemGrid(level lv: CodeLevel, showIcon: Bool, isColor: Bool) -> some View {
        let items = lv.items.filter { $0.enabled }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 72))], spacing: 10) {
            ForEach(items) { item in
                let selected = values[lv.id] == item.code
                Button(action: {
                    pickValue(lv, item.code, colorName: isColor ? item.name : nil)
                }) {
                    VStack(spacing: 4) {
                        if showIcon {
                            CodeItemIconView(icon: item.icon, size: 32)
                        }
                        Text(item.name)
                            .font(showIcon ? .caption : .subheadline)
                            .foregroundColor(selected ? Design.accent : .primary)
                        if !item.code.isEmpty {
                            Text(item.code).font(.caption2).foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(8)
                    .background(selected ? Design.accentSoft : Color.clear)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(selected ? Design.accent : Color.gray.opacity(0.25), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func sequencePicker(level lv: CodeLevel) -> some View {
        let occ = occupiedForCurrentScope()
        return VStack(alignment: .leading, spacing: 10) {
            if !scopeReady {
                Text("先选好色系、纹样、幅宽，序号会自动取该组合下的下一个空号。")
                    .font(.caption).foregroundColor(.secondary)
            } else if let n = sequenceNumber {
                HStack {
                    Text("序号：\(formattedSequence(n))").font(.headline)
                    if sequenceAutoPicked {
                        Text("自动").font(.caption).foregroundColor(.secondary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.gray.opacity(0.15)).cornerRadius(6)
                    }
                    Spacer()
                    Button("重新自动选号") {
                        let free = nextFree(occ)
                        sequenceNumber = free
                        sequenceAutoPicked = true
                        adjustNote = nil
                        values[lv.id] = formattedSequence(free)
                    }
                    .font(.subheadline).foregroundColor(Design.accent)
                }
            }
            if scopeReady {
                if occ.count >= 99 {
                    Text("01–99 已全被占用，可手动输入 ≥1 的序号。")
                        .font(.caption).foregroundColor(.secondary)
                    HStack {
                        LabeledTextField(label: "手动序号", placeholder: "≥1", text: $manualSequenceText, keyboardType: .numberPad)
                        Button("使用") {
                            if let n = Int(manualSequenceText.trimmingCharacters(in: .whitespaces)), n >= 1 {
                                pickManualSequence(n)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("点选手动指定序号（灰色为已占用）：")
                        .font(.caption).foregroundColor(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 44))], spacing: 8) {
                        ForEach(1..<100, id: \.self) { n in
                            let taken = occ.contains(n)
                            let selected = sequenceNumber == n
                            Button(action: { if !taken { pickManualSequence(n) } }) {
                                Text(formattedSequence(n))
                                    .font(.caption)
                                    .fontWeight(selected ? .bold : .regular)
                                    .foregroundColor(taken ? .secondary : (selected ? Design.accent : .primary))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selected ? Design.accentSoft : (taken ? Color.gray.opacity(0.12) : Color.clear))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(selected ? Design.accent : Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                            .disabled(taken)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct UsageFormView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    var record: UsageRecord?
    @State private var lengthText = ""
    @State private var date = Date()
    @State private var selectedWorkIDs: Set<UUID> = []
    @State private var note = ""
    @State private var errorMessage: String?
    @State private var showingWorkPicker = false
    @State private var lengthInitialized = false

    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    /// 可用上限（米）：编辑时把旧记录的长度加回剩余。
    private var maxAvailable: Double {
        if let old = record { return store.remaining(for: fabric) + old.length }
        return store.remaining(for: fabric)
    }
    private var hasMax: Bool { fabric.hasPurchaseLength }
    private var maxDisplay: Double { maxAvailable * LengthUnitHelper.factorToDisplay(unit: store.lengthUnit) }
    private var enteredMetres: Double {
        guard let d = Double(lengthText), d > 0 else { return 0 }
        return LengthUnitHelper.fromDisplay(d, unit: store.lengthUnit)
    }
    /// 滑块↔输入框双向绑定（显示单位）。
    private var lengthSliderBinding: Binding<Double> {
        Binding(
            get: { min(max(Double(lengthText) ?? 0, 0), maxDisplay) },
            set: { lengthText = displayNum($0) }
        )
    }

    init(fabric: Fabric, record: UsageRecord? = nil) {
        self.fabric = fabric
        self.record = record
        if let record {
            _lengthText = State(initialValue: String(format: "%.2f", record.length))
            _date = State(initialValue: record.date)
            _selectedWorkIDs = State(initialValue: Set(record.workIds))
            _note = State(initialValue: record.note)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 长度卡：大数字输入 + 米单位 + 滑块 + 最多/记录后可用 + 全部使用链接。
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Image(systemName: "ruler").foregroundColor(themeAccent)
                        Text("使用长度").font(.headline)
                        Spacer()
                        if hasMax {
                            Text("最多 \(LengthUnitHelper.format(maxAvailable, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        TextField("0", text: $lengthText)
                            .keyboardType(.decimalPad)
                            .font(.system(size: 44, weight: .bold))
                        Text(LengthUnitHelper.suffix(unit: store.lengthUnit))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    if hasMax {
                        Slider(value: lengthSliderBinding, in: 0...maxDisplay)
                            .tint(themeAccent)
                        HStack {
                            Text("记录后可用")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(LengthUnitHelper.format(max(0, maxAvailable - enteredMetres), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(themeAccent)
                        }
                        Button("使用全部可用布长") {
                            lengthText = displayNum(maxDisplay)
                        }
                        .font(.subheadline)
                        .foregroundColor(themeAccent)
                        .buttonStyle(.plain)
                    }
                    if record != nil {
                        Text("编辑已有记录：保存会按新长度重新扣减（先回补旧长度再扣新长度）。")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                // 记录信息卡：图标行。
                VStack(alignment: .leading, spacing: 0) {
                    Text("记录信息")
                        .font(.headline)
                        .padding(.bottom, 8)
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "calendar", accent: themeAccent)
                        Text("使用日期").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)
                    Divider()
                    Button(action: { showingWorkPicker = true }) {
                        HStack(spacing: 12) {
                            RecordIconBox(icon: "tshirt", accent: themeAccent)
                            Text("关联作品").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            Text(selectedWorkIDs.isEmpty ? "未选择" : "\(selectedWorkIDs.count) 个已选")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                    Divider()
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "text.alignleft", accent: themeAccent)
                        TextField("用途，如衣身、袖口", text: $note)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                if record != nil {
                    Button("删除这条使用记录", role: .destructive) {
                        if let record { store.removeUsageAndRestore(record) }
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red).font(.subheadline)
                }
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle(record == nil ? "添加使用记录" : "编辑使用记录")
        .onAppear {
            // 编辑时把记录的米数换算成显示单位（init 里读不到 store，只能在这里做）。
            if !lengthInitialized, let record {
                lengthText = String(format: "%.2f", record.length * LengthUnitHelper.factorToDisplay(unit: store.lengthUnit))
                lengthInitialized = true
            }
        }
        .sheet(isPresented: $showingWorkPicker) {
            NavigationStack {
                List {
                    if store.works.isEmpty {
                        Text("还没有成品").foregroundColor(.secondary)
                    } else {
                        ForEach(store.works) { work in
                            Button(action: {
                                if selectedWorkIDs.contains(work.id) { selectedWorkIDs.remove(work.id) }
                                else { selectedWorkIDs.insert(work.id) }
                            }) {
                                HStack {
                                    Text(work.name.isEmpty ? "未命名成品" : work.name)
                                        .foregroundColor(.primary)
                                    Spacer()
                                    if selectedWorkIDs.contains(work.id) {
                                        Image(systemName: "checkmark").foregroundColor(themeAccent)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .navigationTitle("关联作品")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) { Button("完成") { showingWorkPicker = false } }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let display = Double(lengthText), display > 0 else { errorMessage = "请输入大于 0 的使用长度"; return }
                    let metres = LengthUnitHelper.fromDisplay(display, unit: store.lengthUnit)
                    if let old = record {
                        // 编辑：先把旧长度加回剩余，再按新长度校验。
                        let restored = store.remaining(for: fabric) + old.length
                        if fabric.hasPurchaseLength && metres > restored {
                            errorMessage = "使用长度不能大于剩余长度（已加回旧记录）"; return
                        }
                        fabric.usedLength = max(0, fabric.usedLength - old.length + metres)
                        old.date = date; old.length = metres; old.note = note; old.workIds = Array(selectedWorkIDs)
                        store.save()
                    } else {
                        if fabric.hasPurchaseLength && metres > store.remaining(for: fabric) {
                            errorMessage = "使用长度不能大于剩余长度"; return
                        }
                        store.addUsageAndDeduct(UsageRecord(date: date, length: metres, note: note, fabricId: fabric.id, workIds: Array(selectedWorkIDs)))
                    }
                    dismiss()
                }
            }
        }
    }
}

struct SaleFormView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    var record: SaleRecord?
    @State private var lengthText = ""
    @State private var piecesText = ""
    @State private var isPieces = false
    @State private var channel = ""
    @State private var merchant = ""
    @State private var priceText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var imageNames: [String] = []
    @State private var errorMessage: String?
    @State private var lengthInitialized = false
    private let originalImageNames: [String]

    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    /// 长度出售的可用上限（米）：编辑时把旧记录的长度加回剩余；份数模式不用。
    private var maxAvailable: Double {
        if let old = record, !old.isPieces { return store.remaining(for: fabric) + old.length }
        return store.remaining(for: fabric)
    }
    private var hasMax: Bool { fabric.hasPurchaseLength && !isPieces }
    private var maxDisplay: Double { maxAvailable * LengthUnitHelper.factorToDisplay(unit: store.lengthUnit) }
    private var enteredMetres: Double {
        guard let d = Double(lengthText), d > 0 else { return 0 }
        return LengthUnitHelper.fromDisplay(d, unit: store.lengthUnit)
    }
    /// 滑块↔输入框双向绑定（显示单位）。
    private var lengthSliderBinding: Binding<Double> {
        Binding(
            get: { min(max(Double(lengthText) ?? 0, 0), maxDisplay) },
            set: { lengthText = displayNum($0) }
        )
    }

    init(fabric: Fabric, record: SaleRecord? = nil) {
        self.fabric = fabric
        self.record = record
        self.originalImageNames = record?.imageFileNames ?? []
        if let record {
            _lengthText = State(initialValue: String(format: "%.2f", record.length))
            _piecesText = State(initialValue: record.pieces > 0 ? String(record.pieces) : "")
            _isPieces = State(initialValue: record.isPieces)
            _channel = State(initialValue: record.channel)
            _merchant = State(initialValue: record.merchant)
            _priceText = State(initialValue: String(record.price))
            _date = State(initialValue: record.date)
            _note = State(initialValue: record.note)
            _imageNames = State(initialValue: record.imageFileNames)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 数量卡：长度/份切换 + 大数字输入 + 单位；长度模式带滑块/最多/记录后可用/全部售出链接。
                VStack(alignment: .leading, spacing: 12) {
                    Picker("单位", selection: $isPieces) {
                        Text("长度").tag(false)
                        Text("份").tag(true)
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Image(systemName: isPieces ? "shippingbox" : "ruler").foregroundColor(themeAccent)
                        Text(isPieces ? "售出份数" : "售出长度").font(.headline)
                        Spacer()
                        if hasMax {
                            Text("最多 \(LengthUnitHelper.format(maxAvailable, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    HStack(alignment: .lastTextBaseline, spacing: 6) {
                        TextField("0", text: isPieces ? $piecesText : $lengthText)
                            .keyboardType(isPieces ? .numberPad : .decimalPad)
                            .font(.system(size: 44, weight: .bold))
                        Text(isPieces ? "份" : LengthUnitHelper.suffix(unit: store.lengthUnit))
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    if hasMax {
                        Slider(value: lengthSliderBinding, in: 0...maxDisplay)
                            .tint(themeAccent)
                        HStack {
                            Text("记录后可用")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(LengthUnitHelper.format(max(0, maxAvailable - enteredMetres), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(themeAccent)
                        }
                        Button("售出全部可用布长") {
                            lengthText = displayNum(maxDisplay)
                        }
                        .font(.subheadline)
                        .foregroundColor(themeAccent)
                        .buttonStyle(.plain)
                    }
                    Text("售出不计入消耗。长度出售会扣剩余；份数出售只计份数，不扣剩余长度、不进售出米数。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                // 记录信息卡：图标行（售出价格 / 渠道 / 商家 / 日期 / 备注）。
                VStack(alignment: .leading, spacing: 0) {
                    Text("记录信息")
                        .font(.headline)
                        .padding(.bottom, 8)
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "yensign", accent: themeAccent)
                        Text("售出价格").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        TextField("点击输入", text: $priceText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                            .frame(width: 110)
                        Text("元").font(.subheadline).foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    Divider()
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "bag", accent: themeAccent)
                        Text("渠道").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        Picker("售出渠道", selection: $channel) {
                            Text("未填").tag("")
                            ForEach(store.channelOptions, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.menu)
                        .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                    Divider()
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "storefront", accent: themeAccent)
                        Text("商家").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        TextField("选填", text: $merchant)
                            .multilineTextAlignment(.trailing)
                            .font(.subheadline)
                            .frame(width: 140)
                    }
                    .padding(.vertical, 6)
                    Divider()
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "calendar", accent: themeAccent)
                        Text("售出日期").font(.subheadline).foregroundColor(.secondary)
                        Spacer()
                        DatePicker("", selection: $date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.vertical, 6)
                    Divider()
                    HStack(spacing: 12) {
                        RecordIconBox(icon: "note.text", accent: themeAccent)
                        TextField("备注（选填）", text: $note)
                            .font(.subheadline)
                    }
                    .padding(.vertical, 6)
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                // 图片卡。
                VStack(alignment: .leading, spacing: 8) {
                    Text("图片").font(.headline)
                    FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
                }
                .padding(16)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                if record != nil {
                    Button("删除这条出售记录", role: .destructive) {
                        if let record {
                            for name in record.imageFileNames { FabricImageStore.delete(named: name) }
                            store.deleteSaleRecord(record)
                        }
                        dismiss()
                    }
                    .buttonStyle(.plain)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundColor(.red).font(.subheadline)
                }
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle(record == nil ? "添加出售记录" : "编辑出售记录")
        .onAppear {
            // 编辑时把记录的米数换算成显示单位（init 里读不到 store，只能在这里做）。
            if !lengthInitialized, let record, !record.isPieces {
                lengthText = String(format: "%.2f", record.length * LengthUnitHelper.factorToDisplay(unit: store.lengthUnit))
                lengthInitialized = true
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    for name in imageNames where !originalImageNames.contains(name) { FabricImageStore.delete(named: name) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let price = Double(priceText) ?? 0
                    if isPieces {
                        guard let pieces = Int(piecesText), pieces > 0 else { errorMessage = "份数出售请输入大于 0 的件数"; return }
                        if let old = record {
                            old.isPieces = true; old.pieces = pieces; old.length = 0
                            old.channel = channel; old.merchant = merchant; old.price = price; old.date = date; old.note = note
                            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
                            old.imageFileNames = imageNames
                            store.save()
                        } else {
                            store.addSaleRecord(SaleRecord(fabricId: fabric.id, length: 0, channel: channel, merchant: merchant, price: price, date: date, note: note, imageFileNames: imageNames, isPieces: true, pieces: pieces))
                        }
                    } else {
                        guard let display = Double(lengthText), display > 0 else { errorMessage = "请输入大于 0 的售出长度"; return }
                        let metres = LengthUnitHelper.fromDisplay(display, unit: store.lengthUnit)
                        if let old = record {
                            // 编辑：旧长度出售已从剩余扣掉，先加回再校验。
                            let restored = fabric.hasPurchaseLength ? store.remaining(for: fabric) + (old.isPieces ? 0 : old.length) : Double.greatestFiniteMagnitude
                            if fabric.hasPurchaseLength && metres > restored {
                                errorMessage = "售出长度不能大于剩余长度（已加回旧记录）"; return
                            }
                            old.isPieces = false; old.pieces = 0; old.length = metres
                            old.channel = channel; old.merchant = merchant; old.price = price; old.date = date; old.note = note
                            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
                            old.imageFileNames = imageNames
                            store.save()
                        } else {
                            if fabric.hasPurchaseLength && metres > store.remaining(for: fabric) {
                                errorMessage = "售出长度不能大于剩余长度"; return
                            }
                            store.addSaleRecord(SaleRecord(fabricId: fabric.id, length: metres, channel: channel, merchant: merchant, price: price, date: date, note: note, imageFileNames: imageNames, isPieces: false, pieces: 0))
                        }
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 拍照找相似（纯本地粗比对，不声称精确识别）

struct SimilarSearchView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var referenceColor: String?
    @State private var referenceRGB: (Double, Double, Double)?
    @State private var didPick = false

    private func averageColor(of image: UIImage) -> (Double, Double, Double)? {
        guard let cg = image.cgImage else { return nil }
        let size = 10
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
        guard let data = context.data else { return nil }
        let ptr = data.bindMemory(to: UInt8.self, capacity: size * size * 4)
        var r = 0.0, g = 0.0, b = 0.0
        for i in 0..<(size * size) {
            r += Double(ptr[i * 4]); g += Double(ptr[i * 4 + 1]); b += Double(ptr[i * 4 + 2])
        }
        let n = Double(size * size)
        return (r / n / 255, g / n / 255, b / n / 255)
    }

    private func rank(_ fabric: Fabric) -> Double {
        guard let ref = referenceRGB else { return 0 }
        guard !fabric.colorName.isEmpty else { return 10 }
        let c = FabricColors.rgb(for: fabric.colorName)
        let dist = sqrt(pow(c.0 - ref.0, 2) + pow(c.1 - ref.1, 2) + pow(c.2 - ref.2, 2))
        return max(0, 100 - dist * 100)
    }

    private var ranked: [(fabric: Fabric, score: Double)] {
        store.fabrics.map { ($0, rank($0)) }.sorted { $0.score > $1.score }
    }

    var body: some View {
        List {
            Section {
                Text("按相似度排序，光线不同可能不准，仅供参考")
                    .font(.caption).foregroundColor(.secondary)
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedItems, matching: .images, photoLibrary: .shared()) {
                        Label("从相册选图", systemImage: "photo.on.rectangle")
                    }
                    .buttonStyle(.bordered).tint(Design.accent)
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button(action: { showingCamera = true }) { Label("拍照", systemImage: "camera") }
                            .buttonStyle(.bordered).tint(Design.accent)
                    }
                }
                if let refColor = referenceColor {
                    Text("参考主色（按照片平均色粗匹配）：\(refColor)").font(.subheadline)
                }
            }
            if didPick {
                Section("相似布料") {
                    if ranked.isEmpty { Text("还没有布料").foregroundColor(.secondary) }
                    else {
                        ForEach(ranked, id: \.fabric.id) { item in
                            NavigationLink(destination: FabricDetailView(fabric: item.fabric)) {
                                HStack {
                                    FabricCoverView(fabric: item.fabric, size: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.fabric.displayName).font(.subheadline)
                                        Text("颜色：\(item.fabric.colorName.isEmpty ? "未填" : item.fabric.colorName) · 材质：\(item.fabric.materialName.isEmpty ? "未填" : item.fabric.materialName)")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Text("\(Int(item.score))%").font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            } else {
                Section { Text("先拍一张或选一张照片，App 会按照片平均色粗匹配主色最接近的布料。没有填颜色的布料排在后面。").font(.caption).foregroundColor(.secondary) }
            }
        }
        .navigationTitle("拍照找相似")
        .onChange(of: selectedItems) { items in
            guard let item = items.first else { return }
            selectedItems = []
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data),
                   let avg = averageColor(of: image) {
                    referenceRGB = avg
                    var best = ""; var bestDist = Double.greatestFiniteMagnitude
                    for option in FabricColors.all {
                        let c = FabricColors.rgb(for: option.name)
                        let d = sqrt(pow(c.0 - avg.0, 2) + pow(c.1 - avg.1, 2) + pow(c.2 - avg.2, 2))
                        if d < bestDist { bestDist = d; best = option.name }
                    }
                    referenceColor = best
                    didPick = true
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(
                onImage: { image in
                    showingCamera = false
                    if let avg = averageColor(of: image) {
                        referenceRGB = avg
                        var best = ""; var bestDist = Double.greatestFiniteMagnitude
                        for option in FabricColors.all {
                            let c = FabricColors.rgb(for: option.name)
                            let d = sqrt(pow(c.0 - avg.0, 2) + pow(c.1 - avg.1, 2) + pow(c.2 - avg.2, 2))
                            if d < bestDist { bestDist = d; best = option.name }
                        }
                        referenceColor = best
                        didPick = true
                    }
                },
                onCancel: { showingCamera = false }
            )
        }
    }
}
