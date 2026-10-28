import SwiftUI
import PhotosUI
import UIKit

// MARK: - V3 布料卡片 / 详情 / 编辑 / 使用 / 出售 / 拍照找相似
// 卡片按原型：照片 150px 高，左上爱心，右上状态，编号小字在标题上方，
// 底部五列：材质 / 宽幅 / 米数 / 单价 / 剩余数，单价蓝色；
// 最下剩余进度条（深蓝填充）+ 百分比 + 右侧蓝色方形 + 按钮填使用记录。
// 剩余留空时不显示进度条；已出售且剩余为 0 时 + 按钮置灰禁用。

@MainActor
enum FabricStatusLabel {
    static func text(store: Store, fabric: Fabric) -> String { store.status(for: fabric) }
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
                HStack(alignment: .top, spacing: 0) {
                    cardColumn(label: "材质", value: fabric.materialName.isEmpty ? "—" : fabric.materialName)
                    cardColumn(label: "宽幅", value: fabric.width > 0 ? "\(String(format: "%.0f", fabric.widthCm))cm" : "—")
                    cardColumn(label: "米数", value: fabric.hasPurchaseLength ? "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))" : "—")
                    cardColumn(label: "单价", value: fabric.unitPrice.map { "¥\(String(format: "%.2f", $0))" } ?? "—", blue: true)
                    cardColumn(label: "剩余数", value: fabric.hasPurchaseLength ? "\(LengthUnitHelper.format(remaining, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))" : "—")
                }
                if fabric.hasPurchaseLength && fabric.length > 0 {
                    HStack(spacing: 8) {
                        ProgressBarView(fraction: remaining / fabric.length, height: 8, accent: themeAccent)
                        Text("\(Int(remaining / fabric.length * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        // 点 + 弹出菜单：使用 / 出售（iOS 16 Menu，卡片里最干净的双入口）。
                        Menu {
                            Button("使用", action: onAddUsage)
                            Button("出售", action: onAddSale)
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(isSoldOut ? Color.gray : themeAccent)
                                .cornerRadius(8)
                        }
                        .disabled(isSoldOut)
                    }
                } else if !fabric.hasPurchaseLength {
                    // 买入长度留空时仍可记使用/出售（长度留空不显示进度条，但入口保留）。
                    HStack {
                        Spacer()
                        Menu {
                            Button("使用", action: onAddUsage)
                            Button("出售", action: onAddSale)
                        } label: {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(isSoldOut ? Color.gray : themeAccent)
                                .cornerRadius(8)
                        }
                        .disabled(isSoldOut)
                    }
                }
            }
            .padding(12)
        }
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    private func cardColumn(label: String, value: String, blue: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundColor(.secondary)
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundColor(blue ? themeAccent : .primary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
    @State private var showingShare = false

    private var usageRecords: [UsageRecord] { store.usageRecords(for: fabric.id) }
    private var saleRecords: [SaleRecord] { store.saleRecords(for: fabric.id) }
    private var linkedWorks: [Work] { store.works(for: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    private var sold: Double { store.soldLength(for: fabric.id) }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    var body: some View {
        List {
            // (1) 图片展示（含视频行）
            Section("图片展示") {
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
            // (2) 编号 / 名称 / 消耗 / 售出 / 可用 / 布长 / 幅宽 / 总价 / 单价 / 星星
            Section {
                HStack {
                    if !fabric.code.isEmpty { Text(fabric.code).font(.caption).foregroundColor(.secondary) }
                    Spacer()
                    Button(action: {
                        fabric.isFavorite.toggle(); fabric.updatedAt = Date(); store.save()
                    }) {
                        Image(systemName: fabric.isFavorite ? "star.fill" : "star")
                            .foregroundColor(fabric.isFavorite ? .yellow : .secondary)
                            .font(.title3)
                    }.buttonStyle(.plain)
                }
                LabeledContent("名称", value: fabric.displayName)
                LabeledContent("已消耗米数", value: "\(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                LabeledContent("已售出米数", value: "\(LengthUnitHelper.format(sold, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                if fabric.hasPurchaseLength {
                    LabeledContent("可用米数", value: "\(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                    LabeledContent("布长", value: "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                } else {
                    LabeledContent("可用米数", value: "未填")
                    LabeledContent("布长", value: "未填")
                }
                if fabric.width > 0 { LabeledContent("幅宽", value: "\(String(format: "%.0f", fabric.widthCm)) 厘米") }
                if fabric.hasTotalPrice { LabeledContent("总价", value: "¥\(String(format: "%.2f", fabric.purchasePrice))") }
                if let unit = fabric.unitPrice { LabeledContent("单价", value: "¥\(String(format: "%.2f", unit)) / 米") }
                if !fabric.subCodes.isEmpty { LabeledContent("子编号", value: fabric.subCodes.joined(separator: "、")) }
                if let w = fabric.weightGsm { LabeledContent("克重", value: "\(String(format: "%.0f", w)) g/m²") }
                if let s = fabric.shrinkagePct { LabeledContent("缩水率", value: "\(String(format: "%.1f", s))%") }
                if !fabric.washing.isEmpty { LabeledContent("洗涤", value: fabric.washing.joined(separator: "、")) }
                LabeledContent("购买日期", value: fabric.purchaseDate.map { CSVValues.dateString($0) } ?? "未填")
                LabeledContent("状态", value: store.status(for: fabric))
                Button(action: { showingUsageList = true }) {
                    HStack {
                        Text("使用记录 \(usageRecords.count) 条，共 \(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))，点击查看")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundColor(.secondary)
                    }
                }.foregroundColor(.primary)
                if fabric.hasPurchaseLength && fabric.length > 0 {
                    HStack {
                        Text("剩余 \(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) / 买入 \(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))").font(.subheadline)
                        Spacer()
                        Text("\(Int(remaining / fabric.length * 100))%").font(.subheadline).foregroundColor(.secondary)
                    }
                    ProgressBarView(fraction: remaining / fabric.length, height: 10, accent: themeAccent)
                }
            }
            // (3) 布料信息
            Section("布料信息") {
                LabeledContent("材质", value: fabric.materialName.isEmpty ? "未填" : fabric.materialName)
                if !fabric.composition.isEmpty { LabeledContent("成分", value: fabric.composition) }
                if !fabric.colorName.isEmpty { LabeledContent("颜色", value: fabric.colorName) }
                LabeledContent("渠道", value: fabric.channelName.isEmpty ? "未填" : fabric.channelName)
                if !fabric.merchantName.isEmpty { LabeledContent("商家", value: fabric.merchantName) }
                let tagNames = store.tags(for: fabric).map { $0.name }
                if !tagNames.isEmpty { LabeledContent("标签", value: tagNames.joined(separator: "、")) }
                if !fabric.usageNotes.isEmpty { LabeledContent("用途备注", value: fabric.usageNotes) }
            }
            // (4) 消耗记录、出售记录（点行进编辑表单）
            Section("消耗记录") {
                if usageRecords.isEmpty { Text("暂无使用记录").foregroundColor(.secondary) }
                else {
                    ForEach(usageRecords) { record in
                        Button(action: { editingUsage = record }) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(CSVValues.dateString(record.date))
                                    Spacer()
                                    Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                }
                                if !record.note.isEmpty { Text(record.note).font(.caption).foregroundColor(.secondary) }
                            }
                        }.foregroundColor(.primary)
                        .swipeActions {
                            Button("删除", role: .destructive) { store.removeUsageAndRestore(record) }
                        }
                    }
                }
                Button("填写使用记录") { showingUsage = true }
            }
            Section("出售记录") {
                if saleRecords.isEmpty { Text("暂无出售记录").foregroundColor(.secondary) }
                else {
                    ForEach(saleRecords) { record in
                        Button(action: { editingSale = record }) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(CSVValues.dateString(record.date))
                                    Spacer()
                                    if record.isPieces {
                                        Text("\(record.pieces) 份 · ¥\(String(format: "%.2f", record.price))").font(.subheadline)
                                    } else {
                                        Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) · ¥\(String(format: "%.2f", record.price))").font(.subheadline)
                                    }
                                }
                                if !record.channel.isEmpty { Text(record.channel).font(.caption).foregroundColor(.secondary) }
                                if !record.note.isEmpty { Text(record.note).font(.caption).foregroundColor(.secondary) }
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
                        }.foregroundColor(.primary)
                        .swipeActions {
                            Button("删除", role: .destructive) { store.deleteSaleRecord(record) }
                        }
                    }
                }
                Button("标记出售") { showingSale = true }
            }
            Section("关联成品") {
                if linkedWorks.isEmpty { Text("暂无关联成品").foregroundColor(.secondary) }
                else {
                    ForEach(linkedWorks) { work in
                        Text(work.name.isEmpty ? "未命名成品" : work.name)
                    }
                }
            }
            // (5) 脑洞、备注
            Section("脑洞、备注") {
                if fabric.brainstorm.isEmpty && fabric.note.isEmpty {
                    Text("暂无脑洞与备注，在编辑里填写。").foregroundColor(.secondary)
                } else {
                    if !fabric.brainstorm.isEmpty {
                        Text("脑洞").font(.caption).foregroundColor(.secondary)
                        Text(fabric.brainstorm)
                    }
                    if !fabric.note.isEmpty {
                        Text("备注").font(.caption).foregroundColor(.secondary)
                        Text(fabric.note)
                    }
                }
            }
            Section {
                Button("拍照找相似") { showingSimilar = true }
            }
        }
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
        .alert("删除确认", isPresented: $showingDelete) {
            Button("删除", role: .destructive) { store.deleteFabric(fabric); dismiss() }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后无法恢复，同时会删除它的使用与出售记录。") }
    }

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
            if !fabric.brainstorm.isEmpty { Text("脑洞：\(fabric.brainstorm)") }
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
    @State private var brainstorm: String
    @State private var subCodes: [String]
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
    private let originalImageNames: [String]
    private let originalVideoNames: [String]
    private let washingOptions = ["水洗", "干洗", "可熨烫", "不可熨烫", "低温水洗", "阴干"]

    init(fabric: Fabric?) {
        self.fabric = fabric
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
        _brainstorm = State(initialValue: fabric?.brainstorm ?? "")
        _subCodes = State(initialValue: fabric?.subCodes ?? [])
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
            existing.merchantName = merchantName; existing.brainstorm = brainstorm
            existing.subCodes = subCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
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
                merchantName: merchantName, brainstorm: brainstorm,
                subCodes: subCodes.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty },
                videoFileNames: videoNames,
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

    var body: some View {
        Form {
            // (1) 图片板块：照片 + 视频（相册选视频，详情里可播放）
            Section("图片板块") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
                FabricVideoEditor(videoNames: $videoNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            // (2) 基础信息卡片
            Section("基础信息卡片（全部可留空，编号唯一）") {
                TextField("布料编号（选填，重复会禁止保存）", text: $code)
                Button("生成编号") { codeGenTargetSubIndex = nil; showingCodeGenerator = true }
                Text("编号体系：设置 > 编号体系里定颜色体系与纹样；生成时选颜色与纹样，序号按该组合递增。").font(.caption).foregroundColor(.secondary)
                TextField("名称（非必输）", text: $name)
                TextField("幅宽（厘米）", text: $widthCmText).keyboardType(.decimalPad)
                TextField("长度（\(store.lengthUnit)，留空=未填）", text: $lengthText).keyboardType(.decimalPad)
                HStack {
                    Text("子编号").font(.subheadline)
                    Spacer()
                    Button("新增子编号") { subCodes.append("") }
                }
                if subCodes.isEmpty {
                    Text("暂无子编号。子编号也可关联布料，同样唯一。").font(.caption).foregroundColor(.secondary)
                } else {
                    ForEach(subCodes.indices, id: \.self) { idx in
                        HStack {
                            TextField("子编号", text: $subCodes[idx])
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
                TextField("商家（渠道下二级自定义文本，可留空）", text: $merchantName)
                TextField("总价（元，留空=不计入总价值）", text: $priceText).keyboardType(.decimalPad)
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
                TextField("自定义材质（填了就用这个）", text: $customMaterial)
                TextField("成分（如 棉80%/涤纶20%）", text: $composition)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 10) {
                    ForEach(FabricColors.all) { option in
                        Button(action: { colorName = option.name }) {
                            VStack(spacing: 4) {
                                Circle().fill(option.color).frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                Text(option.name).font(.caption).foregroundColor(colorName == option.name ? Design.accent : .primary)
                            }
                            .padding(6)
                            .background(colorName == option.name ? Design.accentSoft : Color.clear)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
                if !colorName.isEmpty {
                    Button("清除颜色") { colorName = "" }
                }
                TextField("克重（g/m²，选填）", text: $weightText).keyboardType(.decimalPad)
                TextField("缩水率（%，选填）", text: $shrinkageText).keyboardType(.decimalPad)
                ForEach(washingOptions, id: \.self) { option in
                    Button(action: {
                        if washing.contains(option) { washing.remove(option) } else { washing.insert(option) }
                    }) {
                        HStack { Text(option); Spacer(); if washing.contains(option) { Image(systemName: "checkmark") } }
                    }
                    .foregroundColor(.primary)
                }
                TextField("用途备注", text: $usageNotes, axis: .vertical)
                TextField("脑洞（想做什么的想法）", text: $brainstorm, axis: .vertical)
                TextField("备注", text: $note, axis: .vertical)
                Toggle(isOn: $isFavorite) {
                    Label("收藏", systemImage: isFavorite ? "star.fill" : "star")
                }
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .sheet(isPresented: $showingCodeGenerator) {
            NavigationStack {
                CodeGeneratorSheet(
                    initialColor: colorName,
                    onConfirm: { generated in
                        if let idx = codeGenTargetSubIndex, subCodes.indices.contains(idx) {
                            subCodes[idx] = generated
                        } else {
                            code = generated
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

// 多级编号生成表：第一级颜色（与布料颜色同一色板，布料已填颜色时预选）、
// 第二级纹样（设置 > 编号体系可自定义）、第三级该组合下 3 位序号、后续级自定义备注。
// 生成时不覆盖已有编号，只有用户点“确认填入”才填入；序号已存在时自动递增到唯一。
struct CodeGeneratorSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var initialColor: String
    var onConfirm: (String) -> Void
    @State private var color: String
    @State private var pattern: String
    @State private var suffix: String = ""
    init(initialColor: String, onConfirm: @escaping (String) -> Void) {
        self.initialColor = initialColor
        self.onConfirm = onConfirm
        _color = State(initialValue: initialColor.isEmpty ? "红" : initialColor)
        _pattern = State(initialValue: "")
    }
    private var preview: String {
        store.nextCode(color: color, pattern: pattern.isEmpty ? (store.patternOptions.first ?? "素色") : pattern, customSuffix: suffix)
    }
    var body: some View {
        Form {
            Section("第一级：颜色体系（选一个颜色作编号符号）") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 10) {
                    ForEach(FabricColors.all) { option in
                        Button(action: { color = option.name }) {
                            VStack(spacing: 4) {
                                Circle().fill(option.color).frame(width: 32, height: 32)
                                    .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                                Text(option.name).font(.caption).foregroundColor(color == option.name ? Design.accent : .primary)
                            }
                            .padding(6)
                            .background(color == option.name ? Design.accentSoft : Color.clear)
                            .cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Section("第二级：纹样") {
                Picker("纹样", selection: $pattern) {
                    Text("未选").tag("")
                    ForEach(store.patternOptions, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("后续级：自定义备注（选填）") {
                TextField("自定义后缀（如 备注文字）", text: $suffix)
            }
            Section("预览") {
                Text(preview).font(.headline)
                Text("格式：[前缀-]颜色-纹样-001[-备注]；前缀在设置 > 编号体系里定，空则省略。").font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("生成编号")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) { Button("确认填入") { onConfirm(preview) } }
        }
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
                TextField("使用长度（\(store.lengthUnit)）", text: $lengthText).keyboardType(.decimalPad)
                DatePicker("使用时间", selection: $date, displayedComponents: .date)
                TextField("用途备注", text: $note, axis: .vertical)
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
                    TextField("份数（件数，>0）", text: $piecesText).keyboardType(.numberPad)
                } else {
                    TextField("售出长度（\(store.lengthUnit)）", text: $lengthText).keyboardType(.decimalPad)
                }
                Picker("售出渠道", selection: $channel) {
                    Text("未填").tag("")
                    ForEach(store.channelOptions, id: \.self) { Text($0).tag($0) }
                }
                TextField("商家（渠道下二级自定义文本，可留空）", text: $merchant)
                TextField("售出价格（元）", text: $priceText).keyboardType(.decimalPad)
                DatePicker("售出日期", selection: $date, displayedComponents: .date)
                TextField("备注", text: $note, axis: .vertical)
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
