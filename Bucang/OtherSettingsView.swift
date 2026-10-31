import SwiftUI
import UniformTypeIdentifiers

// 其他设置（2026-10-31）：数据管理 / 本地压缩包 / 备份 / 关于的二级菜单
struct OtherSettingsView: View {
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
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
        .navigationTitle("其他设置")
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
                } else if let url = urls.first, let data = try? Data(contentsOf: url) {
                    importSummary = ZipBackup.importZip(data, store: store).text
                }
            case .failure(let error):
                importSummary = "导入失败：\(error.localizedDescription)"
            }
            showingSummary = true
            refreshLocalZips()
        }
        .alert("导入结果", isPresented: $showingSummary) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(importSummary ?? "")
        }
        .sheet(isPresented: $showingExporter) {
            if !exportURLs.isEmpty {
                DocumentExporter(urls: exportURLs)
            }
        }
        .sheet(isPresented: $showingZipExporter) {
            if let doc = zipDocument {
                DocumentExporter(urls: [doc])
            }
        }
        .alert("清空全部本地数据", isPresented: $showingClearConfirm) {
            Button("清空", role: .destructive) {
                store.clearAllData()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除全部本地数据，无法恢复。请先备份。")
        }
    }
}
