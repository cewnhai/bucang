import SwiftUI

// MARK: - 作品

struct WorkListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var searchText = ""

    private var works: [Work] { store.works.sorted { $0.createdAt > $1.createdAt } }

    private var filtered: [Work] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty { return works }
        return works.filter { $0.name.localizedCaseInsensitiveContains(keyword) || $0.note.localizedCaseInsensitiveContains(keyword) }
    }

    private var emptyPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "tshirt")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("暂无作品")
                .font(.headline)
            Text("点右上角加号新增")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { work in
                    NavigationLink(destination: WorkEditView(work: work)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(work.name.isEmpty ? "未命名作品" : work.name).font(.headline)
                            Text("进度 \(Int(work.progress))% · 成本 ¥\(work.costPrice, specifier: "%.2f") · 售价 ¥\(work.sellPrice, specifier: "%.2f")")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { filtered[$0] }
                    for work in toDelete { store.deleteWork(work) }
                }
            }
            .searchable(text: $searchText, prompt: "搜索作品")
            .navigationTitle("作品")
            .toolbar { Button(action: { showingAdd = true }) { Image(systemName: "plus") } }
            .sheet(isPresented: $showingAdd) { NavigationStack { WorkEditView(work: nil) } }
            .overlay {
                if filtered.isEmpty {
                    emptyPlaceholder
                }
            }
        }
    }
}

struct WorkEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var work: Work?
    @State private var name: String
    @State private var progressText: String
    @State private var costText: String
    @State private var sellText: String
    @State private var hoursText: String
    @State private var note: String

    init(work: Work?) {
        self.work = work
        _name = State(initialValue: work?.name ?? "")
        _progressText = State(initialValue: work == nil ? "" : String(Int(work!.progress)))
        _costText = State(initialValue: work == nil ? "" : String(work!.costPrice))
        _sellText = State(initialValue: work == nil ? "" : String(work!.sellPrice))
        _hoursText = State(initialValue: work == nil ? "" : String(work!.timeHours))
        _note = State(initialValue: work?.note ?? "")
    }

    var body: some View {
        Form {
            TextField("作品名称", text: $name)
            TextField("进度（0-100）", text: $progressText).keyboardType(.decimalPad)
            TextField("成本价（元）", text: $costText).keyboardType(.decimalPad)
            TextField("售价（元）", text: $sellText).keyboardType(.decimalPad)
            TextField("累计工时（小时）", text: $hoursText).keyboardType(.decimalPad)
            TextField("备注", text: $note, axis: .vertical)
            if let work {
                Button("删除这个作品", role: .destructive) {
                    store.deleteWork(work)
                    dismiss()
                }
            }
        }
        .navigationTitle(work == nil ? "新增作品" : "编辑作品")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    let progress = min(100, max(0, Double(progressText) ?? 0))
                    if let existing = work {
                        existing.name = name
                        existing.progress = progress
                        existing.costPrice = Double(costText) ?? 0
                        existing.sellPrice = Double(sellText) ?? 0
                        existing.timeHours = Double(hoursText) ?? 0
                        existing.note = note
                        store.save()
                    } else {
                        store.addWork(Work(name: name, progress: progress, costPrice: Double(costText) ?? 0, sellPrice: Double(sellText) ?? 0, timeHours: Double(hoursText) ?? 0, note: note))
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 纸样

struct PatternListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var searchText = ""

    private var patterns: [Pattern] { store.patterns.sorted { $0.createdAt > $1.createdAt } }

    private var filtered: [Pattern] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty { return patterns }
        return patterns.filter { $0.name.localizedCaseInsensitiveContains(keyword) || $0.note.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { pattern in
                    NavigationLink(destination: PatternEditView(pattern: pattern)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(pattern.name.isEmpty ? "未命名纸样" : pattern.name).font(.headline)
                            Text("价格 ¥\(pattern.price, specifier: "%.2f") · 片数 \(pattern.pieceCount)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { filtered[$0] }
                    for pattern in toDelete { store.deletePattern(pattern) }
                }
            }
            .searchable(text: $searchText, prompt: "搜索纸样")
            .navigationTitle("纸样")
            .toolbar { Button(action: { showingAdd = true }) { Image(systemName: "plus") } }
            .sheet(isPresented: $showingAdd) { NavigationStack { PatternEditView(pattern: nil) } }
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "doc")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无纸样")
                            .font(.headline)
                        Text("点右上角加号新增")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct PatternEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var pattern: Pattern?
    @State private var name: String
    @State private var priceText: String
    @State private var pieceText: String
    @State private var sizeDesc: String
    @State private var note: String

    init(pattern: Pattern?) {
        self.pattern = pattern
        _name = State(initialValue: pattern?.name ?? "")
        _priceText = State(initialValue: pattern == nil ? "" : String(pattern!.price))
        _pieceText = State(initialValue: pattern == nil ? "" : String(pattern!.pieceCount))
        _sizeDesc = State(initialValue: pattern?.sizeDesc ?? "")
        _note = State(initialValue: pattern?.note ?? "")
    }

    var body: some View {
        Form {
            TextField("纸样名称", text: $name)
            TextField("价格（元）", text: $priceText).keyboardType(.decimalPad)
            TextField("片数", text: $pieceText).keyboardType(.numberPad)
            TextField("尺寸说明（如 S/M/L/均码）", text: $sizeDesc)
            TextField("备注", text: $note, axis: .vertical)
            if let pattern {
                Button("删除这个纸样", role: .destructive) {
                    store.deletePattern(pattern)
                    dismiss()
                }
            }
        }
        .navigationTitle(pattern == nil ? "新增纸样" : "编辑纸样")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if let existing = pattern {
                        existing.name = name
                        existing.price = Double(priceText) ?? 0
                        existing.pieceCount = Int(pieceText) ?? 0
                        existing.sizeDesc = sizeDesc
                        existing.note = note
                        store.save()
                    } else {
                        store.addPattern(Pattern(name: name, price: Double(priceText) ?? 0, pieceCount: Int(pieceText) ?? 0, sizeDesc: sizeDesc, note: note))
                    }
                    dismiss()
                }
            }
        }
    }
}

// MARK: - 物品

struct ItemListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var searchText = ""

    private var items: [Item] { store.items.sorted { $0.createdAt > $1.createdAt } }

    private var filtered: [Item] {
        let keyword = searchText.trimmingCharacters(in: .whitespaces)
        if keyword.isEmpty { return items }
        return items.filter { $0.name.localizedCaseInsensitiveContains(keyword) || $0.note.localizedCaseInsensitiveContains(keyword) }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(filtered) { item in
                    NavigationLink(destination: ItemEditView(item: item)) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.name.isEmpty ? "未命名物品" : item.name).font(.headline)
                            Text("价格 ¥\(item.price, specifier: "%.2f") · 数量 \(item.quantity)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .onDelete { indexSet in
                    let toDelete = indexSet.map { filtered[$0] }
                    for item in toDelete { store.deleteItem(item) }
                }
            }
            .searchable(text: $searchText, prompt: "搜索物品")
            .navigationTitle("物品")
            .toolbar { Button(action: { showingAdd = true }) { Image(systemName: "plus") } }
            .sheet(isPresented: $showingAdd) { NavigationStack { ItemEditView(item: nil) } }
            .overlay {
                if filtered.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "bag")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text("暂无物品")
                            .font(.headline)
                        Text("点右上角加号新增")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
}

struct ItemEditView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: Item?
    @State private var name: String
    @State private var priceText: String
    @State private var quantityText: String
    @State private var sizeDesc: String
    @State private var note: String

    init(item: Item?) {
        self.item = item
        _name = State(initialValue: item?.name ?? "")
        _priceText = State(initialValue: item == nil ? "" : String(item!.price))
        _quantityText = State(initialValue: item == nil ? "" : String(item!.quantity))
        _sizeDesc = State(initialValue: item?.sizeDesc ?? "")
        _note = State(initialValue: item?.note ?? "")
    }

    var body: some View {
        Form {
            TextField("物品名称", text: $name)
            TextField("价格（元）", text: $priceText).keyboardType(.decimalPad)
            TextField("数量", text: $quantityText).keyboardType(.numberPad)
            TextField("尺寸说明", text: $sizeDesc)
            TextField("备注", text: $note, axis: .vertical)
            if let item {
                Button("删除这个物品", role: .destructive) {
                    store.deleteItem(item)
                    dismiss()
                }
            }
        }
        .navigationTitle(item == nil ? "新增物品" : "编辑物品")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") {
                    if let existing = item {
                        existing.name = name
                        existing.price = Double(priceText) ?? 0
                        existing.quantity = Int(quantityText) ?? 0
                        existing.sizeDesc = sizeDesc
                        existing.note = note
                        store.save()
                    } else {
                        store.addItem(Item(name: name, price: Double(priceText) ?? 0, quantity: Int(quantityText) ?? 0, sizeDesc: sizeDesc, note: note))
                    }
                    dismiss()
                }
            }
        }
    }
}
