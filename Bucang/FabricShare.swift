import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 布料分享文件（2026-11-01）
// 格式：ZIP（STORE）包含：
//   - fabric.json：Fabric + 该布料的 UsageRecord[] + SaleRecord[]
//   - images/xxx.jpg：布料的所有照片（原文件名保留）
// 导入时生成新 UUID，避免与现有数据冲突。

struct FabricSharePackage: Codable {
    var fabric: Fabric
    var usageRecords: [UsageRecord]
    var saleRecords: [SaleRecord]
    var version: Int = 1
}

enum FabricShare {
    static let jsonName = "fabric.json"
    static let imagesPrefix = "images/"

    /// 导出分享文件，返回 ZIP 文件的临时 URL（调用方负责分享后清理）
    static func exportFile(fabric: Fabric, store: Store) -> URL? {
        let pkg = FabricSharePackage(
            fabric: fabric,
            usageRecords: store.usageRecords(for: fabric.id),
            saleRecords: store.saleRecords(for: fabric.id)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let jsonData = try? encoder.encode(pkg) else { return nil }

        var files: [(path: String, data: Data)] = [(jsonName, jsonData)]
        for name in fabric.imageFileNames {
            if let data = FabricImageStore.data(for: name) {
                files.append((imagesPrefix + name, data))
            }
        }
        let zipData = ZipArchive.write(files)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("布料分享-\(fabric.code.isEmpty ? "未命名" : fabric.code)-\(Int(Date().timeIntervalSince1970)).zip")
        do {
            try zipData.write(to: tmp, options: .atomic)
            return tmp
        } catch {
            return nil
        }
    }

    /// 导入分享文件，返回导入结果说明
    static func importFile(from url: URL, store: Store) -> String {
        guard let data = try? Data(contentsOf: url) else {
            return "读取文件失败"
        }
        let result = ZipArchive.read(data)
        if !result.errors.isEmpty {
            return "压缩包损坏：" + result.errors.joined(separator: "；")
        }
        guard let jsonEntry = result.entries.first(where: { $0.path == jsonName }) else {
            return "不是有效的布料分享文件（缺少 fabric.json）"
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let pkg = try? decoder.decode(FabricSharePackage.self, from: jsonEntry.data) else {
            return "分享文件数据解析失败"
        }

        // 生成新 ID，避免冲突
        let newFabricId = UUID()
        let fabric = pkg.fabric
        let oldId = fabric.id
        fabric.id = newFabricId
        fabric.createdAt = Date()
        fabric.updatedAt = Date()

        // 图片：用新文件名存盘，避免覆盖
        var newImageNames: [String] = []
        for entry in result.entries where entry.path.hasPrefix(imagesPrefix) {
            let ext = (entry.path as NSString).pathExtension
            let newName = UUID().uuidString + (ext.isEmpty ? ".jpg" : ".\(ext)")
            if FabricImageStore.saveData(entry.data, named: newName) {
                newImageNames.append(newName)
            }
        }
        fabric.imageFileNames = newImageNames

        // 关联的子编号、标签等保持原样（ID 引用的是名称/UUID，跨设备可能对不上，保留原值）
        store.fabrics.append(fabric)

        // 导入消耗/出售记录（新 ID，关联到新布料）
        for u in pkg.usageRecords {
            let nu = UsageRecord(
                id: UUID(),
                date: u.date,
                length: u.length,
                note: u.note,
                fabricId: newFabricId,
                workIds: []
            )
            store.usageRecords.append(nu)
        }
        for s in pkg.saleRecords {
            let ns = SaleRecord(
                id: UUID(),
                fabricId: newFabricId,
                length: s.length,
                channel: s.channel,
                merchant: s.merchant,
                price: s.price,
                date: s.date,
                note: s.note,
                imageFileNames: [],
                isPieces: s.isPieces,
                pieces: s.pieces
            )
            store.saleRecords.append(ns)
        }

        store.save()
        _ = oldId // 保留以备将来做关联映射
        return "已导入布料「\(fabric.code.isEmpty ? fabric.displayName : fabric.code)」，含 \(newImageNames.count) 张图片、\(pkg.usageRecords.count) 条消耗记录、\(pkg.saleRecords.count) 条出售记录"
    }
}

// MARK: - 分享 Sheet（UIActivityViewController 包装）

struct ShareSheet: UIViewControllerRepresentable {
    var url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
