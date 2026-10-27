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

// MARK: - 我的：用户卡片 + WebDAV 备份 + 数据管理 + 字典管理 + 关于
// 清空行为和提示文案保持原样：提示说会删字典，但实际 clearRecords()
// 只清布料（含使用记录）、作品、纸样、物品，字典保留（见 Models.swift 注释）。
// 这里不悄悄改清空范围，只保留原有行为和原有提示。

struct ProfileView: View {
    @EnvironmentObject private var store: Store

    @State private var showingImporter = false
    @State private var importSummary: String?
    @State private var showingSummary = false
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var showingClearConfirm = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 用户卡片
                    HStack(spacing: 14) {
                        ZStack {
                            Circle()
                                .fill(Design.accentSoft)
                                .frame(width: 60, height: 60)
                            Image(systemName: "scissors")
                                .font(.title2)
                                .foregroundColor(Design.accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的布仓")
                                .font(.title3)
                                .fontWeight(.bold)
                            Text("本地数据 · \(store.fabrics.count) 块布料 · \(store.works.count) 个作品")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Design.card)
                    .cornerRadius(Design.corner)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)

                    // WebDAV 备份卡片
                    CardView {
                        WebDAVBackupView()
                    }

                    // 数据管理卡片
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "数据管理", subtitle: "CSV 是原数据格式，导入按原 UUID 更新不重复建")
                            Button("导入原数据（选多个 CSV）") { showingImporter = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Design.accent)
                            Button("导出全部数据为 CSV") {
                                exportURLs = CSVExporter.exportFiles(store: store)
                                showingExporter = true
                            }
                            .buttonStyle(.bordered)
                            .tint(Design.accent)
                            Text("导入按原 UUID 匹配，重复导入会更新，不会重复建。图片文件按你的要求不导入。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Divider()
                            Button("清空全部本地数据", role: .destructive) { showingClearConfirm = true }
                        }
                    }

                    // 字典管理卡片
                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderView(title: "字典管理", subtitle: "标签 / 材质 / 渠道，点进去可以新增、删除、拖动排序")
                            ForEach(DictKind.allCases) { kind in
                                NavigationLink(destination: DictionaryView(kind: kind)) {
                                    HStack {
                                        Text(kind.title)
                                        Spacer()
                                        Text("\(kind == .tag ? store.tags.count : kind == .material ? store.materials.count : store.channels.count) 个")
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.right")
                                            .foregroundColor(.secondary)
                                            .font(.caption)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    // 关于卡片
                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderView(title: "关于")
                            Text("布仓：本机存储，不做 iCloud 同步，不做订阅。")
                            Text("目标 iOS 16，可用 TrollStore 安装自己编译的包。")
                            Text("本机数据在 Documents/bucang-store.json，图片在 Documents/bucang-images/，WebDAV 备份文件默认 bucang-backup.json，包含全部数据和图片。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Design.background)
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
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
