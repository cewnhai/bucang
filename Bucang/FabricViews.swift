import SwiftUI
import PhotosUI
import UIKit
import AVKit

// MARK: - V3 布料卡片 / 详情 / 编辑 / 使用 / 出售 / 拍照找相似
// 卡片按原型：照片 150px 高，左上爱心，右上状态，编号小字在标题上方，
// 底部五列：材质 / 宽幅 / 米数 / 单价 / 剩余数，单价蓝色；
// 最下剩余进度条（深蓝填充）+ 百分比 + 右侧蓝色方形 + 按钮填使用记录。
// 剩余留空时不显示进度条；已出售且剩余为 0 时 + 按钮置灰禁用。

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

struct FabricCardView: View {
    @EnvironmentObject private var store: Store
    var fabric: Fabric
    var onAddUsage: () -> Void
    var onAddSale: () -> Void = {}
    var compact: Bool = false
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
                    Rectangle()
                        .fill(Design.accentSoft)
                        .frame(height: compact ? 110 : 150)
                        .overlay(Image(systemName: "scissors").foregroundColor(Design.accent).font(.title2))
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
                if !fabric.code.isEmpty {
                    Text(fabric.code)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text(fabric.displayName)
                    .font(.headline)
                    .lineLimit(1)
                // 两列模式卡片窄，五列信息带改横向滚动，左右滑看全数值，不再截断；
                // 整宽模式保持原来的固定五列。
                if compact {
                    ScrollView(.horizontal, showsIndicators: false) {
                        infoStrip
                    }
                } else {
                    infoStrip
                }
                if fabric.hasPurchaseLength && fabric.length > 0 {
                    if compact {
                        // 两列卡片窄：进度行与按钮行上下排，避免进度条被挤没。
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ProgressBarView(fraction: remaining / fabric.length, height: 8, accent: themeAccent)
                                Text("\(Int(remaining / fabric.length * 100))%")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            HStack { Spacer(); usageSaleButtons }
                        }
                    } else {
                        HStack(spacing: 8) {
                            ProgressBarView(fraction: remaining / fabric.length, height: 8, accent: themeAccent)
                            Text("\(Int(remaining / fabric.length * 100))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            usageSaleButtons
                        }
                    }
                } else if !fabric.hasPurchaseLength {
                    // 买入长度留空时仍可记使用/出售（长度留空不显示进度条，但入口保留）。
                    HStack {
                        Spacer()
                        usageSaleButtons
                    }
                }
            }
            .padding(12)
        }
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    // 卡片右下直接双入口：使用 / 出售胶囊按钮（代替原来的 Menu，避免 Menu 嵌在
    // NavigationLink 里的点按误触风险）。已售出时置灰不可点。
    private var usageSaleButtons: some View {
        HStack(spacing: 8) {
            Button("使用", action: onAddUsage)
                .buttonStyle(.plain)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSoldOut ? Color.gray : themeAccent)
                .cornerRadius(12)
            Button("出售", action: onAddSale)
                .buttonStyle(.plain)
                .font(.caption).fontWeight(.semibold)
                .foregroundColor(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(isSoldOut ? Color.gray : themeAccent)
                .cornerRadius(12)
        }
        .disabled(isSoldOut)
    }

    private var infoStrip: some View {
        HStack(alignment: .top, spacing: 0) {
            cardColumn(label: "材质", value: fabric.materialName.isEmpty ? "—" : fabric.materialName)
            cardColumn(label: "宽幅", value: fabric.width > 0 ? "\(String(format: "%.0f", fabric.widthCm))cm" : "—")
            cardColumn(label: "米数", value: fabric.hasPurchaseLength ? "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))" : "—")
            cardColumn(label: "单价", value: fabric.unitPrice.map { "¥\(String(format: "%.2f", $0))" } ?? "—", accent: Design.priceAccent)
            cardColumn(label: "剩余数", value: fabric.hasPurchaseLength ? "\(LengthUnitHelper.format(remaining, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))" : "—")
        }
    }

    private func cardColumn(label: String, value: String, accent: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundColor(accent ?? .primary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// V8 布料详情（原版布局）：顶部照片头（4:3 全宽 Tab + 收藏星标 + 放大按钮 +
// 多图页码）/ 视频条，摘要卡（编号 / 名称 / 收藏 / 状态胶囊 / 已用 / 可用大数字 /
// 进度条 / 布长幅宽总价三列）轻微压住照片头；下方 7 个可折叠板块（图片 / 基础信息 /
// 布料信息 / 其他信息 / 消耗记录 / 出售记录 / 脑洞与备注），收起状态存在
// fabric.collapsedSections。"基础信息"板块的标题行在照片头上方，内容即摘要卡。
// 注意：Fabric.brainstorm 旧文本字段已从全部 UI 移除（模型字段保留），
// 脑洞板块只展示关联的 Brainstorm 实体（经 BrainstormDetailView 进入）。
struct FabricDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingUsage = false
    @State private var showingSale = false
    @State private var showingSimilar = false
    @State private var editingUsage: UsageRecord?
    @State private var editingSale: SaleRecord?
    @State private var showingUsageList = false
    @State private var showingLongImage = false
    @State private var longImage: UIImage?
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

                // 基础信息：标题行（+ 圆形收起钮）在照片头上方；内容是照片头 + 视频条 + 摘要卡。
                HStack {
                    Text("基础信息")
                        .font(.headline)
                    Spacer()
                    collapseToggleButton(key: "basic")
                }
                .padding(.bottom, 8)
                photoHeader
                if !fabric.videoFileNames.isEmpty {
                    videoStrip
                        .padding(.top, 10)
                }
                if fabric.collapsedSections.contains("basic") {
                    CardView {
                        collapsedSummary(key: "basic")
                    }
                    .padding(.top, 10)
                } else {
                    // 摘要卡轻微压住照片头（有视频条时改为常规间距，避免盖住视频缩略图）。
                    summaryCard
                        .padding(.top, fabric.videoFileNames.isEmpty ? -16 : 10)
                }

                // 其余可折叠板块
                VStack(alignment: .leading, spacing: 20) {
                    collapsibleSection(key: "images", title: "图片") {
                        VStack(alignment: .leading, spacing: 18) {
                            FabricImageEditor(
                                imageNames: Binding(get: { fabric.imageFileNames }, set: { fabric.imageFileNames = $0 }),
                                deleteFilesImmediately: true,
                                onNamesChanged: { store.save() }
                            )
                            FabricVideoEditor(
                                videoNames: Binding(get: { fabric.videoFileNames }, set: { fabric.videoFileNames = $0 }),
                                deleteFilesImmediately: true,
                                onNamesChanged: { store.save() }
                            )
                        }
                    }
                    collapsibleSection(key: "fabric", title: "布料信息") { fabricInfoCard }
                    collapsibleSection(key: "other", title: "其他信息") { otherInfoCard }
                    collapsibleSection(key: "usage", title: "消耗记录") { usageCard }
                    collapsibleSection(key: "sale", title: "出售记录") { saleCard }
                    collapsibleSection(key: "brainstorm", title: "脑洞与备注") { brainstormCard }
                }
                .padding(.top, 20)

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
        .sheet(isPresented: $showingUsage) { NavigationStack { UsageFormView(fabric: fabric) } }
        .sheet(isPresented: $showingSale) { NavigationStack { SaleFormView(fabric: fabric) } }
        .sheet(isPresented: $showingSimilar) { NavigationStack { SimilarSearchView() } }
        .sheet(item: $editingUsage) { record in NavigationStack { UsageFormView(fabric: fabric, record: record) } }
        .sheet(item: $editingSale) { record in NavigationStack { SaleFormView(fabric: fabric, record: record) } }
        .sheet(isPresented: $showingUsageList) {
            NavigationStack {
                List {
                    if usageRecords.isEmpty { Text("暂无使用记录").foregroundColor(.secondary) }
                    else {
                        ForEach(usageRecords) { record in
                            Button(action: { showingUsageList = false; editingUsage = record }) {
                                HStack {
                                    Text(CSVValues.dateString(record.date))
                                    Spacer()
                                    Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                }
                            }.foregroundColor(.primary)
                        }
                    }
                }
                .navigationTitle("使用记录")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingUsageList = false } } }
            }
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

    /// 摘要卡底部三列：图标 + 灰 label + 加粗 value。
    private func summaryStat(icon: String, label: String, value: String, valueColor: Color = .primary) -> some View {
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
        }
        .frame(maxWidth: .infinity)
    }

    private struct DetailPreviewItem: Identifiable {
        var name: String
        var id: String { name }
    }

    // MARK: - 一、基础信息（原版头：照片头 + 视频条 + 摘要卡）

    /// 照片头：全宽 4:3，多图可横滑（TabView，不显示系统页码，右下角自绘 "N / M"），
    /// 左上星标收藏，右上放大进全屏预览（点图片本身也进）；无图时剪刀占位。
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
            // 左上：收藏星标
            Button(action: toggleFavorite) {
                Image(systemName: fabric.isFavorite ? "star.fill" : "star")
                    .foregroundColor(fabric.isFavorite ? .yellow : .white)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.35)))
            }
            .buttonStyle(.plain)
            .padding(12)
            .accessibilityLabel("收藏")
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

    /// 摘要卡：编号 caption + 名称 / 右侧爱心 + 状态胶囊；已使用 X 米 · P% /
    /// 右侧可用大数字；细进度条；布长 / 幅宽 / 总价三列。
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
                    Button(action: toggleFavorite) {
                        Image(systemName: fabric.isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundColor(fabric.isFavorite ? .red : .gray)
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
                            valueColor: Design.priceAccent)
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

    private var fabricInfoCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                iconInfoRow(icon: "barcode", label: "编号",
                            value: fabric.code.isEmpty ? "未填" : fabric.code,
                            showChevron: true)
                // 子编号：编号行下的缩进块（原有新增 / 删除逻辑不变）
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
                            Text(sub).font(.subheadline)
                            Spacer()
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

    /// 颜色行：图标盒里放实际色块（白块描边防隐身），"其他"(M) 放小色轮，
    /// 查不到的旧名放 tag 图标；名称文字在右侧。
    private var colorRow: some View {
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
        .padding(.vertical, 6)
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

    // MARK: - 四、消耗记录（点行进编辑表单；行尾垃圾桶删除；头部"记一笔 >"新建）

    private var usageCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    iconBox("doc.text")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("使用记录").font(.headline)
                        Text("共 \(usageRecords.count) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingUsage = true }) {
                        HStack(spacing: 2) {
                            Text("记一笔")
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(themeAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                if usageRecords.isEmpty {
                    Text("暂无使用记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(usageRecords) { record in
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

    // MARK: - 五、出售记录（点行进编辑表单；行尾垃圾桶删除；头部"登记出售 >"新建）

    private var saleCard: some View {
        CardView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    iconBox("doc.text")
                    VStack(alignment: .leading, spacing: 2) {
                        Text("出售记录").font(.headline)
                        Text("共 \(saleRecords.count) 条记录")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button(action: { showingSale = true }) {
                        HStack(spacing: 2) {
                            Text("登记出售")
                            Image(systemName: "chevron.right").font(.caption)
                        }
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(themeAccent)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 4)
                if saleRecords.isEmpty {
                    Text("暂无出售记录")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(saleRecords) { record in
                        HStack(alignment: .top, spacing: 8) {
                            Button(action: { editingSale = record }) {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack {
                                        Text(CSVValues.dateString(record.date)).font(.subheadline)
                                        Spacer()
                                        if record.isPieces {
                                            Text("\(record.pieces) 份 · ¥\(String(format: "%.2f", record.price))")
                                                .font(.subheadline).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                                        } else {
                                            Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) · ¥\(String(format: "%.2f", record.price))")
                                                .font(.subheadline).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                                        }
                                    }
                                    if !record.channel.isEmpty {
                                        Text(record.channel).font(.caption).foregroundColor(.secondary)
                                    }
                                    if !record.note.isEmpty {
                                        Text(record.note).font(.caption).foregroundColor(.secondary)
                                    }
                                    if !record.imageFileNames.isEmpty {
                                        ScrollView(.horizontal, showsIndicators: false) {
                                            HStack(spacing: 8) {
                                                ForEach(record.imageFileNames, id: \.self) { name in
                                                    if let uiImage = FabricImageStore.loadImage(named: name) {
                                                        Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 64, height: 64).clipped().cornerRadius(8)
                                                    }
                                                }
                                            }
                                        }
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
        Form {
            Section {
                Text("布料：\(fabric.displayName)")
                Text("编号：\(fabric.code.isEmpty ? "未填" : fabric.code)")
                Text("剩余：\(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                if record != nil { Text("编辑已有记录：保存会按新长度重新扣减（先回补旧长度再扣新长度）。").font(.caption).foregroundColor(.secondary) }
            }
            Section("填写使用记录") {
                LabeledTextField(label: "使用长度", placeholder: "点击输入", text: $lengthText, keyboardType: .decimalPad, unit: store.lengthUnit)
                DatePicker("使用时间", selection: $date, displayedComponents: .date)
                LabeledMultilineField(label: "用途备注", text: $note)
            }
            Section("关联成品（可多选）") {
                if store.works.isEmpty { Text("还没有成品").foregroundColor(.secondary) }
                else {
                    ForEach(store.works) { work in
                        Button(action: {
                            if selectedWorkIDs.contains(work.id) { selectedWorkIDs.remove(work.id) } else { selectedWorkIDs.insert(work.id) }
                        }) {
                            HStack { Text(work.name.isEmpty ? "未命名成品" : work.name); Spacer(); if selectedWorkIDs.contains(work.id) { Image(systemName: "checkmark") } }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            if record != nil {
                Section {
                    Button("删除这条使用记录", role: .destructive) {
                        if let record { store.removeUsageAndRestore(record) }
                        dismiss()
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .navigationTitle(record == nil ? "填写使用记录" : "编辑使用记录")
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
    private let originalImageNames: [String]

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
        Form {
            Section {
                Text("布料：\(fabric.displayName)")
                Text("剩余：\(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                Text("售出不计入消耗。长度出售会扣剩余；份数出售只计份数，不扣剩余长度、不进售出米数。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("出售记录") {
                Picker("单位", selection: $isPieces) {
                    Text("长度").tag(false)
                    Text("份").tag(true)
                }.pickerStyle(.segmented)
                if isPieces {
                    LabeledTextField(label: "份数", placeholder: ">0", text: $piecesText, keyboardType: .numberPad, unit: "件")
                } else {
                    LabeledTextField(label: "售出长度", placeholder: "点击输入", text: $lengthText, keyboardType: .decimalPad, unit: store.lengthUnit)
                }
                Picker("售出渠道", selection: $channel) {
                    Text("未填").tag("")
                    ForEach(store.channelOptions, id: \.self) { Text($0).tag($0) }
                }
                LabeledTextField(label: "商家", placeholder: "选填", text: $merchant)
                LabeledTextField(label: "售出价格", placeholder: "点击输入", text: $priceText, keyboardType: .decimalPad, unit: "元")
                DatePicker("售出日期", selection: $date, displayedComponents: .date)
                LabeledMultilineField(label: "备注", text: $note)
            }
            Section("图片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            if record != nil {
                Section {
                    Button("删除这条出售记录", role: .destructive) {
                        if let record {
                            for name in record.imageFileNames { FabricImageStore.delete(named: name) }
                            store.deleteSaleRecord(record)
                        }
                        dismiss()
                    }
                }
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .navigationTitle(record == nil ? "标记出售" : "编辑出售记录")
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
