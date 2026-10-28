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
    var compact: Bool = false

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
                    Image(systemName: fabric.isFavorite ? "heart.fill" : "heart")
                        .foregroundColor(fabric.isFavorite ? .red : .white)
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
                        ProgressBarView(fraction: remaining / fabric.length, height: 8)
                        Text("\(Int(remaining / fabric.length * 100))%")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Button(action: onAddUsage) {
                            Image(systemName: "plus")
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(isSoldOut ? Color.gray : Design.accent)
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
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
            Text(value).font(.subheadline).fontWeight(.semibold).foregroundColor(blue ? Design.accent : .primary).lineLimit(1).minimumScaleFactor(0.8)
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

    private var usageRecords: [UsageRecord] { store.usageRecords(for: fabric.id) }
    private var saleRecords: [SaleRecord] { store.saleRecords(for: fabric.id) }
    private var linkedWorks: [Work] { store.works(for: fabric.id) }
    private var remaining: Double { store.remaining(for: fabric) }
    private var sold: Double { store.soldLength(for: fabric.id) }

    var body: some View {
        List {
            Section("基本信息") {
                if !fabric.code.isEmpty { LabeledContent("编号", value: fabric.code) }
                LabeledContent("名称", value: fabric.displayName)
                LabeledContent("材质", value: fabric.materialName.isEmpty ? "未填" : fabric.materialName)
                if !fabric.composition.isEmpty { LabeledContent("成分", value: fabric.composition) }
                if !fabric.colorName.isEmpty { LabeledContent("颜色", value: fabric.colorName) }
                LabeledContent("渠道", value: fabric.channelName.isEmpty ? "未填" : fabric.channelName)
                if fabric.width > 0 { LabeledContent("幅宽", value: "\(String(format: "%.0f", fabric.widthCm)) 厘米") }
                if fabric.hasPurchaseLength { LabeledContent("买入长度", value: "\(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))") }
                LabeledContent("消耗", value: "\(LengthUnitHelper.format(fabric.usedLength, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                LabeledContent("售出", value: "\(LengthUnitHelper.format(sold, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                if fabric.hasPurchaseLength { LabeledContent("剩余", value: "\(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))") }
                if fabric.hasTotalPrice { LabeledContent("总价", value: "¥\(String(format: "%.2f", fabric.purchasePrice))") }
                if let unit = fabric.unitPrice { LabeledContent("单价", value: "¥\(String(format: "%.2f", unit)) / 米") }
                if let w = fabric.weightGsm { LabeledContent("克重", value: "\(String(format: "%.0f", w)) g/m²") }
                if let s = fabric.shrinkagePct { LabeledContent("缩水率", value: "\(String(format: "%.1f", s))%") }
                if !fabric.washing.isEmpty { LabeledContent("洗涤", value: fabric.washing.joined(separator: "、")) }
                LabeledContent("购买日期", value: CSVValues.dateString(fabric.purchaseDate))
                LabeledContent("状态", value: store.status(for: fabric))
                let tagNames = store.tags(for: fabric).map { $0.name }
                if !tagNames.isEmpty { LabeledContent("标签", value: tagNames.joined(separator: "、")) }
                if !fabric.usageNotes.isEmpty { LabeledContent("用途备注", value: fabric.usageNotes) }
                if !fabric.note.isEmpty { LabeledContent("备注", value: fabric.note) }
            }
            Section("图片") {
                FabricImageEditor(
                    imageNames: Binding(get: { fabric.imageFileNames }, set: { fabric.imageFileNames = $0 }),
                    deleteFilesImmediately: true,
                    onNamesChanged: { store.save() }
                )
            }
            if fabric.hasPurchaseLength && fabric.length > 0 {
                Section("剩余进度") {
                    HStack {
                        Text("剩余 \(LengthUnitHelper.format(remaining, unit: store.lengthUnit)) / 买入 \(LengthUnitHelper.format(fabric.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))").font(.subheadline)
                        Spacer()
                        Text("\(Int(remaining / fabric.length * 100))%").font(.subheadline).foregroundColor(.secondary)
                    }
                    ProgressBarView(fraction: remaining / fabric.length, height: 10)
                }
            }
            Section("使用记录") {
                if usageRecords.isEmpty { Text("暂无使用记录").foregroundColor(.secondary) }
                else {
                    ForEach(usageRecords) { record in
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(CSVValues.dateString(record.date))
                                Spacer()
                                Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                            }
                            if !record.note.isEmpty { Text(record.note).font(.caption).foregroundColor(.secondary) }
                        }
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
                        HStack {
                            Text(CSVValues.dateString(record.date))
                            Spacer()
                            Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit)) · ¥\(String(format: "%.2f", record.price))").font(.subheadline)
                        }
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
            Section {
                Button("拍照找相似") { showingSimilar = true }
                Button(fabric.isFavorite ? "取消收藏" : "收藏") {
                    fabric.isFavorite.toggle(); fabric.updatedAt = Date(); store.save()
                }
                Button("编辑", action: { showingEdit = true })
                Button("删除这块布料", role: .destructive) { showingDelete = true }
            }
        }
        .navigationTitle(fabric.displayName)
        .sheet(isPresented: $showingEdit) { NavigationStack { FabricEditView(fabric: fabric) } }
        .sheet(isPresented: $showingUsage) { NavigationStack { UsageFormView(fabric: fabric) } }
        .sheet(isPresented: $showingSale) { NavigationStack { SaleFormView(fabric: fabric) } }
        .sheet(isPresented: $showingSimilar) { NavigationStack { SimilarSearchView() } }
        .alert("删除确认", isPresented: $showingDelete) {
            Button("删除", role: .destructive) { store.deleteFabric(fabric); dismiss() }
            Button("取消", role: .cancel) {}
        } message: { Text("删除后无法恢复，同时会删除它的使用与出售记录。") }
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
    @State private var usageNotes: String
    @State private var note: String
    @State private var purchaseDate: Date
    @State private var isFavorite: Bool
    @State private var selectedTagIDs: Set<UUID>
    @State private var imageNames: [String]
    @State private var errorMessage: String?
    @State private var lengthInitialized = false
    private let originalImageNames: [String]
    private let washingOptions = ["水洗", "干洗", "可熨烫", "不可熨烫", "低温水洗", "阴干"]

    init(fabric: Fabric?) {
        self.fabric = fabric
        self.originalImageNames = fabric?.imageFileNames ?? []
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
        _usageNotes = State(initialValue: fabric?.usageNotes ?? "")
        _note = State(initialValue: fabric?.note ?? "")
        _purchaseDate = State(initialValue: fabric?.purchaseDate ?? Date())
        _isFavorite = State(initialValue: fabric?.isFavorite ?? false)
        _selectedTagIDs = State(initialValue: Set(fabric?.tagIds ?? []))
        _imageNames = State(initialValue: fabric?.imageFileNames ?? [])
    }

    private func generateCode() {
        let prefix = store.codePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = prefix.isEmpty ? "B" : prefix
        var n = store.fabrics.count + 1
        while true {
            let candidate = "\(base)-\(String(format: "%03d", n))"
            if !store.fabrics.contains(where: { $0.code == candidate }) {
                code = candidate
                return
            }
            n += 1
        }
    }

    private func save() {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCode.isEmpty {
            let conflict = store.fabrics.first { $0.code == trimmedCode && $0.id != fabric?.id }
            if let conflict {
                errorMessage = "编号重复，禁止保存：已有一块布料用了这个编号（\(conflict.displayName)）"
                return
            }
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
            existing.usageNotes = usageNotes; existing.note = note
            existing.purchaseDate = purchaseDate; existing.isFavorite = isFavorite
            existing.tagIds = tagIDsArray; existing.updatedAt = Date()
            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
            existing.imageFileNames = imageNames
            store.save()
        } else {
            let newFabric = Fabric(
                name: name, length: lengthMetres, width: widthMetres,
                purchasePrice: price, pricePerMeter: 0, purchaseDate: purchaseDate,
                note: note, tagIds: tagIDsArray, imageFileNames: imageNames,
                code: trimmedCode, materialName: materialValue, composition: composition,
                colorName: colorName, weightGsm: Double(weightText), shrinkagePct: Double(shrinkageText),
                washing: Array(washing), usageNotes: usageNotes, channelName: channel,
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
        dismiss()
    }

    var body: some View {
        Form {
            Section("基本（全部可留空）") {
                TextField("编号（唯一，重复会禁止保存）", text: $code)
                Button("按编号体系生成") { generateCode() }
                TextField("名称", text: $name)
                Picker("材质", selection: $material) {
                    Text("未填").tag("")
                    ForEach(store.materialOptions, id: \.self) { Text($0).tag($0) }
                }
                TextField("自定义材质（填了就用这个）", text: $customMaterial)
                TextField("成分（如 棉80%/涤纶20%）", text: $composition)
                TextField("渠道 / 商家", text: $channel)
                DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                Toggle("收藏", isOn: $isFavorite)
            }
            Section("颜色（主色单选）") {
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
            }
            Section("尺寸与价格（长度按设置单位输入：当前单位 \(store.lengthUnit)）") {
                TextField("买入长度（\(store.lengthUnit)，留空=未填）", text: $lengthText).keyboardType(.decimalPad)
                TextField("幅宽（厘米）", text: $widthCmText).keyboardType(.decimalPad)
                TextField("总价（元，留空=不计入总价值）", text: $priceText).keyboardType(.decimalPad)
                TextField("克重（g/m²，选填）", text: $weightText).keyboardType(.decimalPad)
                TextField("缩水率（%，选填）", text: $shrinkageText).keyboardType(.decimalPad)
            }
            Section("洗涤方式") {
                ForEach(washingOptions, id: \.self) { option in
                    Button(action: {
                        if washing.contains(option) { washing.remove(option) } else { washing.insert(option) }
                    }) {
                        HStack { Text(option); Spacer(); if washing.contains(option) { Image(systemName: "checkmark") } }
                    }
                    .foregroundColor(.primary)
                }
            }
            Section("标签") {
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
            Section("图片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            Section("备注") {
                TextField("用途备注", text: $usageNotes, axis: .vertical)
                TextField("备注", text: $note, axis: .vertical)
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
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

struct UsageFormView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric
    @State private var lengthText = ""
    @State private var date = Date()
    @State private var selectedWorkIDs: Set<UUID> = []
    @State private var note = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("布料：\(fabric.displayName)")
                Text("编号：\(fabric.code.isEmpty ? "未填" : fabric.code)")
                Text("剩余：\(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
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
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .navigationTitle("填写使用记录")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let display = Double(lengthText), display > 0 else { errorMessage = "请输入大于 0 的使用长度"; return }
                    let metres = LengthUnitHelper.fromDisplay(display, unit: store.lengthUnit)
                    if fabric.hasPurchaseLength && metres > store.remaining(for: fabric) {
                        errorMessage = "使用长度不能大于剩余长度"; return
                    }
                    store.addUsageAndDeduct(UsageRecord(date: date, length: metres, note: note, fabricId: fabric.id, workIds: Array(selectedWorkIDs)))
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
    @State private var lengthText = ""
    @State private var channel = ""
    @State private var priceText = ""
    @State private var date = Date()
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("布料：\(fabric.displayName)")
                Text("剩余：\(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                Text("售出不计入消耗，剩余会同步扣减。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("出售记录") {
                TextField("售出长度（\(store.lengthUnit)）", text: $lengthText).keyboardType(.decimalPad)
                TextField("售出渠道", text: $channel)
                TextField("售出价格（元）", text: $priceText).keyboardType(.decimalPad)
                DatePicker("售出日期", selection: $date, displayedComponents: .date)
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .navigationTitle("标记出售")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let display = Double(lengthText), display > 0 else { errorMessage = "请输入大于 0 的售出长度"; return }
                    let metres = LengthUnitHelper.fromDisplay(display, unit: store.lengthUnit)
                    if fabric.hasPurchaseLength && metres > store.remaining(for: fabric) {
                        errorMessage = "售出长度不能大于剩余长度"; return
                    }
                    store.addSaleRecord(SaleRecord(fabricId: fabric.id, length: metres, channel: channel, price: Double(priceText) ?? 0, date: date))
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
