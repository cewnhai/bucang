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
        createdAt: Date = Date(), updatedAt: Date = Date(),
        materialId: UUID? = nil, channelId: UUID? = nil, tagIds: [UUID] = [],
        imageFileNames: [String] = [],
        code: String = "", materialName: String = "", composition: String = "",
        colorName: String = "", weightGsm: Double? = nil, shrinkagePct: Double? = nil,
        washing: [String] = [], usageNotes: String = "", channelName: String = "",
        merchantName: String = "", brainstorm: String = "", subCodes: [String] = [],
        videoFileNames: [String] = [],
        hasTotalPrice: Bool = true, hasPurchaseLength: Bool = true
    ) {
        self.id = id; self.name = name; self.length = length; self.width = width
        self.purchasePrice = purchasePrice; self.pricePerMeter = pricePerMeter
        self.purchaseDate = purchaseDate; self.usedLength = usedLength
        self.isFavorite = isFavorite; self.status = status; self.note = note
        self.createdAt = createdAt; self.updatedAt = updatedAt
        self.materialId = materialId; self.channelId = channelId; self.tagIds = tagIds
        self.imageFileNames = imageFileNames; self.code = code; self.materialName = materialName
        self.composition = composition; self.colorName = colorName; self.weightGsm = weightGsm
        self.shrinkagePct = shrinkagePct; self.washing = washing; self.usageNotes = usageNotes
        self.channelName = channelName; self.merchantName = merchantName
        self.brainstorm = brainstorm; self.subCodes = subCodes
        self.videoFileNames = videoFileNames; self.hasTotalPrice = hasTotalPrice
        self.hasPurchaseLength = hasPurchaseLength
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, length, width, purchasePrice, pricePerMeter, purchaseDate
        case usedLength, isFavorite, status, note, createdAt, updatedAt
        case materialId, channelId, tagIds, imageFileNames
        case code, materialName, composition, colorName, weightGsm, shrinkagePct
        case washing, usageNotes, channelName, merchantName, brainstorm, subCodes, videoFileNames
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
    var isFinished: Bool { finishedAt != nil }
    init(
        id: UUID = UUID(), name: String = "", progress: Double = 0,
        startedAt: Date? = nil, finishedAt: Date? = nil,
        costPrice: Double = 0, sellPrice: Double = 0, timeHours: Double = 0,
        note: String = "", createdAt: Date = Date(),
        imageFileNames: [String] = [], materials: [WorkMaterial] = [],
        isSold: Bool = false, salePrice: Double = 0, hasSalePrice: Bool = false,
        saleDate: Date? = nil, saleChannel: String = "", isUsed: Bool = false, usageCount: Int = 0
    ) {
        self.id = id; self.name = name; self.progress = progress
        self.startedAt = startedAt; self.finishedAt = finishedAt
        self.costPrice = costPrice; self.sellPrice = sellPrice; self.timeHours = timeHours
        self.note = note; self.createdAt = createdAt
        self.imageFileNames = imageFileNames; self.materials = materials
        self.isSold = isSold; self.salePrice = salePrice; self.hasSalePrice = hasSalePrice
        self.saleDate = saleDate; self.saleChannel = saleChannel; self.isUsed = isUsed; self.usageCount = usageCount
    }
    private enum CodingKeys: String, CodingKey {
        case id, name, progress, startedAt, finishedAt, costPrice, sellPrice, timeHours, note, createdAt, imageFileNames, materials
        case isSold, salePrice, hasSalePrice, saleDate, saleChannel, isUsed, usageCount
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
    init(id: UUID = UUID(), name: String = "", imageFileNames: [String] = [], note: String = "", createdAt: Date = Date()) {
        self.id = id; self.name = name; self.imageFileNames = imageFileNames; self.note = note; self.createdAt = createdAt
    }
    private enum CodingKeys: String, CodingKey { case id, name, imageFileNames, note, createdAt }
    required init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        imageFileNames = try c.decodeIfPresent([String].self, forKey: .imageFileNames) ?? []
        note = try c.decodeIfPresent(String.self, forKey: .note) ?? ""
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(imageFileNames, forKey: .imageFileNames); try c.encode(note, forKey: .note)
        try c.encode(createdAt, forKey: .createdAt)
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
    var materialOptions: [String] = []
    var otherCategories: [String] = []
    var lengthUnit: String = "米"
    var hideAmounts: Bool = false
    var codePrefix: String = ""
    var channelOptions: [String] = []
    var patternOptions: [String] = []
    var visibleTabs: [String] = []
    var themeName: String = "深蓝"
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
    @Published var materialOptions: [String] = []
    @Published var otherCategories: [String] = []
    @Published var lengthUnit: String = "米"
    @Published var hideAmounts: Bool = false
    @Published var codePrefix: String = ""
    @Published var channelOptions: [String] = []
    @Published var patternOptions: [String] = []
    @Published var visibleTabs: [String] = []
    @Published var themeName: String = "深蓝"

    static let defaultMaterialOptions = ["棉", "麻", "丝", "毛", "化纤", "混纺", "针织", "其他"]
    static let defaultOtherCategories = ["其他"]
    static let defaultChannelOptions = ["淘宝", "闲鱼", "小红书"]
    static let defaultPatternOptions = ["素色", "提花", "印花", "格纹", "条纹", "碎花", "暗花", "缎面"]
    static let allTabKeys = ["fabric", "work", "other", "wishlist"]

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
        materialOptions = decoded.materialOptions.isEmpty ? Self.defaultMaterialOptions : decoded.materialOptions
        otherCategories = decoded.otherCategories.isEmpty ? Self.defaultOtherCategories : decoded.otherCategories
        lengthUnit = ["米", "厘米", "码"].contains(decoded.lengthUnit) ? decoded.lengthUnit : "米"
        hideAmounts = decoded.hideAmounts; codePrefix = decoded.codePrefix
        channelOptions = decoded.channelOptions.isEmpty ? Self.defaultChannelOptions : decoded.channelOptions
        patternOptions = decoded.patternOptions.isEmpty ? Self.defaultPatternOptions : decoded.patternOptions
        visibleTabs = decoded.visibleTabs.isEmpty ? Self.allTabKeys : decoded.visibleTabs.filter { Self.allTabKeys.contains($0) }
        if !visibleTabs.contains("fabric") { visibleTabs.insert("fabric", at: 0) }
        themeName = decoded.themeName.isEmpty ? "深蓝" : decoded.themeName
        normalizeLegacyFabrics()
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
        for name in channels.map({ $0.name }) where !name.isEmpty && !channelOptions.contains(name) {
            channelOptions.append(name)
        }
        for fabric in fabrics where !fabric.channelName.isEmpty && !channelOptions.contains(fabric.channelName) {
            channelOptions.append(fabric.channelName)
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
            materialOptions: materialOptions, otherCategories: otherCategories,
            lengthUnit: lengthUnit, hideAmounts: hideAmounts, codePrefix: codePrefix,
            channelOptions: channelOptions, patternOptions: patternOptions,
            visibleTabs: visibleTabs, themeName: themeName
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
        let sold = soldLength(for: fabric.id)
        let rem = remaining(for: fabric)
        if sold > 0 && fabric.hasPurchaseLength && rem == 0 { return "已出售" }
        if fabric.hasPurchaseLength && rem == 0 && fabric.usedLength > 0 { return "已用完" }
        if fabric.usedLength > 0 { return "使用中" }
        return "未使用"
    }
    func works(for fabricId: UUID) -> [Work] {
        works.filter { $0.materials.contains { $0.fabricId == fabricId } }
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
    func codeConflict(code: String, excluding fabricId: UUID) -> (fabric: Fabric, code: String)? {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        for fabric in fabrics where fabric.id != fabricId {
            if fabric.code == trimmed { return (fabric, trimmed) }
            if fabric.subCodes.contains(trimmed) { return (fabric, trimmed) }
        }
        return nil
    }
    // 多级编号：[前缀-]颜色-纹样-001[-自定义备注]，序号按颜色+纹样组合独立递增。
    func nextCode(color: String, pattern: String, customSuffix: String) -> String {
        let prefix = codePrefix.trimmingCharacters(in: .whitespacesAndNewlines)
        var maxSeq = 0
        let allCodes = fabrics.flatMap { [$0.code] + $0.subCodes }
        for code in allCodes {
            let parts = code.split(separator: "-").map(String.init)
            let seqIndex: Int?
            if !prefix.isEmpty && parts.count >= 4 && parts[0] == prefix && parts[1] == color && parts[2] == pattern {
                seqIndex = 3
            } else if prefix.isEmpty && parts.count >= 3 && parts[0] == color && parts[1] == pattern {
                seqIndex = 2
            } else { seqIndex = nil }
            if let idx = seqIndex, let n = Int(parts[idx]) { maxSeq = max(maxSeq, n) }
        }
        var seq = maxSeq + 1
        while true {
            let base = prefix.isEmpty ? "\(color)-\(pattern)-\(String(format: "%03d", seq))" : "\(prefix)-\(color)-\(pattern)-\(String(format: "%03d", seq))"
            let suffix = customSuffix.trimmingCharacters(in: .whitespacesAndNewlines)
            let candidate = suffix.isEmpty ? base : "\(base)-\(suffix)"
            if codeConflict(code: candidate, excluding: UUID()) == nil { return candidate }
            seq += 1
        }
    }
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
