import SwiftUI
import PhotosUI
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

enum ImportKind {
    case csv, zip
}

struct LocalZipFile: Identifiable {
    var id: URL { url }
    var url: URL
    var size: Int64
    var modified: Date
}

enum LocalZipHelper {
    static func list() -> [LocalZipFile] {
        let fileManager = FileManager.default
        guard let documents = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
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
        return found
    }
    static func formattedSize(_ bytes: Int64) -> String {
        if bytes >= 1_048_576 { return String(format: "%.1f MB", Double(bytes) / 1_048_576.0) }
        return String(format: "%.1f KB", Double(bytes) / 1024.0)
    }
    static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - V3 设置页（底部导航右项）

struct SettingsView: View {
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
    @State private var newMaterial = ""
    @State private var newCategory = ""
    @State private var newChannel = ""
    @State private var renamingMaterial: String?
    @State private var renamingCategory: String?
    @State private var renamingChannel: String?
    @State private var renameText = ""
    @State private var themePickerItems: [PhotosPickerItem] = []
    @State private var themeImageStamp = Date()

    private func refreshLocalZips() { localZips = LocalZipHelper.list() }
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
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().fill(Design.accentSoft).frame(width: 60, height: 60)
                            Image(systemName: "scissors").font(.title2).foregroundColor(Design.accent)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text("我的布仓").font(.title3).fontWeight(.bold)
                            Text("本地数据 · \(store.fabrics.count) 块布料 · \(store.works.count) 个成品 · \(store.otherItems.count) 个其他 · \(store.wishlistItems.count) 个心愿")
                                .font(.subheadline).foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(16)
                    .background(Design.card)
                    .cornerRadius(Design.corner)
                    .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "全局设置", subtitle: "长度单位全库统一，内部按米存，显示时换算")
                            Picker("长度单位", selection: Binding(
                                get: { store.lengthUnit },
                                set: { store.lengthUnit = $0; store.save() }
                            )) {
                                Text("米").tag("米")
                                Text("厘米").tag("厘米")
                                Text("码").tag("码")
                            }
                            .pickerStyle(.segmented)
                            Toggle("金额默认隐藏（统计卡总价值默认打星）", isOn: Binding(
                                get: { store.hideAmounts },
                                set: { store.hideAmounts = $0; store.save() }
                            ))
                            TextField("编号体系前缀（如 B、FAB，生成编号时用）", text: Binding(
                                get: { store.codePrefix },
                                set: { store.codePrefix = $0; store.save() }
                            ))
                            .textFieldStyle(.roundedBorder)
                            Text("编号唯一且重复时禁止保存，保存时会提示与哪条档案冲突。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "编号体系", subtitle: "多级编号的层级与条目配置，历史编号不受影响")
                            NavigationLink(destination: CodeLevelsEditorView()) {
                                HStack {
                                    Text("编号体系层级设置")
                                    Spacer()
                                    Text("\(store.codeLevels.count) 级").foregroundColor(.secondary)
                                    Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                                }
                                .foregroundColor(.primary)
                                .padding(.vertical, 6)
                            }
                            NavigationLink(destination: ColorItemsSettingsView()) {
                                HStack {
                                    Text("颜色选项")
                                    Spacer()
                                    if let colorLevel = store.codeLevels.first(where: { $0.kind == "color" }) {
                                        Text("\(colorLevel.items.count) 条").foregroundColor(.secondary)
                                    } else {
                                        Text("未找到色系层级").foregroundColor(.secondary)
                                    }
                                    Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                                }
                                .foregroundColor(.primary)
                                .padding(.vertical, 6)
                            }
                            Text("关闭或删除层级只影响之后生成的新编号；历史编号保留，仍可按原编号筛选、排序。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "卡片显示信息", subtitle: "布料卡片上显示哪些字段，顺序固定")
                            ForEach(Store.cardFieldOptions, id: \.key) { option in
                                Toggle(option.title, isOn: Binding(
                                    get: { store.cardDisplayFields.contains(option.key) },
                                    set: { on in
                                        var keys = store.cardDisplayFields
                                        if on {
                                            if !keys.contains(option.key) { keys.append(option.key) }
                                        } else {
                                            keys.removeAll { $0 == option.key }
                                        }
                                        // 始终按规范顺序排列，保持卡片展示一致。
                                        store.cardDisplayFields = Store.cardFieldOptions.map { $0.key }.filter { keys.contains($0) }
                                        store.save()
                                    }
                                ))
                            }
                            Text("全不选时卡片不显示附加信息；下次打开设置页会恢复默认 5 项。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "渠道", subtitle: "布料渠道与出售渠道的选项；商家是渠道下二级自定义文本，在布料/出售表单里填")
                            HStack {
                                TextField("新增渠道", text: $newChannel)
                                    .textFieldStyle(.roundedBorder)
                                Button("添加") {
                                    let name = newChannel.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty, !store.channelOptions.contains(name) else { return }
                                    store.channelOptions.append(name); store.save(); newChannel = ""
                                }
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                            }
                            ForEach(store.channelOptions, id: \.self) { option in
                                HStack {
                                    Text(option)
                                    Spacer()
                                    Button("改名") { renamingChannel = option; renameText = option }
                                        .font(.caption)
                                    Button("删除", role: .destructive) {
                                        store.channelOptions.removeAll { $0 == option }; store.save()
                                    }
                                    .font(.caption)
                                }
                                .padding(.vertical, 2)
                            }
                            Text("筛选面板的渠道组读这里，外加数据里已有但不在选项里的渠道名，旧数据仍可筛选。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "顶栏显示", subtitle: "布仓顶部一级 Tab 的可见性，布料始终显示、不可关闭")
                            ForEach([("fabric", "布料"), ("work", "成品"), ("brainstorm", "脑洞"), ("other", "其他"), ("wishlist", "心愿单")], id: \.0) { key, title in
                                if key == "fabric" {
                                    HStack { Text(title); Spacer(); Text("始终显示").font(.caption).foregroundColor(.secondary) }
                                } else {
                                    Toggle(title, isOn: Binding(
                                        get: { (store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs).contains(key) },
                                        set: { on in
                                            var keys = store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs
                                            if on { if !keys.contains(key) { keys.append(key) } }
                                            else { keys.removeAll { $0 == key } }
                                            if !keys.contains("fabric") { keys.insert("fabric", at: 0) }
                                            store.visibleTabs = Store.allTabKeys.filter { keys.contains($0) }
                                            store.save()
                                        }
                                    ))
                                }
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "个性化", subtitle: "主题色系跟随统计卡、悬浮按钮、顶栏、状态胶囊；主题图只用在统计卡背景，不做全屏背景")
                            Picker("主题色系", selection: Binding(
                                get: { store.themeName },
                                set: { store.themeName = $0; store.save() }
                            )) {
                                ForEach(ThemeHelper.options, id: \.self) { Text($0).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            HStack {
                                Text(ThemeImageStore.exists() ? "已设置主题图（统计卡背景用图 + 深色遮罩）" : "未设置主题图（统计卡用纯主题色）")
                                    .font(.caption).foregroundColor(.secondary)
                                Spacer()
                                PhotosPicker(selection: $themePickerItems, maxSelectionCount: 1, matching: .images) {
                                    Text("选图作统计卡背景")
                                }
                                .buttonStyle(.bordered).tint(Design.accent)
                                if ThemeImageStore.exists() {
                                    Button("清除主题图", role: .destructive) {
                                        ThemeImageStore.clear()
                                        store.themeName = store.themeName
                                        themeImageStamp = Date()
                                    }
                                }
                            }
                            .onChange(of: themePickerItems) { items in
                                guard let item = items.first else { return }
                                themePickerItems = []
                                Task {
                                    if let data = try? await item.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data),
                                       ThemeImageStore.save(uiImage) {
                                        store.themeName = store.themeName
                                        themeImageStamp = Date()
                                    }
                                }
                            }
                            Text("暗黑模式下主题色卡片仍是白字，其余背景自适应。").font(.caption).foregroundColor(.secondary)
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "材质选项", subtitle: "布料材质单选的选项，筛选面板直接读这里")
                            HStack {
                                TextField("新增材质", text: $newMaterial)
                                    .textFieldStyle(.roundedBorder)
                                Button("添加") {
                                    let name = newMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty, !store.materialOptions.contains(name) else { return }
                                    store.materialOptions.append(name); store.save(); newMaterial = ""
                                }
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                            }
                            ForEach(store.materialOptions, id: \.self) { option in
                                HStack {
                                    Text(option)
                                    Spacer()
                                    Button("改名") { renamingMaterial = option; renameText = option }
                                        .font(.caption)
                                    Button("删除", role: .destructive) {
                                        store.materialOptions.removeAll { $0 == option }; store.save()
                                    }
                                    .font(.caption)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "其他分类", subtitle: "“其他” Tab 的分类，增删改名即时生效")
                            HStack {
                                TextField("新增分类", text: $newCategory)
                                    .textFieldStyle(.roundedBorder)
                                Button("添加") {
                                    let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
                                    guard !name.isEmpty, !store.otherCategories.contains(name) else { return }
                                    store.otherCategories.append(name); store.save(); newCategory = ""
                                }
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                            }
                            ForEach(store.otherCategories, id: \.self) { option in
                                HStack {
                                    Text(option)
                                    Spacer()
                                    Button("改名") { renamingCategory = option; renameText = option }
                                        .font(.caption)
                                    Button("删除", role: .destructive) {
                                        store.otherCategories.removeAll { $0 == option }; store.save()
                                    }
                                    .font(.caption)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "数据管理", subtitle: "CSV 是原数据格式，导入按原 UUID 更新不重复建")
                            Button("导入原数据（选多个 CSV）") { importKind = .csv; showingImporter = true }
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                            Button("导出全部数据为 CSV") {
                                exportURLs = CSVExporter.exportFiles(store: store); showingExporter = true
                            }
                            .buttonStyle(.bordered).tint(Design.accent)
                            Button("导出全字段空模板（批量初始化用）") {
                                exportURLs = CSVExporter.exportTemplateFiles(); showingExporter = true
                            }
                            .buttonStyle(.bordered).tint(Design.accent)
                            Button("导出备份压缩包 (.zip)") {
                                if let data = ZipBackup.buildExportData(store: store) {
                                    zipDocument = ZipBackupDocument(data: data); showingZipExporter = true
                                } else {
                                    importSummary = "生成备份压缩包失败，请重试."; showingSummary = true
                                }
                            }
                            .buttonStyle(.bordered).tint(Design.accent)
                            Button("导入备份压缩包 (.zip)") { importKind = .zip; showingImporter = true }
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                            Text("导入按原 UUID 匹配，重复导入会更新，不会重复建。压缩包导入会按原 zip 格式读 CSV + 图片，也能读自家备份（含 JSON 全量 + 图片）。如果选不到文件，可用下面本地压缩包列表导入。")
                                .font(.caption).foregroundColor(.secondary)
                            Divider()
                            Button("清空全部本地数据", role: .destructive) { showingClearConfirm = true }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: "本地压缩包（无需选择器）", subtitle: "不走系统选择器，直接读布仓文件夹里的压缩包")
                            Text("在文件 App 里，把压缩包移到 我的iPhone > Bucang 文件夹（或分享到布仓），然后回来点下面列表里的文件导入。")
                                .font(.caption).foregroundColor(.secondary)
                            Button("刷新列表") { refreshLocalZips() }
                                .buttonStyle(.bordered).tint(Design.accent)
                            if localZips.isEmpty {
                                Text("Bucang 文件夹里还没有压缩包，请先在文件 App 里把压缩包移到 我的iPhone > Bucang")
                                    .font(.subheadline).foregroundColor(.secondary)
                            } else {
                                ForEach(localZips) { file in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(file.url.lastPathComponent).font(.subheadline).lineLimit(2)
                                            Text("\(LocalZipHelper.formattedSize(file.size)) · \(LocalZipHelper.formattedDate(file.modified))")
                                                .font(.caption).foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Button("导入") { importLocalZip(file) }
                                            .buttonStyle(.borderedProminent).tint(Design.accent)
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        }
                    }

                    CardView {
                        WebDAVBackupView()
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderView(title: "字典管理", subtitle: "标签 / 渠道，点进去可以新增、删除、拖动排序（材质选项在上面单独管）")
                            ForEach([DictKind.tag, DictKind.channel]) { kind in
                                NavigationLink(destination: DictionaryView(kind: kind)) {
                                    HStack {
                                        Text(kind.title)
                                        Spacer()
                                        Text("\(kind == .tag ? store.tags.count : store.channels.count) 个")
                                            .foregroundColor(.secondary)
                                        Image(systemName: "chevron.right").foregroundColor(.secondary).font(.caption)
                                    }
                                    .foregroundColor(.primary)
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeaderView(title: "关于")
                            Text("布仓：本机存储，不做 iCloud 同步，不做订阅。")
                            Text("目标 iOS 16，可用 TrollStore 安装自己编译的包。")
                            Text("本机数据在 Documents/bucang-store.json，图片在 Documents/bucang-images/，WebDAV 备份文件默认 bucang-backup.json，包含全部数据和图片。")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Design.background)
            .onAppear { refreshLocalZips() }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: importKind == .zip ? [UTType.data] : [UTType.commaSeparatedText],
                allowsMultipleSelection: importKind == .csv
            ) { result in
                switch result {
                case .success(let urls):
                    if importKind == .csv {
                        importSummary = CSVImporter.importFiles(urls, store: store).text
                    } else if let url = urls.first {
                        if url.pathExtension.lowercased() == "zip" {
                            let accessing = url.startAccessingSecurityScopedResource()
                            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                            if let data = try? Data(contentsOf: url) {
                                importSummary = ZipBackup.importZip(data, store: store).text
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
            } message: { Text(importSummary ?? "") }
            .sheet(isPresented: $showingExporter) { ActivityView(urls: exportURLs) }
            .alert("清空确认", isPresented: $showingClearConfirm) {
                Button("清空", role: .destructive) { store.clearRecords() }
                Button("取消", role: .cancel) {}
            } message: { Text("此操作会删除本 App 里的全部布料、成品、其他、心愿单、使用与出售记录，无法恢复。先导出备份再清。") }
            .alert("改名", isPresented: Binding(
                get: { renamingMaterial != nil || renamingCategory != nil || renamingChannel != nil },
                set: { if !$0 { renamingMaterial = nil; renamingCategory = nil; renamingChannel = nil } }
            )) {
                TextField("新名称", text: $renameText)
                Button("取消", role: .cancel) { renamingMaterial = nil; renamingCategory = nil; renamingChannel = nil }
                Button("确定") {
                    let newName = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !newName.isEmpty {
                        if let old = renamingMaterial, let idx = store.materialOptions.firstIndex(of: old) {
                            store.materialOptions[idx] = newName
                            for fabric in store.fabrics where fabric.materialName == old { fabric.materialName = newName }
                        }
                        if let old = renamingCategory, let idx = store.otherCategories.firstIndex(of: old) {
                            store.otherCategories[idx] = newName
                            for item in store.otherItems where item.category == old { item.category = newName }
                        }
                        if let old = renamingChannel, let idx = store.channelOptions.firstIndex(of: old) {
                            store.channelOptions[idx] = newName
                            for fabric in store.fabrics where fabric.channelName == old { fabric.channelName = newName }
                            for record in store.saleRecords where record.channel == old { record.channel = newName }
                        }
                        store.save()
                    }
                    renamingMaterial = nil; renamingCategory = nil; renamingChannel = nil
                }
            } message: { Text("改名会同步改已用该选项的记录。") }
        }
    }
}

// MARK: - 布仓工具行导入导出弹层（复用同一导入导出逻辑，不含本地列表）

struct ImportExportSheetView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @State private var showingImporter = false
    @State private var importKind: ImportKind = .csv
    @State private var importSummary: String?
    @State private var showingSummary = false
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var zipDocument: ZipBackupDocument?
    @State private var showingZipExporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("导入导出").font(.headline)
                Button("导入原数据（选多个 CSV）") { importKind = .csv; showingImporter = true }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                Button("导出全部数据为 CSV") { exportURLs = CSVExporter.exportFiles(store: store); showingExporter = true }
                    .buttonStyle(.bordered).tint(Design.accent)
                Button("导出备份压缩包 (.zip)") {
                    if let data = ZipBackup.buildExportData(store: store) {
                        zipDocument = ZipBackupDocument(data: data); showingZipExporter = true
                    }
                }
                .buttonStyle(.bordered).tint(Design.accent)
                Button("导入备份压缩包 (.zip)") { importKind = .zip; showingImporter = true }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                Text("如果在选择器里选不到 zip 文件，请用设置页的“本地压缩包（无需选择器）”列表导入：把压缩包移到文件 App 的 Bucang 文件夹，再回设置页点列表里的导入。")
                    .font(.caption).foregroundColor(.secondary)
                Button("完成") { dismiss() }
                    .buttonStyle(.bordered).tint(Design.accent)
            }
            .padding()
        }
        .background(Design.background)
        .navigationTitle("导入导出")
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: importKind == .zip ? [UTType.data] : [UTType.commaSeparatedText],
            allowsMultipleSelection: importKind == .csv
        ) { result in
            switch result {
            case .success(let urls):
                if importKind == .csv {
                    importSummary = CSVImporter.importFiles(urls, store: store).text
                } else if let url = urls.first, url.pathExtension.lowercased() == "zip" {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url) {
                        importSummary = ZipBackup.importZip(data, store: store).text
                    } else {
                        importSummary = "读不到压缩包文件。"
                    }
                } else {
                    importSummary = "请选择 .zip 文件。"
                }
                showingSummary = true
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
        ) { _ in }
        .alert("导入结果", isPresented: $showingSummary) {
            Button("好", role: .cancel) {}
        } message: { Text(importSummary ?? "") }
        .sheet(isPresented: $showingExporter) { ActivityView(urls: exportURLs) }
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
            store.tags = list; store.save()
        case .material:
            var list = materials
            list.move(fromOffsets: source, toOffset: destination)
            for (index, item) in list.enumerated() { item.sortOrder = index }
            store.materials = list; store.save()
        case .channel:
            var list = channels
            list.move(fromOffsets: source, toOffset: destination)
            for (index, item) in list.enumerated() { item.sortOrder = index }
            store.channels = list; store.save()
        }
    }

    var body: some View {
        List {
            switch kind {
            case .tag:
                ForEach(tags) { Text($0.name) }.onDelete(perform: delete).onMove(perform: move)
            case .material:
                ForEach(materials) { Text($0.name) }.onDelete(perform: delete).onMove(perform: move)
            case .channel:
                ForEach(channels) { Text($0.name) }.onDelete(perform: delete).onMove(perform: move)
            }
        }
        .navigationTitle(kind.title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button(action: { showingAdd = true }) { Image(systemName: "plus") } }
            ToolbarItem(placement: .secondaryAction) { EditButton() }
        }
        .alert("新增\(kind.title)", isPresented: $showingAdd) {
            TextField("名称", text: $newName)
            Button("取消", role: .cancel) {}
            Button("添加", action: add)
        } message: { Text("同名不能重复。") }
        .overlay {
            if count == 0 {
                VStack(spacing: 8) {
                    Image(systemName: "tag").font(.largeTitle).foregroundColor(.secondary)
                    Text("暂无\(kind.title)").font(.headline)
                    Text("点右上角加号新增").font(.caption).foregroundColor(.secondary)
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

// MARK: - 编号体系：层级与条目编辑（V8）

// 层级种类标签（kind 只读展示，不允许改种类）。
enum CodeKindLabel {
    static let all: [(key: String, title: String)] = [
        ("color", "色系"), ("pattern", "纹样"), ("sequence", "序号"), ("width", "幅宽"), ("note", "备注"),
    ]
    static func label(_ kind: String) -> String {
        all.first { $0.key == kind }?.title ?? kind
    }
}

// 设置 > 编号体系 > 编号体系层级设置：层级列表（排序/开关/删除/新增）。
struct CodeLevelsEditorView: View {
    @EnvironmentObject private var store: Store
    @State private var newLevelName = ""
    @State private var newLevelKind = "color"
    @State private var deletingLevel: CodeLevel?

    private func moveLevel(_ level: CodeLevel, by delta: Int) {
        guard let idx = store.codeLevels.firstIndex(where: { $0.id == level.id }) else { return }
        let target = idx + delta
        guard target >= 0, target < store.codeLevels.count else { return }
        store.codeLevels.swapAt(idx, target)
        store.save()
    }

    private func addLevel() {
        let name = newLevelName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.codeLevels.append(CodeLevel(name: name, kind: newLevelKind, separatorBefore: "-"))
        store.save()
        newLevelName = ""
    }

    var body: some View {
        List {
            Section {
                ForEach(store.codeLevels) { level in
                    let idx = store.codeLevels.firstIndex(where: { $0.id == level.id }) ?? 0
                    NavigationLink(destination: CodeLevelEditView(level: level)) {
                        HStack(spacing: 6) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(level.name.isEmpty ? "未命名层级" : level.name)
                                Text(CodeKindLabel.label(level.kind))
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("启用", isOn: Binding(
                                get: { level.enabled },
                                set: { level.enabled = $0; store.save() }
                            ))
                            .labelsHidden()
                            Button(action: { moveLevel(level, by: -1) }) {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx == 0)
                            Button(action: { moveLevel(level, by: 1) }) {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(idx == store.codeLevels.count - 1)
                            Button(role: .destructive, action: { deletingLevel = level }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            } footer: {
                Text("关闭的层级不参与新编号生成（生成器里隐藏）；删除层级只影响之后生成的新编号，历史编号保留，仍可按原编号筛选、排序。")
            }

            Section("添加层级") {
                TextField("层级名称（如 色系）", text: $newLevelName)
                VStack(alignment: .leading, spacing: 8) {
                    Text("编号类别").font(.subheadline).foregroundColor(.secondary)
                    // 点右侧类别自动填入层级名称（之后仍可点名称框改成自定义文本）。
                    HStack(spacing: 8) {
                        ForEach(CodeKindLabel.all, id: \.key) { kind in
                            Button(action: {
                                newLevelKind = kind.key
                                newLevelName = kind.title
                            }) {
                                Text(kind.title)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10).padding(.vertical, 7)
                                    .background(newLevelKind == kind.key
                                        ? Design.accentSoft
                                        : Color(UIColor.secondarySystemBackground))
                                    .foregroundColor(newLevelKind == kind.key ? Design.accent : .primary)
                                    .cornerRadius(9)
                            }
                            .buttonStyle(.plain)
                        }
                        Spacer(minLength: 0)
                    }
                }
                if newLevelKind == "sequence",
                   store.codeLevels.contains(where: { $0.kind == "sequence" }) {
                    Text("已有序号层级，再添加一个可能让编号生成混乱（仍可继续）。")
                        .font(.caption).foregroundColor(.orange)
                }
            }

            // 添加按钮独占一行、居中：主题色淡底 + 主色字。
            Section {
                HStack {
                    Spacer()
                    Button("添加层级", action: addLevel)
                        .font(.headline)
                        .padding(.horizontal, 40).padding(.vertical, 10)
                        .background(Design.accentSoft)
                        .foregroundColor(Design.accent)
                        .cornerRadius(12)
                        .opacity(newLevelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.45 : 1)
                        .disabled(newLevelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }
            }
        }
        .navigationTitle("编号体系层级")
        .navigationBarTitleDisplayMode(.inline)
        .alert("删除层级", isPresented: Binding(
            get: { deletingLevel != nil },
            set: { if !$0 { deletingLevel = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let level = deletingLevel {
                    store.codeLevels.removeAll { $0.id == level.id }
                    store.save()
                }
                deletingLevel = nil
            }
            Button("取消", role: .cancel) { deletingLevel = nil }
        } message: {
            Text("删除后该段不再参与新编号生成，历史编号保留、不受影响。")
        }
    }
}

// 点某层级进入：改名 / 分隔符 / 序号位数 / 条目增删改开关。
struct CodeLevelEditView: View {
    @EnvironmentObject private var store: Store
    let level: CodeLevel
    @State private var newItemName = ""
    @State private var newItemCode = ""
    @State private var newItemIcon = ""
    @State private var editingItem: CodeItem?
    @State private var deletingItem: CodeItem?

    private func addItem() {
        let name = newItemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        level.items.append(CodeItem(
            name: name,
            code: newItemCode.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: newItemIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        store.save()
        newItemName = ""; newItemCode = ""; newItemIcon = ""
    }

    var body: some View {
        List {
            Section("基本信息") {
                TextField("层级名称", text: Binding(
                    get: { level.name },
                    set: { level.name = $0; store.save() }
                ))
                HStack {
                    Text("编号类别")
                    Spacer()
                    Text(CodeKindLabel.label(level.kind)).foregroundColor(.secondary)
                }
                TextField("段前分隔符（如 -）", text: Binding(
                    get: { level.separatorBefore },
                    set: { level.separatorBefore = $0; store.save() }
                ))
                if level.kind == "sequence" {
                    Stepper("序号位数：\(level.digits)", value: Binding(
                        get: { level.digits },
                        set: { level.digits = max(1, $0); store.save() }
                    ), in: 1...6)
                }
                Toggle("启用", isOn: Binding(
                    get: { level.enabled },
                    set: { level.enabled = $0; store.save() }
                ))
            }

            if level.kind == "sequence" {
                Section {
                    Text("序号自动递增，无需条目。")
                        .font(.caption).foregroundColor(.secondary)
                }
            } else {
                Section(header: Text("条目"), footer: Text("关闭的条目在编号生成器里隐藏，不影响已有编号。")) {
                    ForEach(level.items) { item in
                        HStack(spacing: 8) {
                            Button(action: { editingItem = item }) {
                                HStack(spacing: 8) {
                                    if !item.icon.isEmpty { CodeItemIconView(icon: item.icon, size: 24) }
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name.isEmpty ? "未命名" : item.name)
                                        Text("代码：\(item.code.isEmpty ? "—" : item.code)")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Toggle("启用", isOn: Binding(
                                get: { item.enabled },
                                set: { item.enabled = $0; store.save() }
                            ))
                            .labelsHidden()
                            Button(role: .destructive, action: { deletingItem = item }) {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    VStack(spacing: 8) {
                        TextField("条目名称", text: $newItemName)
                        TextField("条目代码", text: $newItemCode)
                        TextField("图标（可选，如 🔴）", text: $newItemIcon)
                        Button("添加条目", action: addItem)
                            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
            }
        }
        .navigationTitle(level.name.isEmpty ? "层级设置" : level.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingItem) { item in
            CodeItemEditSheet(item: item)
        }
        .alert("删除条目", isPresented: Binding(
            get: { deletingItem != nil },
            set: { if !$0 { deletingItem = nil } }
        )) {
            Button("删除", role: .destructive) {
                if let item = deletingItem {
                    level.items.removeAll { $0.id == item.id }
                    store.save()
                }
                deletingItem = nil
            }
            Button("取消", role: .cancel) { deletingItem = nil }
        } message: {
            Text("删除后该条目不再参与新编号生成，历史编号保留、不受影响。")
        }
    }
}

// 条目编辑弹层：名称 / 代码 / 图标 / 开关。
struct CodeItemEditSheet: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    let item: CodeItem

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: Binding(
                    get: { item.name },
                    set: { item.name = $0; store.save() }
                ))
                TextField("代码", text: Binding(
                    get: { item.code },
                    set: { item.code = $0; store.save() }
                ))
                TextField("图标（可选）", text: Binding(
                    get: { item.icon },
                    set: { item.icon = $0; store.save() }
                ))
                Toggle("启用", isOn: Binding(
                    get: { item.enabled },
                    set: { item.enabled = $0; store.save() }
                ))
            }
            .navigationTitle("编辑条目")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// 设置 > 编号体系 > 颜色选项：直接编辑色系层级的颜色条目。
// 无"色系"标题、无"基本信息"区；与编号生成器、布料表单共用同一色系层级
//（改 store.codeLevels 并 save）。
struct ColorItemsSettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var editingItemId: UUID?
    @State private var deletingItem: CodeItem?
    @State private var isEditing = false          // 自定义编辑模式（批量删除）
    @State private var selectedIds = Set<UUID>()  // 批量选中的 id
    // 添加颜色：内嵌选色器
    @State private var newColor = Color.red
    @State private var newName = ""
    @State private var newCode = ""

    private var colorLevel: CodeLevel? {
        store.codeLevels.first { $0.kind == "color" }
    }
    private var items: [CodeItem] { colorLevel?.items ?? [] }
    // "其他"固定项：rainbow 图标，不可删除
    private func isOtherItem(_ item: CodeItem) -> Bool { item.name == "其他" && item.icon == "rainbow" }

    // 行显示：有代码 → "名/码"（如 红/R），无代码 → 只有名。
    private func displayText(_ item: CodeItem) -> String {
        let name = item.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let code = item.code.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = name.isEmpty ? "未命名" : name
        return code.isEmpty ? base : "\(base)/\(code)"
    }

    private func addFromInlinePicker() {
        guard let level = colorLevel else { return }
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName: String
        if !name.isEmpty {
            finalName = name
        } else {
            var n = 1
            let existing = Set(level.items.map { $0.name })
            while existing.contains("自定义\(n)") { n += 1 }
            finalName = "自定义\(n)"
        }
        let item = CodeItem(
            name: finalName,
            code: newCode.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: newColor.toHex()
        )
        // "其他"固定项保持在末尾：新项插到它前面
        if let otherIdx = level.items.firstIndex(where: { isOtherItem($0) }) {
            level.items.insert(item, at: otherIdx)
        } else {
            level.items.append(item)
        }
        store.save()
        newName = ""; newCode = ""
        // 选色器复位为随机色，保证下次选相同颜色也有变化感
        newColor = Color(hue: Double.random(in: 0...1), saturation: 0.6, brightness: 0.9)
    }

    private func confirmDelete(_ item: CodeItem) {
        guard !isOtherItem(item) else { return }
        colorLevel?.items.removeAll { $0.id == item.id }
        selectedIds.remove(item.id)
        if editingItemId == item.id { editingItemId = nil }
        store.save()
    }

    private func deleteSelected() {
        let ids = selectedIds
        colorLevel?.items.removeAll { ids.contains($0.id) && !isOtherItem($0) }
        selectedIds.removeAll()
        store.save()
    }

    private func moveItem(from source: IndexSet, to destination: Int) {
        colorLevel?.items.move(fromOffsets: source, toOffset: destination)
        store.save()
    }

    // 行内编辑器：名称 + 代码（颜色改色直接在行内的选色器完成）。
    @ViewBuilder
    private func editRow(_ item: CodeItem) -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                CodeItemIconView(icon: item.icon, size: 28)
                TextField("颜色名（如 红）", text: Binding(
                    get: { item.name },
                    set: { item.name = $0; store.save() }
                ))
                .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 10) {
                TextField("代码（如 R，可空）", text: Binding(
                    get: { item.code },
                    set: { item.code = $0; store.save() }
                ))
                .textFieldStyle(.roundedBorder)
                Spacer()
                Button("完成") { editingItemId = nil }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
            }
        }
        .padding(.vertical, 4)
    }

    // 普通行：图标 + 名/码 + 实色圆行内选色器（点圆直接改色）
    @ViewBuilder
    private func normalRow(_ item: CodeItem) -> some View {
        if editingItemId == item.id {
            editRow(item)
        } else {
            HStack(spacing: 10) {
                Button(action: { editingItemId = item.id }) {
                    HStack(spacing: 10) {
                        CodeItemIconView(icon: item.icon, size: 28)
                        Text(displayText(item)).foregroundColor(.primary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                // 实色圆：行内选色器，点圆直接改色；"其他"固定项不显示
                if !isOtherItem(item), Color(hex: item.icon) != nil {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: item.icon) ?? .red },
                        set: { item.icon = $0.toHex(); store.save() }
                    ))
                    .labelsHidden()
                    .frame(width: 40)
                }
                if !isEditing {
                    Button(role: .destructive, action: { deletingItem = item }) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .foregroundColor(.red)
                    .opacity(isOtherItem(item) ? 0 : 1)
                    .disabled(isOtherItem(item))
                }
            }
        }
    }

    // 编辑模式行：多选框 + 图标 + 名/码
    @ViewBuilder
    private func editingRow(_ item: CodeItem) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                if selectedIds.contains(item.id) { selectedIds.remove(item.id) }
                else { selectedIds.insert(item.id) }
            }) {
                Image(systemName: selectedIds.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundColor(selectedIds.contains(item.id) ? Design.accent : .secondary)
            }
            .buttonStyle(.plain)
            .disabled(isOtherItem(item))
            .opacity(isOtherItem(item) ? 0.3 : 1)
            CodeItemIconView(icon: item.icon, size: 28)
            Text(displayText(item)).foregroundColor(.primary)
            Spacer()
        }
    }

    var body: some View {
        Group {
            if colorLevel != nil {
                List {
                    Section {
                        ForEach(items) { item in
                            if isEditing {
                                editingRow(item)
                            } else {
                                normalRow(item)
                            }
                        }
                        .onMove(perform: moveItem)
                    } header: {
                        Text("颜色列表（\(items.count)）")
                    } footer: {
                        Text("点圆直接改色；点一行改名与代码；拖动排序后，编号生成器与布料表单里的颜色顺序同步变化。“其他”为固定项，不可删除。")
                    }

                    // 添加颜色：内嵌选色器（点“添加”才加入，不会自动乱加）
                    Section {
                        HStack(spacing: 10) {
                            CodeItemIconView(icon: newColor.toHex(), size: 28)
                            ColorPicker("取色", selection: $newColor)
                                .labelsHidden()
                                .frame(width: 44)
                            TextField("名称（可空）", text: $newName)
                                .textFieldStyle(.roundedBorder)
                            TextField("码", text: $newCode)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 64)
                            Button("添加", action: addFromInlinePicker)
                                .buttonStyle(.borderedProminent).tint(Design.accent)
                        }
                    } header: {
                        Text("添加颜色")
                    } footer: {
                        Text("选好颜色、填好名称点“添加”才会加入列表；数量不限。")
                    }
                }
                .navigationTitle("颜色选项")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: {
                            isEditing.toggle()
                            if !isEditing { selectedIds.removeAll() }
                            editingItemId = nil
                        }) {
                            // 图标式编辑键：铅笔 / 对勾
                            Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                                .font(.title3)
                        }
                    }
                    if isEditing {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(selectedIds.count == items.filter({ !isOtherItem($0) }).count ? "取消全选" : "全选") {
                                let deletable = items.filter { !isOtherItem($0) }
                                if selectedIds.count == deletable.count {
                                    selectedIds.removeAll()
                                } else {
                                    selectedIds = Set(deletable.map { $0.id })
                                }
                            }
                        }
                    }
                }
                // 编辑模式底部批量删除条
                .safeAreaInset(edge: .bottom) {
                    if isEditing {
                        HStack {
                            Spacer()
                            Text("已选 \(selectedIds.count) 项")
                                .font(.subheadline).foregroundColor(.secondary)
                            Button("删除选中", role: .destructive, action: deleteSelected)
                                .buttonStyle(.borderedProminent).tint(.red)
                                .disabled(selectedIds.isEmpty)
                            Spacer()
                        }
                        .padding()
                        .background(.thinMaterial)
                    }
                }
                .alert("删除颜色", isPresented: Binding(
                    get: { deletingItem != nil },
                    set: { if !$0 { deletingItem = nil } }
                )) {
                    Button("删除", role: .destructive) {
                        if let item = deletingItem { confirmDelete(item) }
                        deletingItem = nil
                    }
                    Button("取消", role: .cancel) { deletingItem = nil }
                } message: {
                    Text("删除后该颜色不再参与新编号生成与布料表单，历史编号保留、不受影响。")
                }
            } else {
                VStack(spacing: 12) {
                    Text("未找到色系层级").font(.headline)
                    Text("请先在编号体系层级设置里添加一个编号类别为“色系”的层级。")
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding()
                .navigationTitle("颜色选项")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}

