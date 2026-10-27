import SwiftUI
import UniformTypeIdentifiers

enum DictKind: String, CaseIterable, Identifiable {
    case tag, material, channel
    var id: String { rawValue }
    var title: String {
        switch self {
        case .tag: return "标签"
        case .material: return "材质"
        case .channel: return "渠道"
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: Store

    @State private var showingImporter = false
    @State private var importSummary: String?
    @State private var showingSummary = false
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            List {
                Section("总览") {
                    LabeledContent("布料", value: "\(store.fabrics.count) 条")
                    LabeledContent("总长", value: "\(String(format: "%.2f", store.fabrics.reduce(0.0) { $0 + $1.length })) 米")
                    LabeledContent("剩余", value: "\(String(format: "%.2f", store.fabrics.reduce(0.0) { $0 + $1.remainingLength })) 米")
                    LabeledContent("总价", value: "¥\(String(format: "%.2f", store.fabrics.reduce(0.0) { $0 + $1.purchasePrice }))")
                    LabeledContent("作品 / 纸样 / 物品", value: "\(store.works.count) / \(store.patterns.count) / \(store.items.count)")
                }
                Section("字典管理") {
                    ForEach(DictKind.allCases) { kind in
                        NavigationLink(kind.title, destination: DictionaryView(kind: kind))
                    }
                }
                Section("数据导入导出") {
                    Button("导入原数据（选多个 CSV）") { showingImporter = true }
                    Button("导出全部数据为 CSV") {
                        exportURLs = CSVExporter.exportFiles(store: store)
                        showingExporter = true
                    }
                    Text("导入按原 UUID 匹配，重复导入会更新，不会重复建。图片文件按你的要求不导入。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Section("危险操作") {
                    Button("清空全部本地数据", role: .destructive) { showingClearConfirm = true }
                }
                Section("关于") {
                    Text("布仓第一版：本机存储，不联网，不做 iCloud 同步，不做订阅。")
                    Text("目标 iOS 16，可用 TrollStore 安装自己编译的包。")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("设置")
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let summary = CSVImporter.importFiles(urls, store: store)
                    importSummary = summary.text
                    showingSummary = true
                case .failure(let error):
                    importSummary = "选择文件失败：\(error.localizedDescription)"
                    showingSummary = true
                }
            }
            .alert("导入结果", isPresented: $showingSummary) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importSummary ?? "")
            }
            .sheet(isPresented: $showingExporter) {
                ActivityView(urls: exportURLs)
            }
            .alert("清空确认", isPresented: $showingClearConfirm) {
                Button("清空", role: .destructive) {
                    store.clearRecords()
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("此操作会删除本 App 里的全部布料、作品、纸样、物品和字典，无法恢复。先导出备份再清。")
            }
        }
    }
}

struct DictionaryView: View {
    @EnvironmentObject private var store: Store

    var kind: DictKind
    @State private var newName = ""
    @State private var showingAdd = false

    private var tags: [Tag] { store.tags.sorted { $0.sortOrder < $1.sortOrder } }
    private var materials: [Material] { store.materials.sorted { $0.sortOrder < $1.sortOrder } }
    private var channels: [Channel] { store.channels.sorted { $0.sortOrder < $1.sortOrder } }

    private var count: Int {
        switch kind {
        case .tag: return tags.count
        case .material: return materials.count
        case .channel: return channels.count
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        switch kind {
        case .tag:
            if tags.contains(where: { $0.name == name }) { return }
            store.addTag(Tag(name: name, sortOrder: tags.count))
        case .material:
            if materials.contains(where: { $0.name == name }) { return }
            store.addMaterial(Material(name: name, sortOrder: materials.count))
        case .channel:
            if channels.contains(where: { $0.name == name }) { return }
            store.addChannel(Channel(name: name, sortOrder: channels.count))
        }
        newName = ""
        showingAdd = false
    }

    private func delete(at offsets: IndexSet) {
        switch kind {
        case .tag:
            let toDelete = offsets.map { tags[$0] }
            for tag in toDelete { store.deleteTag(tag) }
        case .material:
            let toDelete = offsets.map { materials[$0] }
            for material in toDelete { store.deleteMaterial(material) }
        case .channel:
            let toDelete = offsets.map { channels[$0] }
            for channel in toDelete { store.deleteChannel(channel) }
        }
    }

    private func move(from source: IndexSet, to destination: Int) {
        switch kind {
        case .tag:
            var list = tags
            list.move(fromOffsets: source, toOffset: destination)
            for (index, tag) in list.enumerated() { tag.sortOrder = index }
            store.tags = list
            store.save()
        case .material:
            var list = materials
            list.move(fromOffsets: source, toOffset: destination)
            for (index, item) in list.enumerated() { item.sortOrder = index }
            store.materials = list
            store.save()
        case .channel:
            var list = channels
            list.move(fromOffsets: source, toOffset: destination)
            for (index, item) in list.enumerated() { item.sortOrder = index }
            store.channels = list
            store.save()
        }
    }

    var body: some View {
        List {
            switch kind {
            case .tag:
                ForEach(tags) { Text($0.name) }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
            case .material:
                ForEach(materials) { Text($0.name) }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
            case .channel:
                ForEach(channels) { Text($0.name) }
                    .onDelete(perform: delete)
                    .onMove(perform: move)
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: { showingAdd = true }) { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                EditButton()
            }
        }
        .alert("新增\(kind.title)", isPresented: $showingAdd) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("添加", action: add)
        } message: {
            Text("同名不能重复。")
        }
        .overlay {
            if count == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "tag")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text("暂无\(kind.title)")
                        .font(.headline)
                    Text("点右上角加号新增")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}

struct ActivityView: UIViewControllerRepresentable {
    var urls: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
