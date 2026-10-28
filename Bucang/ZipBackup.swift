import Foundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - 最小 zip 读写：只支持 STORE（method 0，无压缩）
// 原布岛导出就是 STORE（size == compressed size），自家导出也用 STORE，
// 所以不需要任何第三方 zip 库，也不需要改包管理。DEFLATE 等其他
// 压缩方式的条目会被读出时跳过并上报，不会让整次导入崩掉。
// 格式：本地文件头 + 中央目录 + EOCD，CRC 用标准 CRC-32/IEEE（查表法）。
// 文件名统一按 UTF-8 写（flag bit 11），读时也按 UTF-8 解，
// 这样“布仓备份/”“原数据文件/”这类中文目录名在各处都能正确还原。

enum ZipCRC32 {
    private static let table: [UInt32] = {
        var table: [UInt32] = []
        for i in 0..<256 {
            var c = UInt32(i)
            for _ in 0..<8 {
                c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
            }
            table.append(c)
        }
        return table
    }()

    static func crc(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFFFFFF
    }
}

struct ZipEntryData {
    var path: String
    var data: Data
}

struct ZipReadResult {
    var entries: [ZipEntryData] = []
    /// 非 STORE 条目、CRC 失败条目等，被跳过的原因（供导入结果展示）。
    var skipped: [String] = []
    /// 压缩包结构本身的问题（EOCD 找不到、中央目录越界等）。
    var errors: [String] = []
}

enum ZipArchive {
    // MARK: 小端读写（全部带越界检查，绝不越界崩溃）

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16? {
        guard offset >= 0, offset + 1 < data.count else { return nil }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32? {
        guard offset >= 0, offset + 3 < data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private static func appendUInt16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }

    // MARK: 写：STORE

    static func write(_ files: [(path: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        for file in files {
            guard let nameData = file.path.data(using: .utf8) else { continue }
            let crc = ZipCRC32.crc(file.data)
            let localOffset = UInt32(out.count)
            // 本地文件头
            appendUInt32(&out, 0x04034B50)
            appendUInt16(&out, 20) // version needed
            appendUInt16(&out, 0x0800) // flag bit 11: 文件名是 UTF-8
            appendUInt16(&out, 0) // method STORE
            appendUInt16(&out, 0) // mod time
            appendUInt16(&out, 0) // mod date
            appendUInt32(&out, crc)
            appendUInt32(&out, UInt32(file.data.count))
            appendUInt32(&out, UInt32(file.data.count))
            appendUInt16(&out, UInt16(nameData.count))
            appendUInt16(&out, 0) // extra length
            out.append(nameData)
            out.append(file.data)
            // 中央目录条目
            appendUInt32(&central, 0x02014B50)
            appendUInt16(&central, 20) // version made by
            appendUInt16(&central, 20) // version needed
            appendUInt16(&central, 0x0800)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt32(&central, crc)
            appendUInt32(&central, UInt32(file.data.count))
            appendUInt32(&central, UInt32(file.data.count))
            appendUInt16(&central, UInt16(nameData.count))
            appendUInt16(&central, 0)
            appendUInt16(&central, 0)
            appendUInt16(&central, 0) // disk number
            appendUInt16(&central, 0) // internal attributes
            appendUInt32(&central, 0) // external attributes
            appendUInt32(&central, localOffset)
            central.append(nameData)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)
        // EOCD
        appendUInt32(&out, 0x06054B50)
        appendUInt16(&out, 0)
        appendUInt16(&out, 0)
        appendUInt16(&out, UInt16(files.count))
        appendUInt16(&out, UInt16(files.count))
        appendUInt32(&out, UInt32(central.count))
        appendUInt32(&out, cdOffset)
        appendUInt16(&out, 0)
        return out
    }

    // MARK: 读：STORE 提取，非 STORE 跳过上报

    static func read(_ data: Data) -> ZipReadResult {
        var result = ZipReadResult()
        // 找 EOCD：从尾部往前扫（注释最多 64KB，扫最后 64KB + 22 字节）。
        var eocdOffset: Int?
        var cdOffset = 0
        var cdCount = 0
        let scanStart = max(0, data.count - 65557)
        if data.count >= 22 {
            var i = data.count - 22
            while i >= scanStart {
                if readUInt32(data, i) == 0x06054B50,
                   let count = readUInt16(data, i + 10),
                   let size = readUInt32(data, i + 12),
                   let offset = readUInt32(data, i + 16),
                   Int(offset) + Int(size) <= data.count {
                    eocdOffset = i
                    cdOffset = Int(offset)
                    cdCount = Int(count)
                    break
                }
                if i == 0 { break }
                i -= 1
            }
        }
        guard eocdOffset != nil else {
            result.errors.append("压缩包结构不完整（找不到结束记录），无法读取。")
            return result
        }
        var offset = cdOffset
        for _ in 0..<cdCount {
            guard readUInt32(data, offset) == 0x02014B50,
                  let method = readUInt16(data, offset + 10),
                  let crc = readUInt32(data, offset + 16),
                  let compSize = readUInt32(data, offset + 20),
                  let nameLen = readUInt16(data, offset + 28),
                  let extraLen = readUInt16(data, offset + 30),
                  let commentLen = readUInt16(data, offset + 32),
                  let localOffset = readUInt32(data, offset + 42) else {
                result.errors.append("中央目录损坏，剩余条目无法读取。")
                break
            }
            let nameStart = offset + 46
            let nameEnd = nameStart + Int(nameLen)
            guard nameEnd <= data.count else {
                result.errors.append("中央目录文件名越界，剩余条目无法读取。")
                break
            }
            let nameData = data[nameStart..<nameEnd]
            let name = String(data: nameData, encoding: .utf8) ?? String(data: nameData, encoding: .isoLatin1) ?? ""
            offset = nameEnd + Int(extraLen) + Int(commentLen)
            if name.isEmpty || name.hasSuffix("/") { continue } // 目录条目
            if method != 0 {
                result.skipped.append("\(name)（压缩方式 \(method)，本 App 只读无压缩条目，跳过）")
                continue
            }
            // 本地文件头：找数据起点
            guard readUInt32(data, Int(localOffset)) == 0x04034B50,
                  let localNameLen = readUInt16(data, Int(localOffset) + 26),
                  let localExtraLen = readUInt16(data, Int(localOffset) + 28) else {
                result.skipped.append("\(name)（本地文件头损坏，跳过）")
                continue
            }
            let dataStart = Int(localOffset) + 30 + Int(localNameLen) + Int(localExtraLen)
            let dataEnd = dataStart + Int(compSize)
            guard dataStart >= 0, dataEnd <= data.count else {
                result.skipped.append("\(name)（数据越界，跳过）")
                continue
            }
            let fileData = data[dataStart..<dataEnd]
            if ZipCRC32.crc(fileData) != crc {
                result.skipped.append("\(name)（CRC 校验失败，跳过）")
                continue
            }
            result.entries.append(ZipEntryData(path: name, data: Data(fileData)))
        }
        return result
    }
}

// MARK: - 导入结果

struct ZipImportSummary {
    var usedJSON = false
    var restoredFabrics = 0
    var restoredTags = 0
    var restoredMaterials = 0
    var restoredChannels = 0
    var restoredUsage = 0
    var restoredWorks = 0
    var restoredPatterns = 0
    var restoredItems = 0
    var csvSummary: ImportSummary?
    var imagesCopied = 0
    var orphanedImages: [String] = []
    var skippedCompressed: [String] = []
    var errors: [String] = []

    var text: String {
        var lines: [String] = []
        if usedJSON {
            lines.append("已从备份 JSON 恢复（完整数据，覆盖本机）：")
            lines.append("布料 \(restoredFabrics)，标签 \(restoredTags)，材质 \(restoredMaterials)，渠道 \(restoredChannels)，使用记录 \(restoredUsage)，作品 \(restoredWorks)，纸样 \(restoredPatterns)，物品 \(restoredItems)")
        } else if let csv = csvSummary {
            lines.append("已按 CSV 导入（按原 UUID 更新，不重复建）：")
            lines.append("标签：新增 \(csv.tagsAdded)，更新 \(csv.tagsUpdated)")
            lines.append("材质：新增 \(csv.materialsAdded)，更新 \(csv.materialsUpdated)")
            lines.append("渠道：新增 \(csv.channelsAdded)，更新 \(csv.channelsUpdated)")
            lines.append("布料：新增 \(csv.fabricsAdded)，更新 \(csv.fabricsUpdated)")
            lines.append("使用记录：新增 \(csv.usageAdded)，更新 \(csv.usageUpdated)")
            lines.append("跳过：\(csv.skipped) 条")
            if !csv.errors.isEmpty {
                lines.append("问题（只列前 10 条）：")
                lines.append(contentsOf: csv.errors.prefix(10))
            }
        }
        lines.append("图片：已复制 \(imagesCopied) 张")
        if !orphanedImages.isEmpty {
            lines.append("未匹配布料的图片（只列前 10 个）：\(orphanedImages.prefix(10).joined(separator: "、"))")
        }
        if !skippedCompressed.isEmpty {
            lines.append("跳过的压缩条目（只列前 10 个）：")
            lines.append(contentsOf: skippedCompressed.prefix(10))
        }
        if !errors.isEmpty {
            lines.append("问题：")
            lines.append(contentsOf: errors.prefix(10))
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - 压缩包备份：导出 / 导入

@MainActor
enum ZipBackup {
    static let rootFolder = "布仓备份"

    static func basename(_ path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        return parts.last ?? path
    }

    static func isImageEntry(_ path: String) -> Bool {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return false }
        return parts[parts.count - 2] == "images"
    }

    static func defaultExportFileName() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return "布仓备份-\(f.string(from: Date())).zip"
    }

    /// 导出：CSV（复用现有导出代码）+ bucang-store.json 全量 + 全部布料图片。
    static func buildExportData(store: Store) -> Data? {
        var files: [(path: String, data: Data)] = []
        // CSV：直接读现有导出写出的临时文件，保证列格式和单 CSV 导出完全一致。
        let csvURLs = CSVExporter.exportFiles(store: store)
        for url in csvURLs {
            guard let data = try? Data(contentsOf: url) else { continue }
            files.append((path: "\(rootFolder)/\(url.lastPathComponent)", data: data))
        }
        // JSON 全量：直接按内存数据编码，和 Store.save() 写出的格式一致。
        let storeData = StoreData(
            tags: store.tags, materials: store.materials, channels: store.channels,
            fabrics: store.fabrics, usageRecords: store.usageRecords,
            works: store.works, patterns: store.patterns, items: store.items,
            saleRecords: store.saleRecords, otherItems: store.otherItems, wishlistItems: store.wishlistItems,
            materialOptions: store.materialOptions, otherCategories: store.otherCategories,
            lengthUnit: store.lengthUnit, hideAmounts: store.hideAmounts, codePrefix: store.codePrefix,
            channelOptions: store.channelOptions, patternOptions: store.patternOptions,
            visibleTabs: store.visibleTabs, themeName: store.themeName
        )
        if let json = try? JSONEncoder().encode(storeData) {
            files.append((path: "\(rootFolder)/bucang-store.json", data: json))
        }
        // 图片：按布料 + 出售记录去重文件名，只导本地确实存在的文件。
        var seen: Set<String> = []
        for name in store.fabrics.flatMap({ $0.imageFileNames }) + store.saleRecords.flatMap({ $0.imageFileNames }) {
            if seen.contains(name) { continue }
            seen.insert(name)
            if let data = FabricImageStore.data(for: name) {
                files.append((path: "\(rootFolder)/images/\(name)", data: data))
            }
        }
        // 视频：布料视频同样进包，放在 videos/，恢复时按 basename 写回 bucang-videos/。
        if let videoDir = FabricVideoStore.directoryURL() {
            for fabric in store.fabrics {
                for name in fabric.videoFileNames {
                    if let data = try? Data(contentsOf: videoDir.appendingPathComponent(name)) {
                        files.append((path: "\(rootFolder)/videos/\(name)", data: data))
                    }
                }
            }
        }
        return ZipArchive.write(files)
    }

    /// 导入：按 basename 匹配，不依赖根文件夹名，所以原“原数据文件/”包、
    /// 自家“布仓备份/”包、以及文件直接在根目录的包都能读。
    static func importZip(_ data: Data, store: Store) -> ZipImportSummary {
        var summary = ZipImportSummary()
        let read = ZipArchive.read(data)
        summary.skippedCompressed = read.skipped
        summary.errors.append(contentsOf: read.errors)
        if read.entries.isEmpty {
            if summary.errors.isEmpty {
                summary.errors.append("压缩包里没有可读的文件。")
            }
            return summary
        }
        // 找 JSON（basename 匹配）
        let jsonEntry = read.entries.first { basename($0.path).lowercased() == "bucang-store.json" }
        if let jsonEntry,
           let decoded = try? JSONDecoder().decode(StoreData.self, from: jsonEntry.data) {
            // 校验通过后才替换本机数据；解码失败绝不清空本机（见下文 CSV 回退）。
            store.apply(decoded)
            summary.usedJSON = true
            summary.restoredFabrics = decoded.fabrics.count
            summary.restoredTags = decoded.tags.count
            summary.restoredMaterials = decoded.materials.count
            summary.restoredChannels = decoded.channels.count
            summary.restoredUsage = decoded.usageRecords.count
            summary.restoredWorks = decoded.works.count
            summary.restoredPatterns = decoded.patterns.count
            summary.restoredItems = decoded.items.count
            // 图片：全部 images/ 条目都复制回本地（按 basename 覆盖同名），
            // 再报告其中未被任何布料引用的（已复制，但可能是旧图）。
            let referenced = Set(decoded.fabrics.flatMap { $0.imageFileNames } + decoded.saleRecords.flatMap { $0.imageFileNames })
            for entry in read.entries where isImageEntry(entry.path) {
                let name = basename(entry.path)
                if FabricImageStore.saveData(entry.data, named: name) {
                    summary.imagesCopied += 1
                    if !referenced.contains(name) {
                        summary.orphanedImages.append(name)
                    }
                }
            }
            // 视频：videos/ 条目写回 bucang-videos/（JSON 里 videoFileNames 已恢复，文件名对应上即可播放）。
            if let videoDir = FabricVideoStore.directoryURL() {
                try? FileManager.default.createDirectory(at: videoDir, withIntermediateDirectories: true)
                for entry in read.entries where entry.path.lowercased().contains("/videos/") {
                    let name = basename(entry.path)
                    try? entry.data.write(to: videoDir.appendingPathComponent(name), options: .atomic)
                }
            }
            return summary
        }
        if jsonEntry != nil {
            summary.errors.append("备份 JSON 解码失败，已改按 CSV 导入，本机原数据未被清空。")
        }
        // CSV 回退：把找到的 CSV 写到临时目录，复用现有 CSV 导入逻辑（UUID 更新）。
        var csvTexts: [String: String] = [:]
        for entry in read.entries {
            let base = basename(entry.path).lowercased()
            if base.hasSuffix(".csv"), let text = String(data: entry.data, encoding: .utf8) {
                csvTexts[base] = text
            }
        }
        let csvNames = ["tags.csv", "materials.csv", "channels.csv", "fabrics.csv", "usage_records.csv", "fabric_images.csv"]
        let hasAnyCSV = csvNames.contains { csvTexts[$0] != nil }
        if !hasAnyCSV {
            summary.errors.append("压缩包里没有找到 bucang-store.json，也没有找到任何 CSV，无法导入。")
            return summary
        }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("BucangZipImport-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (base, text) in csvTexts {
            let url = dir.appendingPathComponent(base)
            try? text.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        let csvSummary = CSVImporter.importFiles(urls, store: store)
        summary.csvSummary = csvSummary
        try? FileManager.default.removeItem(at: dir)
        // 图片链接：按 fabric_images.csv 的 fabricId + fileName + isMain 链接，
        // 再把已链接的图片文件复制回本地；未链接的图片文件不复制，只上报。
        var linkedNames: Set<String> = []
        if let imagesText = csvTexts["fabric_images.csv"] {
            for row in CSVParser.rowsByHeader(imagesText) {
                guard let fabricId = CSVValues.uuid(row["fabricId"] ?? ""),
                      let fabric = store.fabric(for: fabricId) else {
                    let fileName = basename(row["fileName"] ?? "")
                    if !fileName.isEmpty {
                        summary.orphanedImages.append(fileName)
                    }
                    continue
                }
                let fileName = basename(row["fileName"] ?? "")
                if fileName.isEmpty { continue }
                if fabric.imageFileNames.contains(fileName) {
                    linkedNames.insert(fileName)
                    continue
                }
                if CSVValues.bool(row["isMain"] ?? "") {
                    fabric.imageFileNames.insert(fileName, at: 0)
                } else {
                    fabric.imageFileNames.append(fileName)
                }
                linkedNames.insert(fileName)
            }
            store.save()
        }
        for entry in read.entries where isImageEntry(entry.path) {
            let name = basename(entry.path)
            if linkedNames.contains(name) {
                if FabricImageStore.saveData(entry.data, named: name) {
                    summary.imagesCopied += 1
                }
            } else if !summary.orphanedImages.contains(name) {
                summary.orphanedImages.append(name)
            }
        }
        return summary
    }
}

// MARK: - fileExporter 用的文档（UTType.zip，iOS 15+ API，iOS 16 安全）

struct ZipBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [UTType.zip] }
    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
