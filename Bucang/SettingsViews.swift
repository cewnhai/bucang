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

enum ImportKind {
    case csv, zip
}

// 本地压缩包（无需选择器）：只列 Documents 根目录和 Documents/Inbox/ 里的 .zip，
// 不扫描 bucang-images/ 等子文件夹，导入后不删除原压缩包。
struct LocalZipFile: Identifiable {
    var id: URL { url }
    var url: URL
    var size: Int64
    var modified: Date
}

struct ProfileView: View {
    @EnvironmentObject private var store: Store

    @State private var showingImporter = false
    @State private var importKind: ImportKind = .csv
    @State private var importSummary: String?
    @State private var showingSummary = false
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var showingClearConfirm = false
    @State private var zipDocument: ZipBackupDocument?
    @State private var showingZipExporter = false
    @State private var localZips: [LocalZipFile] = []

    // 只扫描 Documents 根目录和 Documents/Inbox/，Inbox 不存在时当作空，不崩溃也不强制创建。
    private func refreshLocalZips() {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            localZips = []
            return
        }
        var found: [LocalZipFile] = []
        for directory in [documents, documents.appendingPathComponent("Inbox")] {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            for url in urls {
                guard url.pathExtension.lowercased() == "zip" else { continue }
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory),
                      !isDirectory.boolValue else { continue }
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                found.append(LocalZipFile(
                    url: url,
                    size: Int64(values?.fileSize ?? 0),
                    modified: values?.contentModificationDate ?? Date.distantPast
                ))
            }
        }
        found.sort {
            if $0.modified != $1.modified { return $0.modified > $1.modified }
            return $0.url.lastPathComponent < $1.url.lastPathComponent
        }
        localZips = found
    }

    private func formattedSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 {
            return String(format: "%.1f MB", Double(bytes) / 1_048_576.0)
        } else {
            return String(format: "%.1f KB", Double(bytes) / 1024.0)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    // 本地列表导入：文件已在本 App 自己的 Documents 里，直接读，不需要选择器，
    // 也不需要 security-scoped 访问；走和选择器同一条 ZipBackup.importZip，导入后不删文件。
    private func importLocalZip(_ file: LocalZipFile) {
        if let data = try? Data(contentsOf: file.url) {
            importSummary = ZipBackup.importZip(data, store: store).text
        } else {
            importSummary = "读不到压缩包文件。"
        }
        showingSummary = true
        refreshLocalZips()
    }

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
                            Button("导入原数据（选多个 CSV）") { importKind = .csv; showingImporter = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Design.accent)
                            Button("导出全部数据为 CSV") {
                                exportURLs = CSVExporter.exportFiles(store: store)
                                showingExporter = true
                            }
                            .buttonStyle(.bordered)
                            .tint(Design.accent)
                            Button("导出备份压缩包 (.zip)") {
                                if let data = ZipBackup.buildExportData(store: store) {
                                    zipDocument = ZipBackupDocument(data: data)
                                    showingZipExporter = true
                                } else {
                                    importSummary = "生成备份压缩包失败，请重试。"
                                    showingSummary = true
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(Design.accent)
                            Button("导入备份压缩包 (.zip)") { importKind = .zip; showingImporter = true }
                                .buttonStyle(.borderedProminent)
                                .tint(Design.accent)
                            Text("导入按原 UUID 匹配，重复导入会更新，不会重复建。单 CSV 导入不读图片；压缩包导入会按原 zip 格式读 CSV + 图片，也能读自家备份（含 JSON 全量 + 图片）。如果选不到文件，可在文件 App 里长按压缩包 > 分享 > 布仓直接导入。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Divider()
                            Button("清空全部本地数据", role: .destructive) { showingClearConfirm = true }
                        }
                    }

                    // 本地压缩包（无需选择器）：不走系统选择器、不走分享弹窗，
                    // 直接列出布仓文件夹里的压缩包，点“导入”就走同一条 ZipBackup.importZip。
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(
                                title: "本地压缩包（无需选择器）",
                                subtitle: "不走系统选择器，直接读布仓文件夹里的压缩包"
                            )
                            Text("在文件 App 里，把压缩包移到 我的iPhone > Bucang 文件夹（或分享到布仓），然后回来点下面列表里的文件导入。")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button("刷新列表") { refreshLocalZips() }
                                .buttonStyle(.bordered)
                                .tint(Design.accent)
                            if localZips.isEmpty {
                                Text("Bucang 文件夹里还没有压缩包，请先在文件 App 里把压缩包移到 我的iPhone > Bucang")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(localZips) { file in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.url.lastPathComponent)
                                                .font(.subheadline)
                                                .lineLimit(2)
                                            Text("\(formattedSize(file.size)) · \(formattedDate(file.modified))")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("导入") { importLocalZip(file) }
                                            .buttonStyle(.borderedProminent)
                                            .tint(Design.accent)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
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
            .onAppear { refreshLocalZips() }
            .navigationTitle("我的")
            .navigationBarTitleDisplayMode(.inline)
            // 单一选择器：同一视图上挂两个 fileImporter 会冲突，导致
            // zip 选择器实际按 CSV 类型过滤、zip 文件变灰选不了。
            // zip 改用通用文件类型 UTType.data，让所有文件都可选，
            // 再在代码里按 .zip 后缀校验，避免 UTType.zip 在
            // iOS 16.3.1 上对别家 App 导出的 zip 过滤过严。
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: importKind == .zip ? [UTType.data] : [UTType.commaSeparatedText],
                allowsMultipleSelection: importKind == .csv
            ) { result in
                switch result {
                case .success(let urls):
                    if importKind == .csv {
                        let summary = CSVImporter.importFiles(urls, store: store)
                        importSummary = summary.text
                    } else if let url = urls.first {
                        if url.pathExtension.lowercased() == "zip" {
                            let accessing = url.startAccessingSecurityScopedResource()
                            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url) {
                                let summary = ZipBackup.importZip(data, store: store)
                                importSummary = summary.text
                            } else {
                                importSummary = "读不到压缩包文件。"
                            }
                        } else {
                            importSummary = "请选择 .zip 文件，当前选的是 \(url.lastPathComponent)"
                        }
                    } else {
                        importSummary = "没有选到文件。"
                    }
                    showingSummary = true
                    refreshLocalZips()
                case .failure(let error):
                    importSummary = "选择文件失败：\(error.localizedDescription)"
                    showingSummary = true
                }
            }
            .fileExporter(
                isPresented: $showingZipExporter,
                document: zipDocument,
                contentType: UTType.zip,
                defaultFilename: ZipBackup.defaultExportFileName()
            ) { result in
                if case .failure(let error) = result {
                    importSummary = "导出压缩包失败：\(error.localizedDescription)"
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
