import SwiftUI

// iCloud 备份（2026-11-01）：以备不时之需。TrollStore 应用可能拿不到 iCloud 容器授权，
// 届时会明确提示；能拿到授权的设备上可正常备份/恢复。
struct iCloudBackupView: View {
    @EnvironmentObject private var store: Store
    @State private var statusMessage: String?
    @State private var isBusy = false
    @State private var iCloudAvailable: Bool?
    
    private var fileName: String { "bucang-backup.json" }
    
    private func checkAvailability() {
        // ubiquityIdentityToken 非空表示设备已登录 iCloud
        iCloudAvailable = FileManager.default.ubiquityIdentityToken != nil
    }
    
    private func containerURL() -> URL? {
        // 需要 com.apple.developer.ubiquity-container-identifiers 授权；
        // TrollStore 包若无授权会返回 nil。
        FileManager.default.url(forUbiquityContainerIdentifier: nil)?
            .appendingPathComponent("Documents", isDirectory: true)
    }
    
    private func backup() async {
        guard let dir = containerURL() else {
            statusMessage = "拿不到 iCloud 容器：此安装包缺少 iCloud 授权（TrollStore 常见），请继续用 WebDAV 备份。"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = StoreData(
                tags: store.tags, materials: store.materials, channels: store.channels,
                fabrics: store.fabrics, usageRecords: store.usageRecords,
                works: store.works, patterns: store.patterns, items: store.items,
                saleRecords: store.saleRecords, otherItems: store.otherItems, wishlistItems: store.wishlistItems,
                brainstorms: store.brainstorms,
                materialOptions: store.materialOptions, otherCategories: store.otherCategories,
                lengthUnit: store.lengthUnit, hideAmounts: store.hideAmounts, codePrefix: store.codePrefix,
                channelOptions: store.channelOptions, patternOptions: store.patternOptions, codeLevels: store.codeLevels,
                visibleTabs: store.visibleTabs, themeName: store.themeName
            )
            let json = try JSONEncoder().encode(data)
            let dest = dir.appendingPathComponent(fileName)
            try json.write(to: dest, options: .atomic)
            statusMessage = "已备份到 iCloud Drive：\(dest.lastPathComponent)"
        } catch {
            statusMessage = "备份失败：\(error.localizedDescription)"
        }
    }
    
    private func restore() async {
        guard let dir = containerURL() else {
            statusMessage = "拿不到 iCloud 容器：此安装包缺少 iCloud 授权（TrollStore 常见），请继续用 WebDAV 恢复。"
            return
        }
        isBusy = true
        defer { isBusy = false }
        let src = dir.appendingPathComponent(fileName)
        do {
            // 确保 iCloud 文件已下载到本地
            if FileManager.default.isUbiquitousItem(at: src) {
                try FileManager.default.startDownloadingUbiquitousItem(at: src)
            }
            let json = try Data(contentsOf: src)
            if let decoded = try? JSONDecoder().decode(StoreData.self, from: json) {
                store.apply(decoded)
                statusMessage = "已从 iCloud 恢复：\(decoded.fabrics.count) 块布料"
            } else {
                statusMessage = "恢复失败：备份文件格式不对"
            }
        } catch {
            statusMessage = "恢复失败：\(error.localizedDescription)（若文件尚未同步完成，请稍后再试）"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "iCloud 备份", subtitle: "备用选项；TrollStore 包可能无 iCloud 授权")
            if let available = iCloudAvailable {
                Text(available ? "设备已登录 iCloud" : "设备未登录 iCloud，请先在系统设置里登录")
                    .font(.caption).foregroundColor(available ? .green : .orange)
            } else {
                Text("正在检测…").font(.caption).foregroundColor(.secondary)
            }
            HStack(spacing: 12) {
                Button("备份到 iCloud") { Task { await backup() } }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                    .disabled(isBusy)
                Button("从 iCloud 恢复") { Task { await restore() } }
                    .buttonStyle(.bordered).tint(Design.accent)
                    .disabled(isBusy)
            }
            if isBusy { ProgressView().progressViewStyle(.circular) }
            if let msg = statusMessage {
                Text(msg).font(.caption).foregroundColor(.secondary)
            }
            Text("iCloud 免费 5GB；备份文件为 bucang-backup.json，图片不进 iCloud（图片请走 WebDAV 或本地压缩包）。")
                .font(.caption).foregroundColor(.secondary)
        }
        .onAppear { checkAvailability() }
    }
}
