import SwiftUI

enum FabricSort: String, CaseIterable, Identifiable {
    case purchaseDate, price, length, created
    var id: String { rawValue }
    var label: String {
        switch self {
        case .purchaseDate: return "购买日期"
        case .price: return "价格"
        case .length: return "长度"
        case .created: return "创建时间"
        }
    }
}

struct FabricListView: View {
    @EnvironmentObject private var store: Store

    @State private var searchText = ""
    @State private var showFavoritesOnly = false
    @State private var materialFilter: UUID?
    @State private var channelFilter: UUID?
    @State private var sort: FabricSort = .purchaseDate
    @State private var showingAdd = false

    private var fabrics: [Fabric] { store.fabrics }
    private var materials: [Material] { store.materials.sorted { $0.sortOrder < $1.sortOrder } }
    private var channels: [Channel] { store.channels.sorted { $0.sortOrder < $1.sortOrder } }

    private var filtered: [Fabric] {
        var list = fabrics
        if showFavoritesOnly { list = list.filter { $0.isFavorite } }
        if let materialFilter { list = list.filter { $0.materialId == materialFilter } }
        if let channelFilter { list = list.filter { $0.channelId == channelFilter } }
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if !keyword.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(keyword)
                || $0.note.localizedCaseInsensitiveContains(keyword)
                || (store.material(for: $0.materialId)?.name.localizedCaseInsensitiveContains(keyword) ?? false)
                || (store.channel(for: $0.channelId)?.name.localizedCaseInsensitiveContains(keyword) ?? false)
            }
        }
        switch sort {
        case .purchaseDate: return list.sorted { $0.purchaseDate > $1.purchaseDate }
        case .price: return list.sorted { $0.purchasePrice > $1.purchasePrice }
        case .length: return list.sorted { $0.length > $1.length }
        case .created: return list.sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var totalLength: Double { fabrics.reduce(0) { $0 + $1.length } }
    private var totalRemaining: Double { fabrics.reduce(0) { $0 + $1.remainingLength } }
    private var totalPrice: Double { fabrics.reduce(0) { $0 + $1.purchasePrice } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(fabrics.count) 块布料")
                            Text("总长 \(totalLength, specifier: "%.2f") 米 · 剩余 \(totalRemaining, specifier: "%.2f") 米")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Text("总价 ¥\(totalPrice, specifier: "%.2f")")
                            .font(.subheadline)
                    }
                }
                Section {
                    Toggle("只看收藏", isOn: $showFavoritesOnly)
                    Picker("排序", selection: $sort) {
                        ForEach(FabricSort.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("材质", selection: $materialFilter) {
                        Text("全部").tag(UUID?.none)
                        ForEach(materials) { Text($0.name).tag(Optional($0.id)) }
                    }
                    Picker("渠道", selection: $channelFilter) {
                        Text("全部").tag(UUID?.none)
                        ForEach(channels) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                ForEach(filtered) { fabric in
                    NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(fabric.displayName)
                                    .font(.headline)
                                if fabric.isFavorite {
                                    Image(systemName: "star.fill")
                                        .foregroundColor(.yellow)
                                        .font(.caption)
                                }
                            }
                            Text("\(store.material(for: fabric.materialId)?.name ?? "未分类") · \(store.channel(for: fabric.channelId)?.name ?? "未分类")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Text("总长 \(fabric.length, specifier: "%.2f") 米 · 剩余 \(fabric.remainingLength, specifier: "%.2f") 米 · ¥\(fabric.purchasePrice, specifier: "%.2f")")
                                .font(.caption)
                        }
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { filtered[$0] }
                    for fabric in toDelete {
                        store.deleteFabric(fabric)
                    }
                }
            }
            .searchable(text: $searchText, prompt: "按名称、备注、材质、渠道搜索")
            .navigationTitle("布料")
            .toolbar {
                Button(action: { showingAdd = true }) {
                    Image(systemName: "plus")
                }
            }
            .sheet(isPresented: $showingAdd) {
                NavigationStack { FabricEditView(fabric: nil) }
            }
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "scissors")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无布料记录")
                            .font(.headline)
                        Text("点右上角加号新增，或去设置里导入原数据")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct FabricDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var fabric: Fabric

    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingUsage = false
    @State private var usageLengthText = ""
    @State private var usageNote = ""
    @State private var usageError: String?

    private var usageRecords: [UsageRecord] { store.usageRecords(for: fabric.id) }
    private var fabricTags: [Tag] { store.tags(for: fabric) }

    var body: some View {
        List {
            Section("基本信息") {
                LabeledContent("名称", value: fabric.displayName)
                LabeledContent("材质", value: store.material(for: fabric.materialId)?.name ?? "未分类")
                LabeledContent("渠道", value: store.channel(for: fabric.channelId)?.name ?? "未分类")
                LabeledContent("幅宽", value: "\(String(format: "%.2f", fabric.width)) 米")
                LabeledContent("总长", value: "\(String(format: "%.2f", fabric.length)) 米")
                LabeledContent("已用", value: "\(String(format: "%.2f", fabric.usedLength)) 米")
                LabeledContent("剩余", value: "\(String(format: "%.2f", fabric.remainingLength)) 米")
                LabeledContent("总价", value: "¥\(String(format: "%.2f", fabric.purchasePrice))")
                LabeledContent("单价", value: "¥\(String(format: "%.2f", fabric.pricePerMeter)) / 米")
                LabeledContent("购买日期", value: CSVValues.dateString(fabric.purchaseDate))
                if !fabricTags.isEmpty {
                    LabeledContent("标签", value: fabricTags.map { $0.name }.joined(separator: "、"))
                }
                if !fabric.note.isEmpty {
                    LabeledContent("备注", value: fabric.note)
                }
            }
            Section("使用记录") {
                if usageRecords.isEmpty {
                    Text("暂无使用记录")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(usageRecords) { record in
                        HStack {
                            Text(CSVValues.dateString(record.date))
                            Spacer()
                            Text("\(record.length, specifier: "%.2f") 米")
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                fabric.usedLength = max(0, fabric.usedLength - record.length)
                                fabric.updatedAt = Date()
                                store.deleteUsageRecord(record)
                                store.save()
                            }
                        }
                    }
                }
                Button("添加使用记录") { showingUsage = true }
            }
            Section {
                Button(fabric.isFavorite ? "取消收藏" : "收藏") {
                    fabric.isFavorite.toggle()
                    fabric.updatedAt = Date()
                    store.save()
                }
                Button("编辑", action: { showingEdit = true })
                Button("删除这块布料", role: .destructive) { showingDelete = true }
            }
        }
        .navigationTitle(fabric.displayName)
        .sheet(isPresented: $showingEdit) {
            NavigationStack { FabricEditView(fabric: fabric) }
        }
        .alert("删除确认", isPresented: $showingDelete) {
            Button("删除", role: .destructive) {
                store.deleteFabric(fabric)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后无法恢复，同时会删除它的使用记录。")
        }
        .sheet(isPresented: $showingUsage) {
            NavigationStack {
                Form {
                    TextField("使用长度（米）", text: $usageLengthText)
                        .keyboardType(.decimalPad)
                    TextField("备注（选填）", text: $usageNote)
                    if let usageError {
                        Text(usageError).foregroundColor(.red)
                    }
                }
                .navigationTitle("添加使用记录")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") { showingUsage = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("保存") {
                            guard let amount = Double(usageLengthText), amount > 0 else {
                                usageError = "请输入大于 0 的使用长度"
                                return
                            }
                            guard amount <= fabric.remainingLength else {
                                usageError = "使用长度不能大于剩余长度（剩余 \(String(format: "%.2f", fabric.remainingLength)) 米）"
                                return
                            }
                            let record = UsageRecord(date: Date(), length: amount, note: usageNote, fabricId: fabric.id)
                            fabric.usedLength += amount
                            fabric.updatedAt = Date()
                            store.addUsageRecord(record)
                            usageLengthText = ""
                            usageNote = ""
                            usageError = nil
                            showingUsage = false
                        }
                    }
                }
            }
        }
    }
}

struct FabricEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss

    var fabric: Fabric?

    @State private var name: String
    @State private var lengthText: String
    @State private var widthText: String
    @State private var priceText: String
    @State private var pricePerMeterText: String
    @State private var purchaseDate: Date
    @State private var note: String
    @State private var isFavorite: Bool
    @State private var materialID: UUID?
    @State private var channelID: UUID?
    @State private var selectedTagIDs: Set<UUID>
    @State private var errorMessage: String?

    init(fabric: Fabric?) {
        self.fabric = fabric
        _name = State(initialValue: fabric?.name ?? "")
        _lengthText = State(initialValue: fabric == nil ? "" : String(fabric!.length))
        _widthText = State(initialValue: fabric == nil ? "" : String(fabric!.width))
        _priceText = State(initialValue: fabric == nil ? "" : String(fabric!.purchasePrice))
        _pricePerMeterText = State(initialValue: fabric == nil ? "" : String(fabric!.pricePerMeter))
        _purchaseDate = State(initialValue: fabric?.purchaseDate ?? Date())
        _note = State(initialValue: fabric?.note ?? "")
        _isFavorite = State(initialValue: fabric?.isFavorite ?? false)
        _materialID = State(initialValue: fabric?.materialId)
        _channelID = State(initialValue: fabric?.channelId)
        _selectedTagIDs = State(initialValue: Set(fabric?.tagIds ?? []))
    }

    private var materials: [Material] { store.materials.sorted { $0.sortOrder < $1.sortOrder } }
    private var channels: [Channel] { store.channels.sorted { $0.sortOrder < $1.sortOrder } }
    private var tags: [Tag] { store.tags.sorted { $0.sortOrder < $1.sortOrder } }

    private func save() {
        let length = Double(lengthText) ?? 0
        let width = Double(widthText) ?? 0
        let price = Double(priceText) ?? 0
        var perMeter = Double(pricePerMeterText) ?? 0
        if perMeter == 0 && length > 0 {
            perMeter = price / length
        }
        if length < 0 || width < 0 || price < 0 {
            errorMessage = "长度、幅宽、价格不能为负数"
            return
        }
        let selectedTagIDsArray = tags.filter { selectedTagIDs.contains($0.id) }.map { $0.id }
        if let existing = fabric, length < existing.usedLength {
            errorMessage = "总长不能小于已用长度（已用 \(String(format: "%.2f", existing.usedLength)) 米）"
            return
        }
        if let existing = fabric {
            existing.name = name
            existing.length = length
            existing.width = width
            existing.purchasePrice = price
            existing.pricePerMeter = perMeter
            existing.purchaseDate = purchaseDate
            existing.note = note
            existing.isFavorite = isFavorite
            existing.materialId = materialID
            existing.channelId = channelID
            existing.tagIds = selectedTagIDsArray
            existing.updatedAt = Date()
            if existing.usedLength > length {
                errorMessage = "总长不能小于已用长度（已用 \(String(format: "%.2f", existing.usedLength)) 米）"
                return
            }
            store.save()
        } else {
            let newFabric = Fabric(
                name: name, length: length, width: width,
                purchasePrice: price, pricePerMeter: perMeter,
                purchaseDate: purchaseDate, note: note,
                materialId: materialID, channelId: channelID, tagIds: selectedTagIDsArray
            )
            newFabric.isFavorite = isFavorite
            store.addFabric(newFabric)
        }
        dismiss()
    }

    var body: some View {
        Form {
            Section("基本") {
                TextField("名称（可空）", text: $name)
                TextField("总长（米）", text: $lengthText).keyboardType(.decimalPad)
                TextField("幅宽（米）", text: $widthText).keyboardType(.decimalPad)
                TextField("总价（元）", text: $priceText).keyboardType(.decimalPad)
                TextField("单价（元/米，留空自动算）", text: $pricePerMeterText).keyboardType(.decimalPad)
                DatePicker("购买日期", selection: $purchaseDate, displayedComponents: .date)
                Toggle("收藏", isOn: $isFavorite)
            }
            Section("分类") {
                Picker("材质", selection: $materialID) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(materials) { Text($0.name).tag(Optional($0.id)) }
                }
                Picker("渠道", selection: $channelID) {
                    Text("未分类").tag(UUID?.none)
                    ForEach(channels) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("标签") {
                if tags.isEmpty {
                    Text("还没有标签，去设置里先加标签")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(tags) { tag in
                        Button(action: {
                            if selectedTagIDs.contains(tag.id) {
                                selectedTagIDs.remove(tag.id)
                            } else {
                                selectedTagIDs.insert(tag.id)
                            }
                        }) {
                            HStack {
                                Text(tag.name)
                                Spacer()
                                if selectedTagIDs.contains(tag.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            Section("备注") {
                TextField("备注", text: $note, axis: .vertical)
            }
            if let errorMessage {
                Text(errorMessage).foregroundColor(.red)
            }
        }
        .navigationTitle(fabric == nil ? "新增布料" : "编辑布料")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存", action: save)
            }
        }
    }
}
