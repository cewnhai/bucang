import SwiftUI

// MARK: - V3 成品 / 其他 / 心愿单表单
// 成品用料与使用记录同源：成品页加用料 = 给该布新建一条使用记录，
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
    }

    private func save() {
        if let existing = work {
            existing.name = name
            existing.startedAt = hasStartDate ? startDate : nil
            existing.finishedAt = hasFinishDate ? finishDate : nil
            existing.note = note
            for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
            existing.imageFileNames = imageNames
            store.save()
        } else {
            let newWork = Work(
                name: name,
                startedAt: hasStartDate ? startDate : nil,
                finishedAt: hasFinishDate ? finishDate : nil,
                note: note, imageFileNames: imageNames
            )
            store.addWork(newWork)
        }
        dismiss()
    }

    var body: some View {
        Form {
            Section("成品（全部可留空）") {
                TextField("成品名称", text: $name)
                Toggle("填写开始创作时间", isOn: $hasStartDate)
                if hasStartDate { DatePicker("开始创作时间", selection: Binding(get: { startDate ?? Date() }, set: { startDate = $0 }), displayedComponents: .date) }
                Toggle("填写完成时间（填了即视为已完成）", isOn: $hasFinishDate)
                if hasFinishDate { DatePicker("完成时间", selection: Binding(get: { finishDate ?? Date() }, set: { finishDate = $0 }), displayedComponents: .date) }
                TextField("备注", text: $note, axis: .vertical)
            }
            Section("成品照片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
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
                                // 删用料不自动回补剩余（已生成的使用记录仍在），
                                // 如需回补请在布料详情里删对应使用记录。
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
    @State private var selectedFabricId: UUID?
    @State private var amountText = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                Text("成品：\(work.name.isEmpty ? "未命名成品" : work.name)")
                Text("加用料会同时给这块布生成一条使用记录，剩余只扣一次。")
                    .font(.caption).foregroundColor(.secondary)
            }
            Section("选布料") {
                if store.fabrics.isEmpty { Text("还没有布料").foregroundColor(.secondary) }
                else {
                    ForEach(store.fabrics) { fabric in
                        Button(action: { selectedFabricId = fabric.id }) {
                            HStack {
                                Text(fabric.displayName)
                                Spacer()
                                Text("剩余 \(LengthUnitHelper.format(store.remaining(for: fabric), unit: store.lengthUnit)) \(LengthUnitHelper.suffix(unit: store.lengthUnit))").font(.caption).foregroundColor(.secondary)
                                if selectedFabricId == fabric.id { Image(systemName: "checkmark") }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            Section {
                TextField("用量（\(store.lengthUnit)）", text: $amountText).keyboardType(.decimalPad)
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
}

struct OtherEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: OtherItem?
    @State private var category: String
    @State private var customCategory: String
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
        _category = State(initialValue: item?.category ?? "")
        _customCategory = State(initialValue: "")
        _name = State(initialValue: item?.name ?? "")
        _quantityText = State(initialValue: item?.quantityText ?? "")
        _priceText = State(initialValue: item == nil || !item!.hasPrice ? "" : String(item!.price))
        _channel = State(initialValue: item?.channel ?? "")
        _note = State(initialValue: item?.note ?? "")
        _imageNames = State(initialValue: item?.imageFileNames ?? [])
    }

    private func save() {
        let categoryValue = customCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.trimmingCharacters(in: .whitespacesAndNewlines) : customCategory.trimmingCharacters(in: .whitespacesAndNewlines)
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
            Section("其他条目（全部可留空，最少填名称加照片就能存）") {
                Picker("所属分类", selection: $category) {
                    Text("未分类").tag("")
                    ForEach(store.otherCategories, id: \.self) { Text($0).tag($0) }
                }
                TextField("自定义分类（填了就用这个）", text: $customCategory)
                TextField("名称", text: $name)
                TextField("数量或长度", text: $quantityText)
                TextField("价格（元）", text: $priceText).keyboardType(.decimalPad)
                TextField("渠道", text: $channel)
                TextField("备注", text: $note, axis: .vertical)
            }
            Section("照片") {
                FabricImageEditor(imageNames: $imageNames, deleteFilesImmediately: false, onNamesChanged: {})
            }
            if let item {
                Button("删除这个条目", role: .destructive) {
                    store.deleteOtherItem(item); dismiss()
                }
            }
        }
        .navigationTitle(item == nil ? "新增其他条目" : "编辑其他条目")
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
    private let originalImageNames: [String]

    init(item: WishlistItem?, presetName: String) {
        self.item = item
        self.presetName = presetName
        self.originalImageNames = item?.imageFileNames ?? []
        _name = State(initialValue: item?.name ?? presetName)
        _note = State(initialValue: item?.note ?? "")
        _imageNames = State(initialValue: item?.imageFileNames ?? [])
    }

    var body: some View {
        Form {
            Section("心愿单（只当备忘）") {
                TextField("名称", text: $name)
                TextField("想法备注", text: $note, axis: .vertical)
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
                    if let existing = item {
                        existing.name = name; existing.note = note
                        for oldName in originalImageNames where !imageNames.contains(oldName) { FabricImageStore.delete(named: oldName) }
                        existing.imageFileNames = imageNames
                        store.save()
                    } else {
                        store.addWishlistItem(WishlistItem(name: name, imageFileNames: imageNames, note: note))
                    }
                    dismiss()
                }
            }
        }
    }
}
