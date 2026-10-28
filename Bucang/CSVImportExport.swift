import Foundation

// MARK: - CSV 解析：处理引号、逗号、换行和双引号转义

enum CSVParser {
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    field.append(ch)
                    i += 1
                    continue
                }
            } else {
                if ch == "\"" {
                    inQuotes = true
                    i += 1
                    continue
                } else if ch == "," {
                    row.append(field)
                    field = ""
                    i += 1
                    continue
                } else if ch == "\n" {
                    row.append(field)
                    field = ""
                    rows.append(row)
                    row = []
                    i += 1
                    continue
                } else if ch == "\r" {
                    i += 1
                    continue
                } else {
                    field.append(ch)
                    i += 1
                    continue
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !$0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
    }

    static func rowsByHeader(_ text: String) -> [[String: String]] {
        let rows = parse(text)
        guard let header = rows.first else { return [] }
        return rows.dropFirst().map { values in
            var dict: [String: String] = [:]
            for (index, key) in header.enumerated() {
                dict[key] = index < values.count ? values[index] : ""
            }
            return dict
        }
    }

    static func escape(_ value: String) -> String {
        if value.contains(",") || value.contains("\"") || value.contains("\n") {
            return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        return value
    }
}

// MARK: - 日期 / 数字小工具

enum CSVValues {
    static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static let dateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    static func date(_ s: String) -> Date {
        let t = s.trimmingCharacters(in: .whitespaces)
        if let d = dateFormatter.date(from: t) { return d }
        if let d = dateTimeFormatter.date(from: t) { return d }
        return Date()
    }

    static func dateString(_ d: Date) -> String {
        dateFormatter.string(from: d)
    }
    static func dateString(_ d: Date?) -> String {
        guard let d else { return "" }
        return dateFormatter.string(from: d)
    }
    // 购买日期可选：空串/无法解析 = nil，绝不默认今天。
    static func dateOptional(_ s: String) -> Date? {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard !t.isEmpty else { return nil }
        if let d = dateFormatter.date(from: t) { return d }
        if let d = dateTimeFormatter.date(from: t) { return d }
        return nil
    }

    static func double(_ s: String) -> Double {
        Double(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    static func int(_ s: String) -> Int {
        Int(s.trimmingCharacters(in: .whitespaces)) ?? 0
    }

    static func bool(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespaces).lowercased()
        return t == "true" || t == "1" || t == "是"
    }

    static func uuid(_ s: String) -> UUID? {
        UUID(uuidString: s.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - 导入报告

struct ImportSummary {
    var tagsAdded = 0
    var tagsUpdated = 0
    var materialsAdded = 0
    var materialsUpdated = 0
    var channelsAdded = 0
    var channelsUpdated = 0
    var fabricsAdded = 0
    var fabricsUpdated = 0
    var usageAdded = 0
    var usageUpdated = 0
    var skipped = 0
    var errors: [String] = []

    var text: String {
        var lines: [String] = []
        lines.append("标签：新增 \(tagsAdded)，更新 \(tagsUpdated)")
        lines.append("材质：新增 \(materialsAdded)，更新 \(materialsUpdated)")
        lines.append("渠道：新增 \(channelsAdded)，更新 \(channelsUpdated)")
        lines.append("布料：新增 \(fabricsAdded)，更新 \(fabricsUpdated)")
        lines.append("使用记录：新增 \(usageAdded)，更新 \(usageUpdated)")
        lines.append("跳过：\(skipped) 条")
        if !errors.isEmpty {
            lines.append("问题（只列前 10 条）：")
            lines.append(contentsOf: errors.prefix(10))
        }
        lines.append("图片文件已按你的要求忽略，不导入。")
        return lines.joined(separator: "\n")
    }
}

// MARK: - 导入：按原 UUID 匹配，重复导入更新不重复建

@MainActor
enum CSVImporter {
    /// 字典顺序列别名：原导出用 "order"，其他来源可能用 "sortOrder"，两者都接受，"order" 优先。
    static func orderValue(_ row: [String: String]) -> Int {
        let order = (row["order"] ?? "").trimmingCharacters(in: .whitespaces)
        if !order.isEmpty { return CSVValues.int(order) }
        return CSVValues.int(row["sortOrder"] ?? "")
    }

    static func importFiles(_ urls: [URL], store: Store) -> ImportSummary {
        var summary = ImportSummary()
        var texts: [String: String] = [:]
        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url),
                  let text = String(data: data, encoding: .utf8) else {
                summary.errors.append("读不到文件：\(url.lastPathComponent)")
                summary.skipped += 1
                continue
            }
            texts[url.lastPathComponent.lowercased()] = text
        }

        // 现有数据按 id 建索引
        var tagByID: [UUID: Tag] = [:]
        for t in store.tags { tagByID[t.id] = t }
        var materialByID: [UUID: Material] = [:]
        for m in store.materials { materialByID[m.id] = m }
        var channelByID: [UUID: Channel] = [:]
        for c in store.channels { channelByID[c.id] = c }
        var fabricByID: [UUID: Fabric] = [:]
        for f in store.fabrics { fabricByID[f.id] = f }
        var usageByID: [UUID: UsageRecord] = [:]
        for u in store.usageRecords { usageByID[u.id] = u }

        // 字典先导入
        if let text = texts["tags.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                guard let id = CSVValues.uuid(row["id"] ?? "") else { summary.skipped += 1; continue }
                let name = (row["name"] ?? "").trimmingCharacters(in: .whitespaces)
                if name.isEmpty { summary.skipped += 1; continue }
                if let existing = tagByID[id] {
                    existing.name = name
                    existing.sortOrder = orderValue(row)
                    summary.tagsUpdated += 1
                } else {
                    let tag = Tag(id: id, name: name, sortOrder: orderValue(row))
                    store.tags.append(tag)
                    tagByID[id] = tag
                    summary.tagsAdded += 1
                }
            }
        }
        if let text = texts["materials.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                guard let id = CSVValues.uuid(row["id"] ?? "") else { summary.skipped += 1; continue }
                let name = (row["name"] ?? "").trimmingCharacters(in: .whitespaces)
                if name.isEmpty { summary.skipped += 1; continue }
                if let existing = materialByID[id] {
                    existing.name = name
                    existing.sortOrder = orderValue(row)
                    summary.materialsUpdated += 1
                } else {
                    let m = Material(id: id, name: name, sortOrder: orderValue(row))
                    store.materials.append(m)
                    materialByID[id] = m
                    summary.materialsAdded += 1
                }
            }
        }
        if let text = texts["channels.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                guard let id = CSVValues.uuid(row["id"] ?? "") else { summary.skipped += 1; continue }
                let name = (row["name"] ?? "").trimmingCharacters(in: .whitespaces)
                if name.isEmpty { summary.skipped += 1; continue }
                if let existing = channelByID[id] {
                    existing.name = name
                    existing.sortOrder = orderValue(row)
                    summary.channelsUpdated += 1
                } else {
                    let c = Channel(id: id, name: name, sortOrder: orderValue(row))
                    store.channels.append(c)
                    channelByID[id] = c
                    summary.channelsAdded += 1
                }
            }
        }

        // 布料
        if let text = texts["fabrics.csv"] ?? texts["fabrics_template.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                // 模板行 id 留空时自动生成新 UUID（旧导出 id 必填，仍按原 UUID 匹配）。
                let id = CSVValues.uuid(row["id"] ?? "") ?? UUID()
                let materialId: UUID? = (row["materialId"] ?? "").isEmpty ? nil : CSVValues.uuid(row["materialId"] ?? "")
                let channelId: UUID? = (row["purchaseChannelId"] ?? "").isEmpty ? nil : CSVValues.uuid(row["purchaseChannelId"] ?? "")
                if let mid = row["materialId"], !mid.isEmpty, materialId == nil || materialByID[materialId!] == nil {
                    summary.errors.append("布料 \(id) 的材质引用不到，已跳过")
                    summary.skipped += 1
                    continue
                }
                if let cid = row["purchaseChannelId"], !cid.isEmpty, channelId == nil || channelByID[channelId!] == nil {
                    summary.errors.append("布料 \(id) 的渠道引用不到，已跳过")
                    summary.skipped += 1
                    continue
                }
                let tagIDs = (row["tagIds"] ?? "")
                    .replacingOccurrences(of: ";", with: ",")
                    .split(separator: ",")
                    .compactMap { CSVValues.uuid(String($0)) }
                    .filter { tagByID[$0] != nil }
                // V3 新列（模板导入）：code / material / composition / color /
                // widthCm / usageNotes / channel（字符串渠道，优先于 ID）；
                // 旧列仍按原口径读，不编造缺失值。
                let v3Code = (row["code"] ?? "").trimmingCharacters(in: .whitespaces)
                let v3Material = (row["material"] ?? "").trimmingCharacters(in: .whitespaces)
                let v3Composition = (row["composition"] ?? "").trimmingCharacters(in: .whitespaces)
                let v3Color = (row["color"] ?? "").trimmingCharacters(in: .whitespaces)
                let v3UsageNotes = (row["usageNotes"] ?? "").trimmingCharacters(in: .whitespaces)
                let v3Channel = (row["channel"] ?? "").trimmingCharacters(in: .whitespaces)
                let widthCmText = (row["widthCm"] ?? "").trimmingCharacters(in: .whitespaces)
                let widthValue: Double = !widthCmText.isEmpty ? CSVValues.double(widthCmText) / 100 : CSVValues.double(row["width"] ?? "")
                // tagNames：按名称匹配已有标签，缺失则新建（模板批量导入用）。
                var tagIDsAll = tagIDs
                if let tagNamesRaw = row["tagNames"], !tagNamesRaw.trimmingCharacters(in: .whitespaces).isEmpty {
                    for part in tagNamesRaw.split(separator: ";").map({ String($0).trimmingCharacters(in: .whitespaces) }) where !part.isEmpty {
                        if let existingTag = store.tags.first(where: { $0.name == part }) {
                            if !tagIDsAll.contains(existingTag.id) { tagIDsAll.append(existingTag.id) }
                        } else {
                            let newTag = Tag(name: part, sortOrder: store.tags.count)
                            store.tags.append(newTag); tagByID[newTag.id] = newTag; tagIDsAll.append(newTag.id)
                        }
                    }
                }
                if let existing = fabricByID[id] {
                    existing.name = row["name"] ?? ""
                    existing.length = CSVValues.double(row["length"] ?? "")
                    existing.width = widthValue
                    existing.purchasePrice = CSVValues.double(row["purchasePrice"] ?? "")
                    existing.pricePerMeter = CSVValues.double(row["purchasePricePerMeter"] ?? "")
                    existing.purchaseDate = CSVValues.dateOptional(row["purchaseDate"] ?? "")
                    existing.usedLength = CSVValues.double(row["usedLength"] ?? "")
                    existing.isFavorite = CSVValues.bool(row["isFavorite"] ?? "")
                    existing.status = CSVValues.int(row["status"] ?? "")
                    existing.note = row["note"] ?? ""
                    existing.materialId = materialId
                    existing.channelId = channelId
                    existing.tagIds = tagIDsAll
                    existing.updatedAt = Date()
                    if !v3Code.isEmpty { existing.code = v3Code }
                    if !v3Material.isEmpty { existing.materialName = v3Material }
                    if !v3Composition.isEmpty { existing.composition = v3Composition }
                    if !v3Color.isEmpty { existing.colorName = v3Color }
                    if !v3UsageNotes.isEmpty { existing.usageNotes = v3UsageNotes }
                    if !v3Channel.isEmpty { existing.channelName = v3Channel }
                    existing.hasPurchaseLength = existing.length > 0
                    existing.hasTotalPrice = existing.purchasePrice > 0
                    summary.fabricsUpdated += 1
                } else {
                    let fabric = Fabric(
                        id: id,
                        name: row["name"] ?? "",
                        length: CSVValues.double(row["length"] ?? ""),
                        width: widthValue,
                        purchasePrice: CSVValues.double(row["purchasePrice"] ?? ""),
                        pricePerMeter: CSVValues.double(row["purchasePricePerMeter"] ?? ""),
                        purchaseDate: CSVValues.dateOptional(row["purchaseDate"] ?? ""),
                        usedLength: CSVValues.double(row["usedLength"] ?? ""),
                        isFavorite: CSVValues.bool(row["isFavorite"] ?? ""),
                        status: CSVValues.int(row["status"] ?? ""),
                        note: row["note"] ?? "",
                        createdAt: CSVValues.date(row["createdAt"] ?? ""),
                        updatedAt: CSVValues.date(row["modifiedAt"] ?? ""),
                        materialId: materialId,
                        channelId: channelId,
                        tagIds: tagIDsAll,
                        code: v3Code, materialName: v3Material, composition: v3Composition,
                        colorName: v3Color, usageNotes: v3UsageNotes, channelName: v3Channel
                    )
                    fabric.hasPurchaseLength = fabric.length > 0
                    fabric.hasTotalPrice = fabric.purchasePrice > 0
                    store.fabrics.append(fabric)
                    fabricByID[id] = fabric
                    summary.fabricsAdded += 1
                }
            }
        }

        // 使用记录（fabric_images.csv 按要求忽略，不读）
        if let text = texts["usage_records.csv"] ?? texts["usage_records_template.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                guard let id = CSVValues.uuid(row["id"] ?? ""),
                      let fabricID = CSVValues.uuid(row["fabricId"] ?? ""),
                      fabricByID[fabricID] != nil else {
                    summary.skipped += 1
                    continue
                }
                let length = CSVValues.double(row["length"] ?? "")
                let usage = CSVValues.double(row["usage"] ?? "")
                let amount = length != 0 ? length : usage
                if let existing = usageByID[id] {
                    existing.date = CSVValues.date(row["date"] ?? "")
                    existing.length = amount
                    existing.fabricId = fabricID
                    summary.usageUpdated += 1
                } else {
                    let record = UsageRecord(id: id, date: CSVValues.date(row["date"] ?? ""), length: amount, fabricId: fabricID)
                    store.usageRecords.append(record)
                    usageByID[id] = record
                    summary.usageAdded += 1
                }
            }
        }

        // 出售记录（V3 新增文件 sale_records.csv；旧包没有此文件时跳过）
        if let text = texts["sale_records.csv"] ?? texts["sale_records_template.csv"] {
            for row in CSVParser.rowsByHeader(text) {
                guard let id = CSVValues.uuid(row["id"] ?? ""),
                      let fabricID = CSVValues.uuid(row["fabricId"] ?? ""),
                      fabricByID[fabricID] != nil else {
                    summary.skipped += 1; continue
                }
                if let existing = store.saleRecords.first(where: { $0.id == id }) {
                    existing.length = CSVValues.double(row["length"] ?? "")
                    existing.channel = row["channel"] ?? ""
                    existing.price = CSVValues.double(row["price"] ?? "")
                    existing.date = CSVValues.date(row["date"] ?? "")
                } else {
                    store.saleRecords.append(SaleRecord(
                        id: id, fabricId: fabricID,
                        length: CSVValues.double(row["length"] ?? ""),
                        channel: row["channel"] ?? "",
                        price: CSVValues.double(row["price"] ?? ""),
                        date: CSVValues.date(row["date"] ?? "")
                    ))
                }
            }
        }

        store.normalizeLegacyFabrics()
        store.save()
        return summary
    }
}

// MARK: - 导出：按原 CSV 列格式

@MainActor
enum CSVExporter {
    static func exportFiles(store: Store) -> [URL] {
        let tags = store.tags.sorted { $0.sortOrder < $1.sortOrder }
        let materials = store.materials.sorted { $0.sortOrder < $1.sortOrder }
        let channels = store.channels.sorted { $0.sortOrder < $1.sortOrder }
        let fabrics = store.fabrics.sorted { $0.createdAt < $1.createdAt }
        let usage = store.usageRecords.sorted { $0.date < $1.date }

        var files: [(String, String)] = []

        var tagsCSV = "id,name,order\n"
        for t in tags { tagsCSV += [t.id.uuidString, t.name, String(t.sortOrder)].map(CSVParser.escape).joined(separator: ",") + "\n" }
        files.append(("tags.csv", tagsCSV))

        var materialsCSV = "id,name,order\n"
        for m in materials { materialsCSV += [m.id.uuidString, m.name, String(m.sortOrder)].map(CSVParser.escape).joined(separator: ",") + "\n" }
        files.append(("materials.csv", materialsCSV))

        var channelsCSV = "id,name,order\n"
        for c in channels { channelsCSV += [c.id.uuidString, c.name, String(c.sortOrder)].map(CSVParser.escape).joined(separator: ",") + "\n" }
        files.append(("channels.csv", channelsCSV))

        var fabricsCSV = "id,name,length,width,purchasePrice,purchasePricePerMeter,purchaseDate,usedLength,isFavorite,createdAt,modifiedAt,status,note,materialId,purchaseChannelId,tagIds\n"
        for f in fabrics {
            let values = [
                f.id.uuidString, f.name, String(f.length), String(f.width),
                String(f.purchasePrice), String(f.pricePerMeter),
                CSVValues.dateString(f.purchaseDate), String(f.usedLength),
                f.isFavorite ? "true" : "false",
                CSVValues.dateString(f.createdAt), CSVValues.dateString(f.updatedAt),
                String(f.status), f.note,
                f.materialId?.uuidString ?? "", f.channelId?.uuidString ?? "",
                f.tagIds.map { $0.uuidString }.joined(separator: ";")
            ]
            fabricsCSV += values.map(CSVParser.escape).joined(separator: ",") + "\n"
        }
        files.append(("fabrics.csv", fabricsCSV))

        var usageCSV = "id,fabricId,fworkId,length,date,usage\n"
        for u in usage {
            let values = [u.id.uuidString, u.fabricId.uuidString, "", String(u.length), CSVValues.dateString(u.date), String(u.length)]
            usageCSV += values.map(CSVParser.escape).joined(separator: ",") + "\n"
        }
        files.append(("usage_records.csv", usageCSV))

        // 图片：只导出文件名（不导图片字节，和原来一样）。
        // id 是导出时生成的，模型里只存文件名，不存图片记录 id；
        // 第一张图记为 isMain，createdAt 用布料创建时间。
        var imagesCSV = "id,fabricId,fworkId,fPatternId,itemId,isMain,createdAt,fileName\n"
        for f in fabrics {
            for (index, fileName) in f.imageFileNames.enumerated() {
                let values = [
                    UUID().uuidString, f.id.uuidString, "", "", "",
                    index == 0 ? "true" : "false",
                    CSVValues.dateString(f.createdAt), fileName
                ]
                imagesCSV += values.map(CSVParser.escape).joined(separator: ",") + "\n"
            }
        }
        files.append(("fabric_images.csv", imagesCSV))

        var saleCSV = "id,fabricId,length,channel,price,date\n"
        for s in store.saleRecords.sorted(by: { $0.date < $1.date }) {
            let values = [s.id.uuidString, s.fabricId.uuidString, String(s.length), s.channel, String(s.price), CSVValues.dateString(s.date)]
            saleCSV += values.map(CSVParser.escape).joined(separator: ",") + "\n"
        }
        files.append(("sale_records.csv", saleCSV))

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BucangExport-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            try? content.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }

    /// V3 全字段空模板：只含表头，填完回传可批量导入（走同一 CSVImporter）。
    static func exportTemplateFiles() -> [URL] {
        let files: [(String, String)] = [
            ("fabrics_template.csv", "id,code,name,material,composition,color,widthCm,length,purchasePrice,purchaseDate,isFavorite,note,usageNotes,channel,tagNames\n"),
            ("usage_records_template.csv", "id,fabricId,length,date,note\n"),
            ("sale_records_template.csv", "id,fabricId,length,channel,price,date\n"),
            ("works_template.csv", "id,name,startDate,finishDate,note\n"),
            ("other_items_template.csv", "id,category,name,quantityText,price,channel,note\n"),
            ("wishlist_template.csv", "id,name,note\n"),
        ]
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("BucangTemplate-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var urls: [URL] = []
        for (name, content) in files {
            let url = dir.appendingPathComponent(name)
            try? content.write(to: url, atomically: true, encoding: .utf8)
            urls.append(url)
        }
        return urls
    }
}
