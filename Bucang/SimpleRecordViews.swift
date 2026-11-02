import SwiftUI

// MARK: - V3 成品 / 其他 / 心愿单表单
// 成品用料与消耗记录同源：成品页加用料 = 给该布新建一条消耗记录，
// 剩余只扣一次，绝不重复计量。

struct WorkEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var work: Work?
    @State private var name: String
    @State private var startDate: Date?
    @State private var hasStartDate: Bool
    @State private var finishDate: Date?
    @State private var hasFinishDate: Bool
    @State private var note: String
    @State private var imageNames: [String]
    @State private var isSold: Bool
    @State private var salePriceText: String
    @State private var shippingFeeText: String
    @State private var hasSalePrice: Bool
    @State private var saleDate: Date
    @State private var hasSaleDate: Bool
    @State private var saleChannel: String
    @State private var isUsed: Bool
    @State private var usageCount: Int
    @State private var laborCostText: String
    @State private var hasLaborCost: Bool
    @State private var selColors: Set<String>
    @State private var workSize: String
    @State private var workSizeUnit: String
    private let originalImageNames: [String]

    init(work: Work?) {
        self.work = work
        self.originalImageNames = work?.imageFileNames ?? []
        _name = State(initialValue: work?.name ?? "")
        _startDate = State(initialValue: work?.startedAt ?? Date())
        _hasStartDate = State(initialValue: work?.startedAt != nil)
        _finishDate = State(initialValue: work?.finishedAt ?? Date())
        _hasFinishDate = State(initialValue: work?.finishedAt != nil)
        _note = State(initialValue: work?.note ?? "")
        _imageNames = State(initialValue: work?.imageFileNames ?? [])
        _isSold = State(initialValue: work?.isSold ?? false)
        _salePriceText = State(initialValue: work == nil || !work!.hasSalePrice ? "" : String(work!.salePrice))
        _shippingFeeText = State(initialValue: work == nil ? "" : (work!.shippingFee == 0 ? "" : String(work!.shippingFee)))
        _hasSalePrice = State(initialValue: work?.hasSalePrice ?? false)
        _saleDate = State(initialValue: work?.saleDate ?? Date())
        _hasSaleDate = State(initialValue: work?.saleDate != nil)
        _saleChannel = State(initialValue: work?.saleChannel ?? "")
        _isUsed = State(initialValue: work?.isUsed ?? false)
        _usageCount = State(initialValue: work?.usageCount ?? 0)
        _laborCostText = State(initialValue: work == nil || !work!.hasLaborCost ? "" : String(work!.laborCost))
        _hasLaborCost = State(initialValue: work?.hasLaborCost ?? false)
        _selColors = State(initialValue: Set(work?.colorCodes ?? []))
        _workSize = State(initialValue: work?.workSize ?? "")
        _workSizeUnit = State(initialValue: work?.workSizeUnit ?? "cm")
    }

    private func save() {
        let labor = Double(laborCostText) ?? 0
        let laborFilled = hasLaborCost && !laborCostText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if let existing = work {
            existing.name = name
            existing.startedAt = hasStartDate ? startDate : nil
            existing.finishedAt = hasFinishDate ? finishDate : nil
            existing.note = note
            existing.isSold = isSold
            existing.salePrice = Double(salePriceText) ?? 0
            existing.hasSalePrice = isSold && !salePriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            existing.shippingFee = Double(shippingFeeText) ?? 0
            existing.saleDate = (isSold && hasSaleDate) ? saleDate : nil
            existing.saleChannel = saleChannel
            existing.isUsed = isUsed
            existing.usageCount = usageCount
            existing.laborCost = labor
            existing.hasLaborCost = laborFilled
            existing.workSize = workSize
            existing.workSizeUnit = workSizeUnit
            existing.colorCodes = Array(selColors)
            // 兼容旧 colorName：取第一个选中色的名称
            if let firstCode = selColors.first,
               let item = store.levelOrder().first(where: { $0.kind == "color" })?.items.first(where: { $0.code == firstCode }) {
                existing.colorName = item.name
            } else {
                existing.colorName = ""
            }
            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
            existing.imageFileNames = imageNames
            store.save()
        } else {
            let newWork = Work(
                name: name,
                startedAt: hasStartDate ? startDate : nil,
                finishedAt: hasFinishDate ? finishDate : nil,
                note: note, imageFileNames: imageNames,
                isSold: isSold, salePrice: Double(salePriceText) ?? 0,
                hasSalePrice: isSold && !salePriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                shippingFee: Double(shippingFeeText) ?? 0,
                saleDate: (isSold && hasSaleDate) ? saleDate : nil,
                saleChannel: saleChannel, isUsed: isUsed, usageCount: usageCount,
                laborCost: labor, hasLaborCost: laborFilled, colorCodes: Array(selColors),
                workSize: workSize, workSizeUnit: workSizeUnit
            )
            store.addWork(newWork)
        }
        dismiss()
    }

    var body: some View {
        Form {
            Section("成品照片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            Section("成品尺寸") {
                Picker("尺寸", selection: $workSize) {
                    Text("未选择").tag("")
                    ForEach(store.workSizeOptions, id: \.self) { option in
                        Text(option).tag(option)
                    }
                }
                Picker("单位", selection: $workSizeUnit) {
                    Text("cm").tag("cm")
                    Text("m").tag("m")
                    Text("尺").tag("尺")
                }
                .pickerStyle(.segmented)
            }
            // 成品页没有独立的详情页（列表直达编辑），只读的关联脑洞放编辑页最上方。
            if let work {
                Section("关联脑洞") {
                    let links = store.brainstorms(forWork: work.id)
                    if links.isEmpty {
                        Text("暂无关联脑洞").foregroundColor(.secondary)
                    } else {
                        ForEach(links) { brainstorm in
                            NavigationLink(destination: BrainstormDetailView(brainstorm: brainstorm)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(brainstorm.title.isEmpty ? "未命名脑洞" : brainstorm.title).lineLimit(1)
                                    Text(brainstorm.status).font(.caption).foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            Section("成品") {
                LabeledTextField(label: "成品名称", placeholder: "选填", text: $name)
                VStack(alignment: .leading, spacing: 8) {
                    Text("颜色搭配").font(.subheadline).foregroundColor(.secondary)
                    let items = (store.levelOrder().first(where: { $0.kind == "color" })?.items ?? [])
                        .filter { $0.enabled }
                    if items.isEmpty {
                        Text("暂无颜色选项").foregroundColor(.secondary).font(.caption)
                    } else {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4), spacing: 16) {
                            ForEach(items) { item in
                                let selected = selColors.contains(item.code)
                                Button(action: {
                                    if selected { selColors.remove(item.code) }
                                    else { selColors.insert(item.code) }
                                }) {
                                    VStack(spacing: 6) {
                                        ZStack {
                                            CodeItemIconView(icon: item.icon, size: 44)
                                            if selected {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .font(.title3)
                                                    .foregroundColor(.white)
                                                    .background(Circle().fill(ThemeHelper.accent(store.themeName)).frame(width: 20, height: 20))
                                                    .offset(x: 16, y: -16)
                                            }
                                        }
                                        let _code = item.code.trimmingCharacters(in: .whitespacesAndNewlines)
                                        Text(_code.isEmpty ? item.name : "\(item.name)/\(_code)")
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .background(selected ? ThemeHelper.accent(store.themeName).opacity(0.12) : Color.clear)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Toggle("填写开始创作时间", isOn: $hasStartDate)
                if hasStartDate { DatePicker("开始创作时间", selection: Binding(get: { startDate ?? Date() }, set: { startDate = $0 }), displayedComponents: .date) }
                Toggle("填写完成时间（填了即视为已完成）", isOn: $hasFinishDate)
                if hasFinishDate { DatePicker("完成时间", selection: Binding(get: { finishDate ?? Date() }, set: { finishDate = $0 }), displayedComponents: .date) }
                LabeledMultilineField(label: "备注", text: $note)
            }
            Section("出售 / 使用") {
                // 2026-11-01：只有已完成（填了完成时间）的成品才能标记出售
                if hasFinishDate {
                    Toggle("是否出售", isOn: $isSold)
                    if isSold {
                        LabeledTextField(label: "邮费/打包费", placeholder: "留空=0", text: $shippingFeeText, keyboardType: .decimalPad, unit: "元")
                        LabeledTextField(label: "出售价格", placeholder: "留空=未填", text: $salePriceText, keyboardType: .decimalPad, unit: "元")
                        HStack {
                            Text("实际入账").font(.subheadline).foregroundColor(.secondary)
                            Spacer()
                            let price = Double(salePriceText) ?? 0
                            let fee = Double(shippingFeeText) ?? 0
                            Text("¥\(String(format: "%.2f", max(0, price - fee)))")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        Toggle("填写出售时间", isOn: $hasSaleDate)
                        if hasSaleDate { DatePicker("出售时间", selection: $saleDate, displayedComponents: .date) }
                        Picker("出售渠道", selection: $saleChannel) {
                            Text("未填").tag("")
                            ForEach(store.channelOptions, id: \.self) { Text($0).tag($0) }
                        }
                    }
                } else {
                    Text("填了完成时间后才能标记出售").font(.caption).foregroundColor(.secondary)
                }
                Toggle("是否使用", isOn: $isUsed)
                Stepper("使用次数：\(usageCount)", value: $usageCount, in: 0...9999)
            }
            Section("工费") {
                Toggle("填写工费", isOn: $hasLaborCost)
                if hasLaborCost {
                    LabeledTextField(label: "工费", placeholder: "留空=未填", text: $laborCostText, keyboardType: .decimalPad, unit: "元")
                }
            }
            if let work {
                Section("用料清单") {
                    if work.materials.isEmpty { Text("还没有用料，回到成品页点“加用料”").foregroundColor(.secondary) }
                    else {
                        ForEach(work.materials) { material in
                            HStack {
                                Text(store.fabric(for: material.fabricId)?.displayName ?? "已删除的布料")
                                Spacer()
                                Text("\(LengthUnitHelper.format(material.amount, unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))").font(.caption).foregroundColor(.secondary)
                                // Form 里 swipe 删除不可靠，另给明确的删除按钮；
                                // 删用料不自动回补剩余（已生成的消耗记录仍在），
                                // 如需回补请在布料详情里删对应消耗记录。
                                Button("删除", role: .destructive) {
                                    work.materials.removeAll { $0.id == material.id }
                                    store.save()
                                }
                                .font(.caption)
                            }
                        }
                    }
                    let cost = store.workCost(for: work)
                    Text("用料成本合计：¥\(String(format: "%.2f", cost.total))\(cost.hasMissingPrice ? "（部分布料无单价，未计入）" : "")")
                        .font(.subheadline)
                    if work.hasLaborCost {
                        Text("工费：¥\(String(format: "%.2f", work.laborCost))")
                            .font(.subheadline)
                    }
                    HStack {
                        Text("总成本").font(.subheadline)
                        Spacer()
                        Text("¥\(String(format: "%.2f", store.workTotalCost(for: work)))")
                            .font(.subheadline).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                    }
                }
                Section {
                    Button("删除这个成品", role: .destructive) {
                        store.deleteWork(work); dismiss()
                    }
                }
            }
        }
        .navigationTitle(work == nil ? "新建成品" : "编辑成品")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    for name in imageNames where !originalImageNames.contains(name) { FabricImageStore.delete(named: name) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
    }
}

struct WorkMaterialAddView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var work: Work
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    @State private var selectedFabricId: UUID?
    @State private var amountText = ""
    @State private var errorMessage: String?
    @State private var searchText = ""
    @State private var isGrid = false

    private var filteredFabrics: [Fabric] {
        var list = store.fabrics
        let kw = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !kw.isEmpty {
            list = list.filter {
                $0.displayName.localizedCaseInsensitiveContains(kw)
                || $0.code.localizedCaseInsensitiveContains(kw)
            }
        }
        return list
    }

    var body: some View {
        Form {
            Section {
                Text("成品：\(work.name.isEmpty ? "未命名成品" : work.name)")
                Text("加用料会同时给这块布生成一条消耗记录，剩余只扣一次。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("选布料") {
                // 置顶搜索栏 + 单双列切换
                HStack(spacing: 8) {
                    HStack {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("搜索", text: $searchText)
                    }
                    .padding(8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    Button(action: { isGrid.toggle() }) {
                        Image(systemName: isGrid ? "list.bullet" : "square.grid.2x2")
                            .font(.title3)
                            .foregroundColor(themeAccent)
                    }
                }
                if filteredFabrics.isEmpty {
                    Text("还没有布料").foregroundColor(.secondary)
                } else if isGrid {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        ForEach(filteredFabrics) { fabric in gridCard(fabric) }
                    }
                } else {
                    ForEach(filteredFabrics) { fabric in listRow(fabric) }
                }
            }
            Section {
                LabeledTextField(label: "用量", placeholder: "点击输入", text: $amountText, keyboardType: .decimalPad, unit: store.lengthUnit)
            }
            if let errorMessage { Text(errorMessage).foregroundColor(.red) }
        }
        .navigationTitle("成品加用料")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    guard let fabricId = selectedFabricId, let fabric = store.fabric(for: fabricId) else { errorMessage = "请先选一块布料"; return }
                    guard let display = Double(amountText), display > 0 else { errorMessage = "请输入大于 0 的用量"; return }
                    let metres = LengthUnitHelper.fromDisplay(display, unit: store.lengthUnit)
                    if fabric.hasPurchaseLength && metres > store.remaining(for: fabric) {
                        errorMessage = "用量不能大于剩余长度"; return
                    }
                    work.materials.append(WorkMaterial(fabricId: fabricId, amount: metres))
                    store.addUsageAndDeduct(UsageRecord(date: Date(), length: metres, note: "用于成品：\(work.name.isEmpty ? "未命名成品" : work.name)", fabricId: fabricId, workIds: [work.id]))
                    store.save()
                    dismiss()
                }
            }
        }
    }

    private func thumb(_ fabric: Fabric) -> some View {
        Group {
            if let name = fabric.imageFileNames.first, let uiImage = FabricImageStore.loadImage(named: name) {
                Image(uiImage: uiImage).resizable().scaledToFill()
            } else {
                Rectangle().fill(ThemeHelper.accentSoft(store.themeName))
                    .overlay(Image(systemName: "photo").foregroundColor(themeAccent))
            }
        }
    }

    private func listRow(_ fabric: Fabric) -> some View {
        let selected = selectedFabricId == fabric.id
        return Button(action: { selectedFabricId = fabric.id }) {
            HStack(spacing: 12) {
                thumb(fabric).frame(width: 56, height: 56).cornerRadius(8).clipped()
                VStack(alignment: .leading, spacing: 2) {
                    Text(fabric.displayName).foregroundColor(.primary).lineLimit(1)
                    Text("剩余 \(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                        .font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark.circle.fill").foregroundColor(themeAccent) }
            }
        }
        .foregroundColor(.primary)
    }

    private func gridCard(_ fabric: Fabric) -> some View {
        let selected = selectedFabricId == fabric.id
        return Button(action: { selectedFabricId = fabric.id }) {
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    thumb(fabric).frame(height: 100).clipped()
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(themeAccent)
                            .background(Circle().fill(Color.white))
                            .padding(6)
                    }
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(fabric.displayName).font(.subheadline).foregroundColor(.primary).lineLimit(1)
                    Text("剩余 \(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit))")
                        .font(.caption).foregroundColor(.secondary).lineLimit(1)
                }
                .padding(8)
            }
            .background(Color(.systemBackground))
            .cornerRadius(12)
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(selected ? themeAccent : Color.gray.opacity(0.2), lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
    }
}

struct OtherEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: OtherItem?
    @State private var category: String
    @State private var subCategory: String
    @State private var customSubCategory: String
    @State private var name: String
    @State private var quantityText: String
    @State private var priceText: String
    @State private var channel: String
    @State private var note: String
    @State private var imageNames: [String]
    private let originalImageNames: [String]

    init(item: OtherItem?) {
        self.item = item
        self.originalImageNames = item?.imageFileNames ?? []
        // 已存的 category 可能是子分类名，反查父级
        let savedCat = item?.category ?? ""
        // 注意：init 时 store 还未注入，用默认值；body 首次渲染时通过 onAppear 校正
        _category = State(initialValue: savedCat)
        _subCategory = State(initialValue: "")
        _customSubCategory = State(initialValue: "")
        _name = State(initialValue: item?.name ?? "")
        _quantityText = State(initialValue: item?.quantityText ?? "")
        _priceText = State(initialValue: item == nil || !item!.hasPrice ? "" : String(item!.price))
        _channel = State(initialValue: item?.channel ?? "")
        _note = State(initialValue: item?.note ?? "")
        _imageNames = State(initialValue: item?.imageFileNames ?? [])
    }

    // 当前一级分类的子分类列表
    private var childCategories: [OtherCategory] {
        guard let parent = store.otherCategoryTree.first(where: { $0.name == category && $0.parentId == nil }) else { return [] }
        return store.otherCategoryTree.filter { $0.parentId == parent.id }.sorted { $0.order < $1.order }
    }

    private func save() {
        var categoryValue = category.trimmingCharacters(in: .whitespacesAndNewlines)
        // 处理子分类
        let customSub = customSubCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if subCategory == "__custom__" && !customSub.isEmpty {
            // 自定义子分类：自动加入设置
            if let parent = store.otherCategoryTree.first(where: { $0.name == category && $0.parentId == nil }) {
                if !store.otherCategoryTree.contains(where: { $0.name == customSub && $0.parentId == parent.id }) {
                    let maxOrder = store.otherCategoryTree.filter { $0.parentId == parent.id }.map { $0.order }.max() ?? -1
                    store.otherCategoryTree.append(OtherCategory(name: customSub, parentId: parent.id, order: maxOrder + 1))
                    store.saveCategoryTree()
                }
            }
            categoryValue = customSub
        } else if !subCategory.isEmpty && subCategory != "__custom__" {
            categoryValue = subCategory
        }
        if !categoryValue.isEmpty && !store.otherCategories.contains(categoryValue) {
            store.otherCategories.append(categoryValue)
        }
        if let existing = item {
            existing.category = categoryValue; existing.name = name; existing.quantityText = quantityText
            existing.price = Double(priceText) ?? 0; existing.hasPrice = !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            existing.channel = channel; existing.note = note
            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
            existing.imageFileNames = imageNames
            store.save()
        } else {
            let newItem = OtherItem(
                category: categoryValue, name: name, imageFileNames: imageNames,
                quantityText: quantityText, price: Double(priceText) ?? 0,
                hasPrice: !priceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                channel: channel, note: note
            )
            store.addOtherItem(newItem)
        }
        dismiss()
    }

    var body: some View {
        Form {
            Section("照片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            Section("其他条目") {
                Picker("所属分类", selection: $category) {
                    Text("未分类").tag("")
                    ForEach(store.otherCategoryTree.filter { $0.parentId == nil }.sorted { $0.order < $1.order }) { Text($0.name).tag($0.name) }
                }
                .onChange(of: category) { _ in subCategory = ""; customSubCategory = "" }
                Picker("子分类", selection: $subCategory) {
                    Text("无").tag("")
                    ForEach(childCategories) { Text($0.name).tag($0.name) }
                    Text("自定义…").tag("__custom__")
                }
                if subCategory == "__custom__" {
                    LabeledTextField(label: "自定义子分类", placeholder: "输入新子分类名称", text: $customSubCategory)
                }
                LabeledTextField(label: "名称", placeholder: "选填", text: $name)
                LabeledTextField(label: "数量或长度", placeholder: "选填", text: $quantityText)
                LabeledTextField(label: "价格", placeholder: "点击输入", text: $priceText, keyboardType: .decimalPad, unit: "元")
                LabeledTextField(label: "渠道", placeholder: "选填", text: $channel)
                LabeledMultilineField(label: "备注", text: $note)
            }
            if let item {
                Button("删除这个条目", role: .destructive) {
                    store.deleteOtherItem(item); dismiss()
                }
            }
        }
        .navigationTitle(item == nil ? "新增其他条目" : "编辑其他条目")
        .onAppear {
            // 若已存分类是子分类，拆成父级+子级
            if let sub = store.otherCategoryTree.first(where: { $0.name == category && $0.parentId != nil }),
               let parent = store.otherCategoryTree.first(where: { $0.id == sub.parentId }) {
                category = parent.name
                subCategory = sub.name
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    for name in imageNames where !originalImageNames.contains(name) { FabricImageStore.delete(named: name) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) { Button("保存", action: save) }
        }
    }
}

struct WishlistEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: WishlistItem?
    var presetName: String
    @State private var name: String
    @State private var note: String
    @State private var imageNames: [String]
    @State private var estimatedPriceText: String
    @State private var hasEstimatedPrice: Bool
    private let originalImageNames: [String]

    init(item: WishlistItem?, presetName: String) {
        self.item = item
        self.presetName = presetName
        self.originalImageNames = item?.imageFileNames ?? []
        _name = State(initialValue: item?.name ?? presetName)
        _note = State(initialValue: item?.note ?? "")
        _imageNames = State(initialValue: item?.imageFileNames ?? [])
        _estimatedPriceText = State(initialValue: item == nil || !item!.hasEstimatedPrice ? "" : String(item!.estimatedPrice))
        _hasEstimatedPrice = State(initialValue: item?.hasEstimatedPrice ?? false)
    }

    private func saveValues() -> (price: Double, filled: Bool) {
        let price = Double(estimatedPriceText) ?? 0
        let filled = hasEstimatedPrice && !estimatedPriceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (price, filled)
    }

    var body: some View {
        Form {
            Section("心愿单") {
                LabeledTextField(label: "名称", placeholder: "选填", text: $name)
                LabeledMultilineField(label: "想法备注", text: $note)
            }
            Section("预估价") {
                Toggle("填写预估价", isOn: $hasEstimatedPrice)
                if hasEstimatedPrice {
                    LabeledTextField(label: "预估价", placeholder: "留空=未填", text: $estimatedPriceText, keyboardType: .decimalPad, unit: "元")
                }
            }
            Section("照片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            if let item {
                Button("删除这个心愿", role: .destructive) {
                    store.deleteWishlistItem(item); dismiss()
                }
            }
        }
        .navigationTitle(item == nil ? "新增心愿" : "编辑心愿")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") {
                    for name in imageNames where !originalImageNames.contains(name) { FabricImageStore.delete(named: name) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let (estPrice, estFilled) = saveValues()
                    if let existing = item {
                        existing.name = name; existing.note = note
                        existing.estimatedPrice = estPrice; existing.hasEstimatedPrice = estFilled
                        for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
                        existing.imageFileNames = imageNames
                        store.save()
                    } else {
                        store.addWishlistItem(WishlistItem(name: name, imageFileNames: imageNames, note: note,
                                                           estimatedPrice: estPrice, hasEstimatedPrice: estFilled))
                    }
                    dismiss()
                }
            }
        }
    }
}
