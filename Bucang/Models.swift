import Foundation
import SwiftUI

// MARK: - V3 数据模型（Excel 定稿 V3）
// 内部长度一律用米存，显示时按设置的长度单位换算（米/厘米/码）。
// 旧 bucang-store.json 没有新字段时仍能解码：所有新字段都用
// decodeIfPresent + 默认值，旧数据不丢、不编造。

// MARK: - 字典：标签 / 材质（旧实体，保留作 CSV 兼容与材质选项来源）

final class Tag: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int
    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sortOrder = sortOrder
    }
}

final class Material: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int
    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sortOrder = sortOrder
    }
}

final class Channel: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int
    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id; self.name = name; self.sortOrder = sortOrder
    }
}

// MARK: - 颜色色板（主色单选）

struct FabricColorOption: Identifiable {
    var id: String { name }
    var name: String
    var color: Color
}

enum FabricColors {
    static let all: [FabricColorOption] = [
        FabricColorOption(name: "红", color: Color.red),
        FabricColorOption(name: "橙", color: Color.orange),
        FabricColorOption(name: "黄", color: Color.yellow),
        FabricColorOption(name: "绿", color: Color.green),
        FabricColorOption(name: "蓝", color: Color.blue),
        FabricColorOption(name: "紫", color: Color.purple),
        FabricColorOption(name: "粉", color: Color.pink),
        FabricColorOption(name: "白", color: Color.white),
        FabricColorOption(name: "黑", color: Color.black),
        FabricColorOption(name: "灰", color: Color.gray),
        FabricColorOption(name: "棕", color: Color.brown),
        FabricColorOption(name: "米", color: Color(red: 0.90, green: 0.85, blue: 0.70)),
        FabricColorOption(name: "多彩", color: Color(red: 0.75, green: 0.55, blue: 0.90)),
    ]
    static func color(for name: String) -> Color {
        all.first { $0.name == name }?.color ?? Color.gray
    }
    // 粗比对用 RGB 近似（仅用于拍照找相似，不声称精确识别）。
    static func rgb(for name: String) -> (Double, Double, Double) {
        switch name {
        case "红": return (1, 0, 0)
        case "橙": return (1, 0.5, 0)
        case "黄": return (1, 1, 0)
        case "绿": return (0, 0.7, 0.2)
        case "蓝": return (0, 0.3, 1)
        case "紫": return (0.6, 0.2, 0.8)
        case "粉": return (1, 0.6, 0.8)
        case "白": return (1, 1, 1)
        case "黑": return (0, 0, 0)
        case "灰": return (0.5, 0.5, 0.5)
        case "棕": return (0.6, 0.4, 0.2)
        case "米": return (0.90, 0.85, 0.70)
        case "多彩": return (0.75, 0.55, 0.90)
        default: return (0.5, 0.5, 0.5)
        }
    }
}

// MARK: - 编号体系（V8：多层级编号，可在设置 > 编号体系里配置）
// 默认 4 级：色系（12 色，代码 W/B/R/P/O/Y/G/L/Z/H/T/M）→ 纹样（1–6）
// → 序号（2 位，"-" 分隔，按色系+纹样+幅宽范围独立递增，不回收）
// → 幅宽（D 大身 / B 半幅 / J 卷布）。例：P1-01D。
// 用户可增删改各级与条目、可开关；历史编号不受影响。

final class CodeItem: Identifiable, Codable {
    var id: UUID
    var name: String   // 如 红
    var code: String   // 如 R
    var icon: String   // 如 🔴（可空）
    var enabled: Bool
    init(id: UUID = UUID(), name: String = "", code: String = "", icon: String = "", enabled: Bool = true) {
        self.id = id; self.name = name; self.code = code; self.icon = icon; self.enabled = enabled
    }
    private enum CodingKeys: String, CodingKey { case id, name, code, icon, enabled }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(code, forKey: .code); try c.encode(icon, forKey: .icon)
        try c.encode(enabled, forKey: .enabled)
    }
}

final class CodeLevel: Identifiable, Codable {
    var id: UUID
    var name: String            // 如 色系
    var kind: String            // color / pattern / sequence / width / note
    var separatorBefore: String // 该段与上一段之间的分隔符，如 "-"
    var digits: Int             // 序号位数（sequence 用）
    var enabled: Bool
    var items: [CodeItem]
    init(id: UUID = UUID(), name: String = "", kind: String = "note", separatorBefore: String = "-",
         digits: Int = 2, enabled: Bool = true, items: [CodeItem] = []) {
        self.id = id; self.name = name; self.kind = kind; self.separatorBefore = separatorBefore
        self.digits = digits; self.enabled = enabled; self.items = items
    }
    private enum CodingKeys: String, CodingKey { case id, name, kind, separatorBefore, digits, enabled, items }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "note"
        separatorBefore = try c.decodeIfPresent(String.self, forKey: .separatorBefore) ?? "-"
        digits = try c.decodeIfPresent(Int.self, forKey: .digits) ?? 2
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        items = try c.decodeIfPresent([CodeItem].self, forKey: .items) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind); try c.encode(separatorBefore, forKey: .separatorBefore)
        try c.encode(digits, forKey: .digits); try c.encode(enabled, forKey: .enabled)
        try c.encode(items, forKey: .items)
    }
}

// MARK: - 脑洞（V8 新增：灵感想法，可关联布料/成品/其他，可转成品）

final class Brainstorm: Identifiable, Codable {
    var id: UUID
    var title: String
    var content: String
    var imageFileNames: [String]
    var linkedFabricIds: [UUID]
    var linkedWorkIds: [UUID]
    var linkedOtherIds: [UUID]
    var status: String   // 想法中 / 已立项 / 已放弃
    var createdAt: Date
    var convertedWorkId: UUID?
    init(id: UUID = UUID(), title: String = "", content: String = "", imageFileNames: [String] = [],
         linkedFabricIds: [UUID] = [], linkedWorkIds: [UUID] = [], linkedOtherIds: [UUID] = [],
         status: String = "想法中", createdAt: Date = Date(), convertedWorkId: UUID? = nil) {
        self.id = id; self.title = title; self.content = content; self.imageFileNames = imageFileNames
        self.linkedFabricIds = linkedFabricIds; self.linkedWorkIds = linkedWorkIds
        self.linkedOtherIds = linkedOtherIds; self.status = status
        self.createdAt = createdAt; self.convertedWorkId = convertedWorkId
    }
    private enum CodingKeys: String, CodingKey {
        case id, title, content, imageFileNames, linkedFabricIds, linkedWorkIds, linkedOtherIds, status, createdAt, convertedWorkId
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        content = try c.decodeIfPresent(String.self, forKey: .content) ?? ""
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        linkedFabricIds = try c.decodeIfPresent([UUID].self, forKey: .linkedFabricIds) ?? []
        linkedWorkIds = try c.decodeIfPresent([UUID].self, forKey: .linkedWorkIds) ?? []
        linkedOtherIds = try c.decodeIfPresent([UUID].self, forKey: .linkedOtherIds) ?? []
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "想法中"
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        convertedWorkId = try c.decodeIfPresent(UUID.self, forKey: .convertedWorkId)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(title, forKey: .title)
        try c.encode(content, forKey: .content); try c.encode(imageFileNames, forKey: .imageFileNames)
        try c.encode(linkedFabricIds, forKey: .linkedFabricIds); try c.encode(linkedWorkIds, forKey: .linkedWorkIds)
        try c.encode(linkedOtherIds, forKey: .linkedOtherIds); try c.encode(status, forKey: .status)
        try c.encode(createdAt, forKey: .createdAt); try c.encodeIfPresent(convertedWorkId, forKey: .convertedWorkId)
    }
}

// MARK: - 长度单位（内部米，显示换算）

enum LengthUnitHelper {
    static func factorToDisplay(unit: String) -> Double {
        switch unit {
        case "厘米": return 100
        case "码": return 1.09361
        default: return 1
        }
    }
    static func fromDisplay(_ value: Double, unit: String) -> Double {
        let f = factorToDisplay(unit: unit)
        return f == 0 ? value : value / f
    }
    static func format(_ metres: Double, unit: String) -> String {
        let v = metres * factorToDisplay(unit: unit)
        return String(format: "%.2f", v)
    }
    static func suffix(unit: String) -> String {
        switch unit {
        case "厘米": return "厘米"
        case "码": return "码"
        default: return "米"
        }
    }
}

// MARK: - 备注条目（V9.1：备注改为多条列表，每条带时间；
// 旧数据的单条 note 文本在 Fabric 解码时迁移为第一条，note 字段保留作兼容）

struct NoteEntry: Codable, Identifiable {
    var id: UUID
    var text: String
    var createdAt: Date
    init(id: UUID = UUID(), text: String = "", createdAt: Date = Date()) {
        self.id = id; self.text = text; self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case id, text, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        text = try c.decodeIfPresent(String.self, forKey: .text) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(text, forKey: .text)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - 布料（V3）

final class Fabric: Identifiable, Codable {
    var id: UUID
    var name: String
    // 内部米；旧字段，保留作兼容与统计。
    var length: Double
    // 内部米；旧字段，显示时换算成厘米（V3 幅宽单位是厘米）。
    var width: Double
    var purchasePrice: Double
    var pricePerMeter: Double
    var purchaseDate: Date?
    var usedLength: Double
    var isFavorite: Bool
    var status: Int
    var note: String
    // V9.1：多条备注（UI 只读写 notes；note 保留给旧 JSON 解码，解码时迁移为 notes 第一条）。
    var notes: [NoteEntry]
    var createdAt: Date
    var updatedAt: Date
    var materialId: UUID?
    var channelId: UUID?
    var tagIds: [UUID]
    var imageFileNames: [String]
    // V3 新增
    var code: String
    var materialName: String
    var composition: String
    var colorName: String
    var weightGsm: Double?
    var shrinkagePct: Double?
    var washing: [String]
    var usageNotes: String
    var channelName: String
    var merchantName: String
    var brainstorm: String
    var subCodes: [String]
    var videoFileNames: [String]
    // V8 新增：codeSegments 生成时按层级顺序存每段（如 ["P","1","01","D"]），
    // 用于层级排序；collapsedSections 存详情页收起的板块键，默认只收起"其他信息"。
    var codeSegments: [String]
    var collapsedSections: [String]
    var hasTotalPrice: Bool
    var hasPurchaseLength: Bool

    // 派生：剩余（旧口径，不含售出；V3 剩余请用 Store.remaining(for:)，
    // 它会再减售出长度）。
    var remainingLength: Double { max(0, length - usedLength) }
    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名布料" : name
    }
    var unitPrice: Double? {
        guard hasTotalPrice, length > 0 else { return nil }
        return purchasePrice / length
    }
    var widthCm: Double { width * 100 }
    // 显示用材质 / 渠道：新字段优先，旧 ID 兜底由 Store 归一化后也已填进新字段。
    var displayMaterial: String { materialName }
    var displayChannel: String { channelName }

    init(
        id: UUID = UUID(), name: String = "", length: Double = 0, width: Double = 0,
        purchasePrice: Double = 0, pricePerMeter: Double = 0, purchaseDate: Date? = nil,
        usedLength: Double = 0, isFavorite: Bool = false, status: Int = 0, note: String = "",
        notes: [NoteEntry] = [],
        createdAt: Date = Date(), updatedAt: Date = Date(),
        materialId: UUID? = nil, channelId: UUID? = nil, tagIds: [UUID] = [],
        imageFileNames: [String] = [],
        code: String = "", materialName: String = "", composition: String = "",
        colorName: String = "", weightGsm: Double? = nil, shrinkagePct: Double? = nil,
        washing: [String] = [], usageNotes: String = "", channelName: String = "",
        merchantName: String = "", brainstorm: String = "", subCodes: [String] = [],
        videoFileNames: [String] = [], codeSegments: [String] = [],
        collapsedSections: [String] = ["other"],
        hasTotalPrice: Bool = true, hasPurchaseLength: Bool = true
    ) {
        self.id = id; self.name = name; self.length = length; self.width = width
        self.purchasePrice = purchasePrice; self.pricePerMeter = pricePerMeter
        self.purchaseDate = purchaseDate; self.usedLength = usedLength
        self.isFavorite = isFavorite; self.status = status; self.note = note
        // V9.1：直接传 note 建布料时（如心愿单转入库、CSV 导入），自动同步为第一条备注，
        // 避免各调用处逐个补同步逻辑；已显式传 notes 的不受影响。
        if notes.isEmpty && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            self.notes = [NoteEntry(text: note, createdAt: createdAt)]
        } else {
            self.notes = notes
        }
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.materialId = materialId; self.channelId = channelId; self.tagIds = tagIds
        self.imageFileNames = imageFileNames; self.code = code; self.materialName = materialName
        self.composition = composition; self.colorName = colorName; self.weightGsm = weightGsm
        self.shrinkagePct = shrinkagePct; self.washing = washing; self.usageNotes = usageNotes
        self.channelName = channelName; self.merchantName = merchantName
        self.brainstorm = brainstorm; self.subCodes = subCodes
        self.videoFileNames = videoFileNames; self.codeSegments = codeSegments
        self.collapsedSections = collapsedSections
        self.hasTotalPrice = hasTotalPrice
        self.hasPurchaseLength = hasPurchaseLength
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, length, width, purchasePrice, pricePerMeter, purchaseDate
        case usedLength, isFavorite, status, note, notes, createdAt, updatedAt
        case materialId, channelId, tagIds, imageFileNames
        case code, materialName, composition, colorName, weightGsm, shrinkagePct
        case washing, usageNotes, channelName, merchantName, brainstorm, subCodes, videoFileNames
        case codeSegments, collapsedSections
        case hasTotalPrice, hasPurchaseLength
    }

    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        length = try c.decodeIfPresent(Double.self, forKey: .length) ?? 0
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 0
        purchasePrice = try c.decodeIfPresent(Double.self, forKey: .purchasePrice) ?? 0
        pricePerMeter = try c.decodeIfPresent(Double.self, forKey: .pricePerMeter) ?? 0
        purchaseDate = try c.decodeIfPresent(Date.self, forKey: .purchaseDate)
        usedLength = try c.decodeIfPresent(Double.self, forKey: .usedLength) ?? 0
        isFavorite = try c.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        status = try c.decodeIfPresent(Int.self, forKey: .status) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        // V9.1 迁移：旧 JSON 只有单条 note 文本时，把它作为第一条备注（时间用创建时间）。
        notes = try c.decodeIfPresent([NoteEntry].self, forKey: .notes) ?? []
        if notes.isEmpty && !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notes = [NoteEntry(text: note, createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date())]
        }
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
        materialId = try c.decodeIfPresent(UUID.self, forKey: .materialId)
        channelId = try c.decodeIfPresent(UUID.self, forKey: .channelId)
        tagIds = try c.decodeIfPresent([UUID].self, forKey: .tagIds) ?? []
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        materialName = try c.decodeIfPresent(String.self, forKey: .materialName) ?? ""
        composition = try c.decodeIfPresent(String.self, forKey: .composition) ?? ""
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? ""
        weightGsm = try c.decodeIfPresent(Double.self, forKey: .weightGsm)
        shrinkagePct = try c.decodeIfPresent(Double.self, forKey: .shrinkagePct)
        washing = try c.decodeIfPresent([String].self, forKey: .washing) ?? []
        usageNotes = try c.decodeIfPresent(String.self, forKey: .usageNotes) ?? ""
        channelName = try c.decodeIfPresent(String.self, forKey: .channelName) ?? ""
        merchantName = try c.decodeIfPresent(String.self, forKey: .merchantName) ?? ""
        brainstorm = try c.decodeIfPresent(String.self, forKey: .brainstorm) ?? ""
        subCodes = try c.decodeIfPresent([String].self, forKey: .subCodes) ?? []
        videoFileNames = try c.decodeIfPresent([String].self, forKey: .videoFileNames) ?? []
        codeSegments = try c.decodeIfPresent([String].self, forKey: .codeSegments) ?? []
        // V8 前旧数据没有收起状态：默认只收起"其他信息"。
        collapsedSections = try c.decodeIfPresent([String].self, forKey: .collapsedSections) ?? ["other"]
        // 旧数据没有这两个标志时按旧值推断：有价格/有长度即视为已填，0 视为未填。
        hasTotalPrice = try c.decodeIfPresent(Bool.self, forKey: .hasTotalPrice) ?? (purchasePrice > 0)
        hasPurchaseLength = try c.decodeIfPresent(Bool.self, forKey: .hasPurchaseLength) ?? (length > 0)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(length, forKey: .length)
        try c.encode(width, forKey: .width)
        try c.encode(purchasePrice, forKey: .purchasePrice)
        try c.encode(pricePerMeter, forKey: .pricePerMeter)
        try c.encodeIfPresent(purchaseDate, forKey: .purchaseDate)
        try c.encode(usedLength, forKey: .usedLength)
        try c.encode(isFavorite, forKey: .isFavorite)
        try c.encode(status, forKey: .status)
        try c.encode(note, forKey: .note)
        try c.encode(notes, forKey: .notes)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encodeIfPresent(materialId, forKey: .materialId)
        try c.encodeIfPresent(channelId, forKey: .channelId)
        try c.encode(tagIds, forKey: .tagIds)
        try c.encode(imageFileNames, forKey: .imageFileNames)
        try c.encode(code, forKey: .code)
        try c.encode(materialName, forKey: .materialName)
        try c.encode(composition, forKey: .composition)
        try c.encode(colorName, forKey: .colorName)
        try c.encodeIfPresent(weightGsm, forKey: .weightGsm)
        try c.encodeIfPresent(shrinkagePct, forKey: .shrinkagePct)
        try c.encode(washing, forKey: .washing)
        try c.encode(usageNotes, forKey: .usageNotes)
        try c.encode(channelName, forKey: .channelName)
        try c.encode(merchantName, forKey: .merchantName)
        try c.encode(brainstorm, forKey: .brainstorm)
        try c.encode(subCodes, forKey: .subCodes)
        try c.encode(videoFileNames, forKey: .videoFileNames)
        try c.encode(codeSegments, forKey: .codeSegments)
        try c.encode(collapsedSections, forKey: .collapsedSections)
        try c.encode(hasTotalPrice, forKey: .hasTotalPrice)
        try c.encode(hasPurchaseLength, forKey: .hasPurchaseLength)
    }
}

// MARK: - 使用记录（V3：可关联多个成品）

final class UsageRecord: Identifiable, Codable {
    var id: UUID
    var date: Date
    var length: Double
    var note: String
    var fabricId: UUID
    var workIds: [UUID]
    init(id: UUID = UUID(), date: Date = Date(), length: Double = 0, note: String = "", fabricId: UUID, workIds: [UUID] = []) {
        self.id = id; self.date = date; self.length = length; self.note = note; self.fabricId = fabricId; self.workIds = workIds
    }
    private enum CodingKeys: String, CodingKey { case id, date, length, note, fabricId, workIds }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        length = try c.decodeIfPresent(Double.self, forKey: .length) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        fabricId = try c.decodeIfPresent(UUID.self, forKey: .fabricId) ?? UUID()
        workIds = try c.decodeIfPresent([UUID].self, forKey: .workIds) ?? []
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(date, forKey: .date)
        try c.encode(length, forKey: .length); try c.encode(note, forKey: .note)
        try c.encode(fabricId, forKey: .fabricId); try c.encode(workIds, forKey: .workIds)
    }
}

// MARK: - 出售记录（V3 新增：不计入消耗）

final class SaleRecord: Identifiable, Codable {
    var id: UUID
    var fabricId: UUID
    var length: Double
    var channel: String
    var merchant: String
    var price: Double
    var date: Date
    var note: String
    var imageFileNames: [String]
    var isPieces: Bool
    var pieces: Int
    init(id: UUID = UUID(), fabricId: UUID, length: Double = 0, channel: String = "", merchant: String = "", price: Double = 0, date: Date = Date(), note: String = "", imageFileNames: [String] = [], isPieces: Bool = false, pieces: Int = 0) {
        self.id = id; self.fabricId = fabricId; self.length = length; self.channel = channel; self.merchant = merchant; self.price = price; self.date = date; self.note = note; self.imageFileNames = imageFileNames; self.isPieces = isPieces; self.pieces = pieces
    }
    private enum CodingKeys: String, CodingKey { case id, fabricId, length, channel, merchant, price, date, note, imageFileNames, isPieces, pieces }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        fabricId = try c.decodeIfPresent(UUID.self, forKey: .fabricId) ?? UUID()
        length = try c.decodeIfPresent(Double.self, forKey: .length) ?? 0
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        merchant = try c.decodeIfPresent(String.self, forKey: .merchant) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        date = try c.decodeIfPresent(Date.self, forKey: .date) ?? Date()
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        isPieces = try c.decodeIfPresent(Bool.self, forKey: .isPieces) ?? false
        pieces = try c.decodeIfPresent(Int.self, forKey: .pieces) ?? 0
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(fabricId, forKey: .fabricId)
        try c.encode(length, forKey: .length); try c.encode(channel, forKey: .channel)
        try c.encode(merchant, forKey: .merchant)
        try c.encode(price, forKey: .price); try c.encode(date, forKey: .date)
        try c.encode(note, forKey: .note); try c.encode(imageFileNames, forKey: .imageFileNames)
        try c.encode(isPieces, forKey: .isPieces); try c.encode(pieces, forKey: .pieces)
    }
}

// MARK: - 成品用料

struct WorkMaterial: Codable, Identifiable {
    var id: UUID = UUID()
    var fabricId: UUID
    var amount: Double
    init(fabricId: UUID, amount: Double) {
        self.fabricId = fabricId; self.amount = amount
    }
}

// MARK: - 成品（V3：开始/完成时间 + 用料清单 + 成本合计派生）

final class Work: Identifiable, Codable {
    var id: UUID
    var name: String
    var progress: Double
    var startedAt: Date?
    var finishedAt: Date?
    var costPrice: Double
    var sellPrice: Double
    var timeHours: Double
    var note: String
    var createdAt: Date
    var imageFileNames: [String]
    var materials: [WorkMaterial]
    var isSold: Bool
    var salePrice: Double
    var hasSalePrice: Bool
    var saleDate: Date?
    var saleChannel: String
    var isUsed: Bool
    var usageCount: Int
    // V8 新增：工费（非必填，留空不计入总成本）
    var laborCost: Double
    var hasLaborCost: Bool
    // 2026-10-31：成品颜色
    var colorName: String
    var isFinished: Bool { finishedAt != nil }
    init(
        id: UUID = UUID(), name: String = "", progress: Double = 0,
        startedAt: Date? = nil, finishedAt: Date? = nil,
        costPrice: Double = 0, sellPrice: Double = 0, timeHours: Double = 0,
        note: String = "", createdAt: Date = Date(),
        imageFileNames: [String] = [], materials: [WorkMaterial] = [],
        isSold: Bool = false, salePrice: Double = 0, hasSalePrice: Bool = false,
        saleDate: Date? = nil, saleChannel: String = "", isUsed: Bool = false, usageCount: Int = 0,
        laborCost: Double = 0, hasLaborCost: Bool = false, colorName: String = ""
    ) {
        self.id = id; self.name = name; self.progress = progress
        self.startedAt = startedAt; self.finishedAt = finishedAt
        self.costPrice = costPrice; self.sellPrice = sellPrice; self.timeHours = timeHours
        self.note = note; self.createdAt = createdAt
        self.imageFileNames = imageFileNames; self.materials = materials
        self.isSold = isSold; self.salePrice = salePrice; self.hasSalePrice = hasSalePrice
        self.saleDate = saleDate; self.saleChannel = saleChannel; self.isUsed = isUsed; self.usageCount = usageCount
        self.laborCost = laborCost; self.hasLaborCost = hasLaborCost; self.colorName = colorName
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, progress, startedAt, finishedAt, costPrice, sellPrice, timeHours, note, createdAt, imageFileNames, materials
        case isSold, salePrice, hasSalePrice, saleDate, saleChannel, isUsed, usageCount
        case laborCost, hasLaborCost, colorName
    }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        progress = try c.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        startedAt = try c.decodeIfPresent(Date.self, forKey: .startedAt)
        finishedAt = try c.decodeIfPresent(Date.self, forKey: .finishedAt)
        costPrice = try c.decodeIfPresent(Double.self, forKey: .costPrice) ?? 0
        sellPrice = try c.decodeIfPresent(Double.self, forKey: .sellPrice) ?? 0
        timeHours = try c.decodeIfPresent(Double.self, forKey: .timeHours) ?? 0
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        materials = try c.decodeIfPresent([WorkMaterial].self, forKey: .materials) ?? []
        isSold = try c.decodeIfPresent(Bool.self, forKey: .isSold) ?? false
        salePrice = try c.decodeIfPresent(Double.self, forKey: .salePrice) ?? 0
        hasSalePrice = try c.decodeIfPresent(Bool.self, forKey: .hasSalePrice) ?? (salePrice > 0)
        saleDate = try c.decodeIfPresent(Date.self, forKey: .saleDate)
        saleChannel = try c.decodeIfPresent(String.self, forKey: .saleChannel) ?? ""
        isUsed = try c.decodeIfPresent(Bool.self, forKey: .isUsed) ?? false
        usageCount = try c.decodeIfPresent(Int.self, forKey: .usageCount) ?? 0
        laborCost = try c.decodeIfPresent(Double.self, forKey: .laborCost) ?? 0
        hasLaborCost = try c.decodeIfPresent(Bool.self, forKey: .hasLaborCost) ?? (laborCost > 0)
        colorName = try c.decodeIfPresent(String.self, forKey: .colorName) ?? "" 
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(progress, forKey: .progress); try c.encodeIfPresent(startedAt, forKey: .startedAt)
        try c.encodeIfPresent(finishedAt, forKey: .finishedAt); try c.encode(costPrice, forKey: .costPrice)
        try c.encode(sellPrice, forKey: .sellPrice); try c.encode(timeHours, forKey: .timeHours)
        try c.encode(note, forKey: .note); try c.encode(createdAt, forKey: .createdAt)
        try c.encode(imageFileNames, forKey: .imageFileNames); try c.encode(materials, forKey: .materials)
        try c.encode(isSold, forKey: .isSold); try c.encode(salePrice, forKey: .salePrice)
        try c.encode(hasSalePrice, forKey: .hasSalePrice); try c.encodeIfPresent(saleDate, forKey: .saleDate)
        try c.encode(saleChannel, forKey: .saleChannel); try c.encode(isUsed, forKey: .isUsed)
        try c.encode(usageCount, forKey: .usageCount)
        try c.encode(laborCost, forKey: .laborCost); try c.encode(hasLaborCost, forKey: .hasLaborCost)
    }
}

// MARK: - 纸样 / 物品（旧实体：保留数据，不在 V3 主界面展示）

final class Pattern: Identifiable, Codable {
    var id: UUID; var name: String; var price: Double; var pieceCount: Int
    var sizeDesc: String; var purchasedAt: Date?; var note: String; var createdAt: Date
    init(id: UUID = UUID(), name: String = "", price: Double = 0, pieceCount: Int = 0, sizeDesc: String = "", purchasedAt: Date? = nil, note: String = "", createdAt: Date = Date()) {
        self.id = id; self.name = name; self.price = price; self.pieceCount = pieceCount
        self.sizeDesc = sizeDesc; self.purchasedAt = purchasedAt; self.note = note; self.createdAt = createdAt
    }
}

final class Item: Identifiable, Codable {
    var id: UUID; var name: String; var price: Double; var quantity: Int
    var sizeDesc: String; var purchasedAt: Date?; var note: String; var createdAt: Date
    init(id: UUID = UUID(), name: String = "", price: Double = 0, quantity: Int = 0, sizeDesc: String = "", purchasedAt: Date? = nil, note: String = "", createdAt: Date = Date()) {
        self.id = id; self.name = name; self.price = price; self.quantity = quantity
        self.sizeDesc = sizeDesc; self.purchasedAt = purchasedAt; self.note = note; self.createdAt = createdAt
    }
}

// MARK: - 其他条目（V3 新增）

final class OtherItem: Identifiable, Codable {
    var id: UUID; var category: String; var name: String; var imageFileNames: [String]
    var quantityText: String; var price: Double; var hasPrice: Bool; var channel: String; var note: String; var createdAt: Date
    init(id: UUID = UUID(), category: String = "", name: String = "", imageFileNames: [String] = [], quantityText: String = "", price: Double = 0, hasPrice: Bool = false, channel: String = "", note: String = "", createdAt: Date = Date()) {
        self.id = id; self.category = category; self.name = name; self.imageFileNames = imageFileNames
        self.quantityText = quantityText; self.price = price; self.hasPrice = hasPrice
        self.channel = channel; self.note = note; self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case id, category, name, imageFileNames, quantityText, price, hasPrice, channel, note, createdAt }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        category = try c.decodeIfPresent(String.self, forKey: .category) ?? ""
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        quantityText = try c.decodeIfPresent(String.self, forKey: .quantityText) ?? ""
        price = try c.decodeIfPresent(Double.self, forKey: .price) ?? 0
        hasPrice = try c.decodeIfPresent(Bool.self, forKey: .hasPrice) ?? (price > 0)
        channel = try c.decodeIfPresent(String.self, forKey: .channel) ?? ""
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(category, forKey: .category)
        try c.encode(name, forKey: .name); try c.encode(imageFileNames, forKey: .imageFileNames)
        try c.encode(quantityText, forKey: .quantityText); try c.encode(price, forKey: .price)
        try c.encode(hasPrice, forKey: .hasPrice); try c.encode(channel, forKey: .channel)
        try c.encode(note, forKey: .note); try c.encode(createdAt, forKey: .createdAt)
    }
}

// MARK: - 心愿单（V3 新增）

final class WishlistItem: Identifiable, Codable {
    var id: UUID; var name: String; var imageFileNames: [String]; var note: String; var createdAt: Date
    // V8 新增：预估价（转入库时带入布料总价）
    var estimatedPrice: Double; var hasEstimatedPrice: Bool
    // 2026-10-31：已购标记
    var isPurchased: Bool
    init(id: UUID = UUID(), name: String = "", imageFileNames: [String] = [], note: String = "", createdAt: Date = Date(),
         estimatedPrice: Double = 0, hasEstimatedPrice: Bool = false, isPurchased: Bool = false) {
        self.id = id; self.name = name; self.imageFileNames = imageFileNames; self.note = note; self.createdAt = createdAt
        self.estimatedPrice = estimatedPrice; self.hasEstimatedPrice = hasEstimatedPrice; self.isPurchased = isPurchased
    }
    private enum CodingKeys: String, CodingKey { case id, name, imageFileNames, note, createdAt, estimatedPrice, hasEstimatedPrice, isPurchased }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        estimatedPrice = try c.decodeIfPresent(Double.self, forKey: .estimatedPrice) ?? 0
        hasEstimatedPrice = try c.decodeIfPresent(Bool.self, forKey: .hasEstimatedPrice) ?? (estimatedPrice > 0)
        isPurchased = try c.decodeIfPresent(Bool.self, forKey: .isPurchased) ?? false
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(imageFileNames, forKey: .imageFileNames); try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(estimatedPrice, forKey: .estimatedPrice); try c.encode(hasEstimatedPrice, forKey: .hasEstimatedPrice)
    }
}

// MARK: - 本地存储

struct StoreData: Codable {
    var tags: [Tag] = []
    var materials: [Material] = []
    var channels: [Channel] = []
    var fabrics: [Fabric] = []
    var usageRecords: [UsageRecord] = []
    var works: [Work] = []
    var patterns: [Pattern] = []
    var items: [Item] = []
    var saleRecords: [SaleRecord] = []
    var otherItems: [OtherItem] = []
    var wishlistItems: [WishlistItem] = []
    var brainstorms: [Brainstorm] = []
    var materialOptions: [String] = []
    var otherCategories: [String] = []
    var lengthUnit: String = "米"
    var hideAmounts: Bool = false
    var codePrefix: String = ""
    var channelOptions: [String] = []
    // patternOptions：Build #12 的旧纹样选项，V8 起编号体系改用 codeLevels，
    // 该字段仅为数据兼容保留，UI 不再展示。
    var patternOptions: [String] = []
    var codeLevels: [CodeLevel] = []
    var visibleTabs: [String] = []
    var themeName: String = "深蓝"
    // V9：布料卡片显示字段（key 见 Store.cardFieldOptions）。旧 JSON 没有该键时
    // 解码为 []，Store.apply 里按默认 5 项补齐，走 visibleTabs/codeLevels 的迁移口径。
    var cardDisplayFields: [String] = []
}

@MainActor
final class Store: ObservableObject {
    @Published var tags: [Tag] = []
    @Published var materials: [Material] = []
    @Published var channels: [Channel] = []
    @Published var fabrics: [Fabric] = []
    @Published var usageRecords: [UsageRecord] = []
    @Published var works: [Work] = []
    @Published var patterns: [Pattern] = []
    @Published var items: [Item] = []
    @Published var saleRecords: [SaleRecord] = []
    @Published var otherItems: [OtherItem] = []
    @Published var wishlistItems: [WishlistItem] = []
    @Published var brainstorms: [Brainstorm] = []
    @Published var materialOptions: [String] = []
    @Published var otherCategories: [String] = []
    @Published var lengthUnit: String = "米"
    @Published var hideAmounts: Bool = false
    @Published var codePrefix: String = ""
    @Published var channelOptions: [String] = []
    // patternOptions 仅数据兼容保留，V8 UI 不再使用（改用 codeLevels）。
    @Published var patternOptions: [String] = []
    @Published var codeLevels: [CodeLevel] = []
    @Published var visibleTabs: [String] = []
    @Published var themeName: String = "深蓝"
    @Published var cardDisplayFields: [String] = []

    static let defaultMaterialOptions = ["棉", "麻", "丝", "毛", "化纤", "混纺", "针织", "其他"]
    static let defaultOtherCategories = ["其他"]
    static let defaultChannelOptions = ["淘宝", "闲鱼", "小红书"]
    static let defaultPatternOptions = ["素色", "提花", "印花", "格纹", "条纹", "碎花", "暗花", "缎面"]
    static let allTabKeys = ["fabric", "work", "brainstorm", "other", "wishlist"]
    static let defaultVisibleTabs = ["fabric", "work", "brainstorm", "wishlist"]
    // V9 卡片显示字段：9 个可用 key 与中文名，数组顺序即设置页与卡片的展示顺序。
    static let cardFieldOptions: [(key: String, title: String)] = [
        ("material", "材质"),
        ("width", "宽幅"),
        ("length", "米数"),
        ("unitPrice", "单价"),
        ("remaining", "剩余数"),
        ("totalPrice", "总价"),
        ("color", "颜色"),
        ("channel", "渠道"),
        ("tags", "标签"),
    ]
    static let defaultCardDisplayFields = ["material", "width", "length", "unitPrice", "remaining"]
    // V8 状态胶囊：7 级。派生优先级见 status(for:)：
    // 已出售（售出且剩余 0）＞ 部分出售（售出且剩余 >0）＞ 已用完 ＞ 使用中 ＞ 未使用。
    // 说明文档原表把“使用中”排在“已用完”前会使已用完永远不可达，此处按可达的合理
    // 口径实现（剩余为 0 且有用过 → 已用完，否则有用过 → 使用中）。
    static let statusCapsules = ["全部", "收藏", "未使用", "使用中", "已用完", "部分出售", "已出售"]
    // 旧颜色名 → 新色系表名（V8 编号体系的色系级）。不在映射里且不在色系表里的
    // 名字保留原样，code 查不到（显示时只显示名字）。
    // V8.1："多/多色/多彩"统一为"其他"（色轮图标），"米/米色/米白"并入"茶"。
    static let oldColorNameMap = ["棕": "茶", "米": "茶", "多": "其他", "多色": "其他", "多彩": "其他"]

    static func defaultColorItems() -> [CodeItem] {
        // 图2的13色默认值（2026-10-31）：圆色块图标存16进制，顺序按图。
        [
            ("红", "R", "#FF3B30"), ("橙", "O", "#FF9500"), ("黄", "Y", "#FFCC00"),
            ("绿", "G", "#34C759"), ("蓝", "B", "#007AFF"), ("紫", "Z", "#AF52DE"),
            ("粉", "P", "#FF2D55"), ("白", "W", "#FFFFFF"), ("黑", "K", "#000000"),
            ("灰", "H", "#8E8E93"), ("棕", "BR", "#A2845E"), ("米", "M", "#E5D9B8"),
            ("多彩", "D", "#C9A9E0"), ("其他", "Q", "rainbow"),
        ].map { CodeItem(name: $0.0, code: $0.1, icon: $0.2) }
    }
    static func defaultCodeLevels() -> [CodeLevel] {
        let colorItems = defaultColorItems()
        let patternItems = [
            ("无地", "1"), ("小纹", "2"), ("付下", "3"),
            ("绞染/絣", "4"), ("刺绣", "5"), ("段染/霞染", "6"),
        ].map { CodeItem(name: $0.0, code: $0.1) }
        let widthItems = [
            ("大身", "D"), ("半幅", "B"), ("卷布", "J"),
        ].map { CodeItem(name: $0.0, code: $0.1) }
        return [
            CodeLevel(name: "色系", kind: "color", separatorBefore: "", items: colorItems),
            CodeLevel(name: "纹样", kind: "pattern", separatorBefore: "", items: patternItems),
            CodeLevel(name: "序号", kind: "sequence", separatorBefore: "-", digits: 2),
            CodeLevel(name: "幅宽", kind: "width", separatorBefore: "", items: widthItems),
        ]
    }

    init() { load() }

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-store.json")
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: data) else { return }
        apply(decoded)
    }

    func apply(_ decoded: StoreData) {
        tags = decoded.tags; materials = decoded.materials; channels = decoded.channels
        fabrics = decoded.fabrics; usageRecords = decoded.usageRecords
        works = decoded.works; patterns = decoded.patterns; items = decoded.items
        saleRecords = decoded.saleRecords; otherItems = decoded.otherItems
        wishlistItems = decoded.wishlistItems
        brainstorms = decoded.brainstorms
        materialOptions = decoded.materialOptions.isEmpty ? Self.defaultMaterialOptions : decoded.materialOptions
        otherCategories = decoded.otherCategories.isEmpty ? Self.defaultOtherCategories : decoded.otherCategories
        lengthUnit = ["米", "厘米", "码"].contains(decoded.lengthUnit) ? decoded.lengthUnit : "米"
        hideAmounts = decoded.hideAmounts; codePrefix = decoded.codePrefix
        channelOptions = decoded.channelOptions.isEmpty ? Self.defaultChannelOptions : decoded.channelOptions
        patternOptions = decoded.patternOptions.isEmpty ? Self.defaultPatternOptions : decoded.patternOptions
        codeLevels = decoded.codeLevels.isEmpty ? Self.defaultCodeLevels() : decoded.codeLevels
        migrateColorDefaults()
        ensureFixedOtherColor()
        // migrateColorWheel 已停用（2026-10-31）：旧逻辑删"米"/改名"多彩"，与新13色默认值冲突
        if decoded.visibleTabs.isEmpty {
            visibleTabs = Self.defaultVisibleTabs
        } else {
            // 老用户迁移：补上 V8 新增的 brainstrom tab，保证能看到新 Tab。
            visibleTabs = decoded.visibleTabs.filter { Self.allTabKeys.contains($0) }
            if !visibleTabs.contains("brainstorm") { visibleTabs.append("brainstorm") }
        }
        if !visibleTabs.contains("fabric") { visibleTabs.insert("fabric", at: 0) }
        themeName = decoded.themeName.isEmpty ? "深蓝" : decoded.themeName
        // cardDisplayFields 迁移口径与 codeLevels/visibleTabs 一致：空视为未设置，用默认 5 项。
        cardDisplayFields = decoded.cardDisplayFields.isEmpty ? Self.defaultCardDisplayFields : decoded.cardDisplayFields
        normalizeLegacyFabrics()
    }

    /// 色轮迁移（V8.1）：色系级里删除 米/米色/米白 条目；
    /// 多/多色/多彩 条目改名为"其他"、图标改成 "wheel"；
    /// 布料 colorName 同步：米/米色/米白→茶，多/多色/多彩→其他。
    /// 精确匹配；幂等，每次 load/apply 都可安全重跑；有改动才 save。
    private func migrateColorWheel() {
        var changed = false
        for level in codeLevels where level.kind == "color" {
            let before = level.items.count
            level.items.removeAll { $0.name == "米" || $0.name == "米色" || $0.name == "米白" }
            if level.items.count != before { changed = true }
            for item in level.items where item.name == "多" || item.name == "多色" || item.name == "多彩" {
                item.name = "其他"
                item.icon = "wheel"
                changed = true
            }
        }
        for fabric in fabrics {
            let newName: String
            switch fabric.colorName {
            case "米", "米色", "米白": newName = "茶"
            case "多", "多色", "多彩": newName = "其他"
            default: newName = fabric.colorName
            }
            if newName != fabric.colorName {
                fabric.colorName = newName
                changed = true
            }
        }
        if changed { save() }
    }

    /// 旧数据归一化：旧布料只有 materialId/channelId 时，按字典名填进
    /// V3 的 materialName/channelName；不编造名称，查不到就留空。
    /// 同时把字典里的材质名补进材质选项，保证筛选面板能读到旧材质。
    func normalizeLegacyFabrics() {
        let materialById: [UUID: String] = Dictionary(uniqueKeysWithValues: materials.map { ($0.id, $0.name) })
        let channelById: [UUID: String] = Dictionary(uniqueKeysWithValues: channels.map { ($0.id, $0.name) })
        for fabric in fabrics {
            if fabric.materialName.isEmpty, let mid = fabric.materialId, let name = materialById[mid] {
                fabric.materialName = name
            }
            if fabric.channelName.isEmpty, let cid = fabric.channelId, let name = channelById[cid] {
                fabric.channelName = name
            }
        }
        for name in materials.map({ $0.name }) where !name.isEmpty && !materialOptions.contains(name) {
            materialOptions.append(name)
        }
        for fabric in fabrics where !fabric.materialName.isEmpty && !materialOptions.contains(fabric.materialName) {
            materialOptions.append(fabric.materialName)
        }
            for fabric in fabrics where !fabric.channelName.isEmpty && !channelOptions.contains(fabric.channelName) {
            channelOptions.append(fabric.channelName)
        }
        // V8 颜色迁移：旧颜色名按 oldColorNameMap 映射到新色系表
        //（棕/米→茶，多/多色/多彩→其他），其余旧名原样保留；
        // 色系表里查不到 code 的显示时只显示名字。
        for fabric in fabrics {
            if let mapped = Self.oldColorNameMap[fabric.colorName] {
                fabric.colorName = mapped
            }
        }
    }

    // MARK: - 编号体系（V8）

    /// 启用的层级（按数组顺序）。
    func levelOrder() -> [CodeLevel] { codeLevels.filter { $0.enabled } }

    /// 按颜色名查色系条目（含旧名映射），找不到返回 nil。
    func colorItem(forName name: String) -> CodeItem? {
        let mapped = Self.oldColorNameMap[name] ?? name
        return codeLevels.first { $0.kind == "color" }?.items.first { $0.enabled && $0.name == mapped }
    }
    func colorCode(forName name: String) -> String? { colorItem(forName: name)?.code }

    /// 布料各段：优先用生成时存的 codeSegments，否则尽力解析旧编号。
    func segments(of fabric: Fabric) -> [String] {
        if !fabric.codeSegments.isEmpty { return fabric.codeSegments }
        return parseSegments(code: fabric.code)
    }

    /// 尽力解析：按 -/_/空格拆分，与各级条目的 code/name 贪心匹配。
    func parseSegments(code: String) -> [String] {
        let levels = levelOrder()
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let parts = trimmed.split { $0 == "-" || $0 == "_" || $0 == " " }.map(String.init)
        var segs = Array(repeating: "", count: levels.count)
        var used = Set<Int>()
        for (li, level) in levels.enumerated() {
            if level.kind == "sequence" {
                if let i = parts.indices.first(where: { !used.contains($0) && Int(parts[$0]) != nil }) {
                    segs[li] = parts[i]; used.insert(i)
                }
            } else if level.kind == "note" {
                if let i = parts.indices.last(where: { !used.contains($0) }) {
                    segs[li] = parts[i]; used.insert(i)
                }
            } else if let i = parts.indices.first(where: { idx in !used.contains(idx) && level.items.contains(where: { $0.code == parts[idx] || $0.name == parts[idx] }) }) {
                segs[li] = parts[i]; used.insert(i)
            }
        }
        return segs
    }

    /// 按 kind 取某段（找不到返回 ""）。
    func segmentForKind(_ fabric: Fabric, kind: String) -> String {
        let levels = levelOrder()
        let segs = segments(of: fabric)
        guard let idx = levels.firstIndex(where: { $0.kind == kind }), idx < segs.count else { return "" }
        return segs[idx]
    }

    /// 某 色系+纹样+幅宽 范围下已占用的序号（不回收删除产生的空号）。
    func occupiedSequences(colorCode: String, patternCode: String, widthCode: String) -> Set<Int> {
        var set = Set<Int>()
        for f in fabrics {
            if segmentForKind(f, kind: "color") == colorCode,
               segmentForKind(f, kind: "pattern") == patternCode,
               segmentForKind(f, kind: "width") == widthCode,
               let n = Int(segmentForKind(f, kind: "sequence")) {
                set.insert(n)
            }
        }
        return set
    }
    /// 该范围内下一个可用序号。
    func nextSequenceNumber(colorCode: String, patternCode: String, widthCode: String) -> Int {
        let occ = occupiedSequences(colorCode: colorCode, patternCode: patternCode, widthCode: widthCode)
        var n = 1
        while occ.contains(n) { n += 1 }
        return n
    }

    /// 生成编号：values 按 level.id 存每级选中的段值（sequence 存数字字符串）。
    /// 返回 (编号, 各段)。首段直接拼，后续段用本级的 separatorBefore 连接。
    func generateCode(values: [UUID: String]) -> (code: String, segments: [String]) {
        let levels = levelOrder()
        var segments: [String] = []
        var code = ""
        for (idx, level) in levels.enumerated() {
            let v = values[level.id] ?? ""
            segments.append(v)
            if idx == 0 { code = v } else { code += level.separatorBefore + v }
        }
        return (code, segments)
    }

    /// 子编号自动延续：主编号 + "-1"、"-2"……（全局唯一）。
    func nextSubCode(for fabric: Fabric) -> String {
        let base = fabric.code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return "" }
        var n = 1
        // 自己已有的子编号也要跳过（codeConflict 会排除自身），否则永远生成 base-1 导致无法连续新增。
        while codeConflict(code: "\(base)-\(n)", excluding: fabric.id) != nil || fabric.subCodes.contains("\(base)-\(n)") { n += 1 }
        return "\(base)-\(n)"
    }

    /// 编号层级排序：按层级顺序逐段比。sequence 按数字；note 按字符串；
    /// 其余级按该段在条目表里的顺序；未知/缺失的段排最后；最后回退字符串比较。
    func hierarchicalCompare(_ a: Fabric, _ b: Fabric) -> ComparisonResult {
        let levels = levelOrder()
        let sa = segments(of: a), sb = segments(of: b)
        for (idx, level) in levels.enumerated() {
            let x = idx < sa.count ? sa[idx] : "", y = idx < sb.count ? sb[idx] : ""
            if x == y { continue }
            switch level.kind {
            case "sequence":
                let nx = Int(x), ny = Int(y)
                if let nx, let ny {
                    if nx != ny { return nx < ny ? .orderedAscending : .orderedDescending }
                } else if nx != nil { return .orderedAscending }
                else if ny != nil { return .orderedDescending }
                else {
                    let r = x.localizedCompare(y)
                    if r != .orderedSame { return r }
                }
            case "note":
                let r = x.localizedCompare(y)
                if r != .orderedSame { return r }
            default:
                let ix = level.items.firstIndex(where: { $0.code == x || $0.name == x })
                let iy = level.items.firstIndex(where: { $0.code == y || $0.name == y })
                if let ix, let iy {
                    if ix != iy { return ix < iy ? .orderedAscending : .orderedDescending }
                } else if ix != nil { return .orderedAscending }
                else if iy != nil { return .orderedDescending }
                else {
                    let r = x.localizedCompare(y)
                    if r != .orderedSame { return r }
                }
            }
        }
        return a.code.localizedCompare(b.code)
    }

    // MARK: - 卡片显示信息（V9：布料卡片可配置显示字段）

    /// 某字段在某块布料上的 (中文名, 显示值)；缺失值统一显示 "—"。
    /// 这是 canonical 口径：FabricViews 卡片里的内联排版是展示层写法，
    /// 取值语义以这里为准（key 不在 9 个可用字段里时返回 ("", "—")）。
    func cardField(key: String, for fabric: Fabric) -> (label: String, value: String) {
        let label = Self.cardFieldOptions.first { $0.key == key }?.title ?? ""
        switch key {
        case "material":
            let v = fabric.materialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (label, v.isEmpty ? "—" : v)
        case "width":
            // 内部米 → 厘米，整数显示，如 "37厘米"。
            let cm = fabric.widthCm
            return (label, cm > 0 ? String(format: "%.0f厘米", cm) : "—")
        case "length":
            guard fabric.hasPurchaseLength, fabric.length > 0 else { return (label, "—") }
            let unit = lengthUnit
            return (label, LengthUnitHelper.format(fabric.length, unit: unit) + LengthUnitHelper.suffix(unit: unit))
        case "unitPrice":
            guard let u = fabric.unitPrice else { return (label, "—") }
            return (label, "¥" + String(format: "%.2f", u))
        case "remaining":
            guard fabric.hasPurchaseLength else { return (label, "—") }
            let unit = lengthUnit
            return (label, LengthUnitHelper.format(remaining(for: fabric), unit: unit) + LengthUnitHelper.suffix(unit: unit))
        case "totalPrice":
            guard fabric.hasTotalPrice else { return (label, "—") }
            return (label, "¥" + String(format: "%.2f", fabric.purchasePrice))
        case "color":
            let name = fabric.colorName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return (label, "—") }
            if let code = colorCode(forName: name), !code.isEmpty {
                return (label, "\(name)/\(code)")
            }
            return (label, name)
        case "channel":
            let v = fabric.channelName.trimmingCharacters(in: .whitespacesAndNewlines)
            return (label, v.isEmpty ? "—" : v)
        case "tags":
            let names = tags(for: fabric).map { $0.name }.filter { !$0.isEmpty }
            return (label, names.isEmpty ? "—" : names.joined(separator: "、"))
        default:
            return (label, "—")
        }
    }

    func save() {
        objectWillChange.send()
        guard let url = fileURL else { return }
        let data = StoreData(
            tags: tags, materials: materials, channels: channels,
            fabrics: fabrics, usageRecords: usageRecords,
            works: works, patterns: patterns, items: items,
            saleRecords: saleRecords, otherItems: otherItems, wishlistItems: wishlistItems,
            brainstorms: brainstorms,
            materialOptions: materialOptions, otherCategories: otherCategories,
            lengthUnit: lengthUnit, hideAmounts: hideAmounts, codePrefix: codePrefix,
            channelOptions: channelOptions, patternOptions: patternOptions, codeLevels: codeLevels,
            visibleTabs: visibleTabs, themeName: themeName, cardDisplayFields: cardDisplayFields
        )
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

    // MARK: - 派生统计（V3 口径：消耗不含售出，剩余 = 买入 - 消耗 - 售出）

    func soldLength(for fabricId: UUID) -> Double {
        // 只计长度出售，份数出售不进米数。
        saleRecords.filter { $0.fabricId == fabricId && !$0.isPieces }.reduce(0) { $0 + $1.length }
    }
    func soldPiecesTotal() -> Int {
        saleRecords.filter { $0.isPieces }.reduce(0) { $0 + $1.pieces }
    }
    func saleRecords(for fabricId: UUID) -> [SaleRecord] {
        saleRecords.filter { $0.fabricId == fabricId }.sorted { $0.date > $1.date }
    }
    func remaining(for fabric: Fabric) -> Double {
        guard fabric.hasPurchaseLength else { return 0 }
        return max(0, fabric.length - fabric.usedLength - soldLength(for: fabric.id))
    }
    func status(for fabric: Fabric) -> String {
        // 主状态：取 statuses 的第一个，保持旧调用兼容。
        statuses(for: fabric).first ?? "未使用"
    }
    /// 多状态：使用和出售可同时存在，如 ["使用中", "部分出售"]。
    /// 完全售出（剩余 0）时独占"已出售"。
    func statuses(for fabric: Fabric) -> [String] {
        let sold = soldLength(for: fabric.id)
        let rem = remaining(for: fabric)
        let used = fabric.usedLength
        if sold > 0 && fabric.hasPurchaseLength && rem == 0 { return ["已出售"] }
        var result: [String] = []
        if fabric.hasPurchaseLength && rem == 0 && used > 0 && sold == 0 {
            result.append("已用完")
        } else if used > 0 {
            result.append("使用中")
        }
        if sold > 0 { result.append("部分出售") }
        if result.isEmpty { result.append("未使用") }
        return result
    }
    func works(for fabricId: UUID) -> [Work] {
        works.filter { $0.materials.contains { $0.fabricId == fabricId } }
    }
    /// V9.1：布料关联的成品（聚合，去重）：成品用料直接关联的 +
    /// 各条使用/消耗记录里关联的成品。详情页"关联成品"项的计数与列表都走这里。
    func aggregatedWorks(for fabricId: UUID) -> [Work] {
        var seen = Set<UUID>()
        var result: [Work] = []
        for work in works(for: fabricId) {
            if seen.insert(work.id).inserted { result.append(work) }
        }
        for record in usageRecords(for: fabricId) {
            for wid in record.workIds {
                if seen.insert(wid).inserted, let work = work(for: wid) {
                    result.append(work)
                }
            }
        }
        return result
    }
    /// V9.1：出售记录页的状态胶囊（只看出售口径）：已售罄/部分出售/未出售。
    func saleStatus(for fabric: Fabric) -> String {
        let sold = soldLength(for: fabric.id)
        guard sold > 0 else { return "未出售" }
        if fabric.hasPurchaseLength && remaining(for: fabric) == 0 { return "已出售" }
        return "部分出售"
    }
    func workCost(for work: Work) -> (total: Double, hasMissingPrice: Bool) {
        var total = 0.0; var missing = false
        for m in work.materials {
            guard let fabric = fabric(for: m.fabricId) else { continue }
            if let unit = fabric.unitPrice {
                total += m.amount * unit
            } else {
                missing = true
            }
        }
        return (total, missing)
    }
    /// V8：成品总成本 = 用料成本合计 + 工费（工费未填则不计入）。
    func workTotalCost(for work: Work) -> Double {
        let (mat, _) = workCost(for: work)
        return mat + (work.hasLaborCost ? work.laborCost : 0)
    }
    var totalValue: Double { fabrics.filter { $0.hasTotalPrice }.reduce(0) { $0 + $1.purchasePrice } }
    var totalMeters: Double { fabrics.filter { $0.hasPurchaseLength }.reduce(0) { $0 + $1.length } }
    var totalConsumed: Double { fabrics.reduce(0) { $0 + $1.usedLength } }
    var totalSoldMeters: Double { saleRecords.filter { !$0.isPieces }.reduce(0) { $0 + $1.length } }
    var totalRemaining: Double { max(0, totalMeters - totalConsumed - totalSoldMeters) }
    // 售出块数：有出售记录的布料去重数（长度出售与份数出售都计入一块布料），售出米数只计长度出售。
    var soldPieceCount: Int { Set(saleRecords.map { $0.fabricId }).count }
    var soldRevenue: Double { saleRecords.reduce(0) { $0 + $1.price } }
    func lastSaleDate(for fabricId: UUID) -> Date? { saleRecords(for: fabricId).first?.date }

    // MARK: - ID 查询

    func material(for id: UUID?) -> Material? {
        guard let id else { return nil }
        return materials.first { $0.id == id }
    }
    func channel(for id: UUID?) -> Channel? {
        guard let id else { return nil }
        return channels.first { $0.id == id }
    }
    func tags(for fabric: Fabric) -> [Tag] {
        let wanted = Set(fabric.tagIds)
        return tags.filter { wanted.contains($0.id) }.sorted { $0.sortOrder < $1.sortOrder }
    }
    func usageRecords(for fabricId: UUID) -> [UsageRecord] {
        usageRecords.filter { $0.fabricId == fabricId }.sorted { $0.date > $1.date }
    }
    func fabric(for id: UUID) -> Fabric? { fabrics.first { $0.id == id } }
    func work(for id: UUID) -> Work? { works.first { $0.id == id } }

    // MARK: - 新增 / 删除

    func addTag(_ tag: Tag) { tags.append(tag); save() }
    func addMaterial(_ material: Material) { materials.append(material); save() }
    func addChannel(_ channel: Channel) { channels.append(channel); save() }
    func addFabric(_ fabric: Fabric) { fabrics.append(fabric); save() }
    func addUsageRecord(_ record: UsageRecord) { usageRecords.append(record); save() }
    func addSaleRecord(_ record: SaleRecord) { saleRecords.append(record); save() }
    func addWork(_ work: Work) { works.append(work); save() }
    func addPattern(_ pattern: Pattern) { patterns.append(pattern); save() }
    func addItem(_ item: Item) { items.append(item); save() }
    func addOtherItem(_ item: OtherItem) { otherItems.append(item); save() }
    func addWishlistItem(_ item: WishlistItem) { wishlistItems.append(item); save() }
    func addBrainstorm(_ b: Brainstorm) { brainstorms.append(b); save() }

    func brainstorms(forFabric id: UUID) -> [Brainstorm] {
        brainstorms.filter { $0.linkedFabricIds.contains(id) }.sorted { $0.createdAt > $1.createdAt }
    }
    func brainstorms(forWork id: UUID) -> [Brainstorm] {
        brainstorms.filter { $0.linkedWorkIds.contains(id) }.sorted { $0.createdAt > $1.createdAt }
    }
    func brainstorms(forOther id: UUID) -> [Brainstorm] {
        brainstorms.filter { $0.linkedOtherIds.contains(id) }.sorted { $0.createdAt > $1.createdAt }
    }
    func deleteBrainstorm(_ b: Brainstorm) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-images") {
            for name in b.imageFileNames { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        }
        brainstorms.removeAll { $0.id == b.id }; save()
    }

    func deleteTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        for fabric in fabrics { fabric.tagIds.removeAll { $0 == tag.id } }
        save()
    }
    func deleteMaterial(_ material: Material) {
        materials.removeAll { $0.id == material.id }
        for fabric in fabrics where fabric.materialId == material.id { fabric.materialId = nil }
        save()
    }
    func deleteChannel(_ channel: Channel) {
        channels.removeAll { $0.id == channel.id }
        for fabric in fabrics where fabric.channelId == channel.id { fabric.channelId = nil }
        save()
    }
    func codeConflict(code: String, excluding fabricId: UUID, ownedSubCodes: Set<String> = []) -> (fabric: Fabric, code: String)? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for fabric in fabrics where fabric.id != fabricId {
            if fabric.code == trimmed { return (fabric, trimmed) }
            if fabric.subCodes.contains(trimmed) {
                // 自己拥有的子编号，被关联的布料也持有它（链接），不算冲突，否则关联后永远无法保存。
                if ownedSubCodes.contains(trimmed) { continue }
                return (fabric, trimmed)
            }
        }
        return nil
    }
    /// 颜色默认值迁移到图2的13色（2026-10-31）：旧版12色（含茶/其他）替换为新13色，
    /// 用户自定义的颜色（不在旧默认值里的）保留并追加到末尾。
    private func migrateColorDefaults() {
        guard let level = codeLevels.first(where: { $0.kind == "color" }) else { return }
        let newNames = Set(Self.defaultColorItems().map { $0.name })
        // 如果已经是新13色（名称完全匹配），不处理
        let currentNames = Set(level.items.map { $0.name })
        if currentNames == newNames { return }
        // 保留自定义项（不在新默认值里的）
        let customs = level.items.filter { !newNames.contains($0.name) }
        level.items = Self.defaultColorItems() + customs
        save()
    }
    /// 确保颜色层级末尾有固定的"其他"项（2026-10-31）：rainbow图标，不可删除（UI层隐藏删除键）。
    private func ensureFixedOtherColor() {
        guard let level = codeLevels.first(where: { $0.kind == "color" }) else { return }
        // 已有名为"其他"的项：确保图标为rainbow（旧版可能是wheel或emoji）
        if let other = level.items.first(where: { $0.name == "其他" }) {
            if other.icon != "rainbow" { other.icon = "rainbow" }
            // 移到末尾
            level.items.removeAll { $0.id == other.id }
            level.items.append(other)
            save()
            return
        }
        // 没有：追加
        level.items.append(CodeItem(name: "其他", code: "Q", icon: "rainbow"))
        save()
    }
    // 旧 nextCode（Build #12 颜色+纹样生成器）已被 V8 编号体系取代，
    // 生成逻辑见本文件 MARK: - 编号体系（V8）与 FabricViews 的新生成表。
    func deleteFabric(_ fabric: Fabric) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-images") {
            for name in fabric.imageFileNames {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }
        }
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-videos") {
            for name in fabric.videoFileNames { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        }
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-images") {
            for record in saleRecords where record.fabricId == fabric.id {
                for name in record.imageFileNames { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
            }
        }
        fabrics.removeAll { $0.id == fabric.id }
        usageRecords.removeAll { $0.fabricId == fabric.id }
        saleRecords.removeAll { $0.fabricId == fabric.id }
        for work in works { work.materials.removeAll { $0.fabricId == fabric.id } }
        save()
    }
    func deleteUsageRecord(_ record: UsageRecord) {
        usageRecords.removeAll { $0.id == record.id }
        save()
    }
    func deleteSaleRecord(_ record: SaleRecord) {
        saleRecords.removeAll { $0.id == record.id }
        save()
    }
    func deleteWork(_ work: Work) { works.removeAll { $0.id == work.id }; save() }
    func deletePattern(_ pattern: Pattern) { patterns.removeAll { $0.id == pattern.id }; save() }
    func deleteItem(_ item: Item) { items.removeAll { $0.id == item.id }; save() }
    func deleteOtherItem(_ item: OtherItem) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-images") {
            for name in item.imageFileNames { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        }
        otherItems.removeAll { $0.id == item.id }; save()
    }
    func deleteWishlistItem(_ item: WishlistItem) {
        if let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-images") {
            for name in item.imageFileNames { try? FileManager.default.removeItem(at: dir.appendingPathComponent(name)) }
        }
        wishlistItems.removeAll { $0.id == item.id }; save()
    }
    func clearRecords() {
        fabrics.removeAll(); usageRecords.removeAll(); saleRecords.removeAll()
        works.removeAll(); patterns.removeAll(); items.removeAll()
        otherItems.removeAll(); wishlistItems.removeAll(); save()
    }
    // 使用记录写入（V3：记录 + 剩余同步扣减，消耗合计 = usedLength 保持一致）
    func addUsageAndDeduct(_ record: UsageRecord) {
        if let fabric = fabric(for: record.fabricId) {
            fabric.usedLength += record.length
            fabric.updatedAt = Date()
        }
        usageRecords.append(record); save()
    }
    func removeUsageAndRestore(_ record: UsageRecord) {
        if let fabric = fabric(for: record.fabricId) {
            fabric.usedLength = max(0, fabric.usedLength - record.length)
            fabric.updatedAt = Date()
        }
        usageRecords.removeAll { $0.id == record.id }; save()
    }
}
