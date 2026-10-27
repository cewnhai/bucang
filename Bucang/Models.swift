import Foundation
import SwiftData

// MARK: - 字典：标签 / 材质 / 渠道

@Model
final class Tag {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class Material {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

@Model
final class Channel {
    @Attribute(.unique) var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

// MARK: - 布料

@Model
final class Fabric {
    @Attribute(.unique) var id: UUID
    var name: String
    var length: Double
    var width: Double
    var purchasePrice: Double
    var pricePerMeter: Double
    var purchaseDate: Date
    var usedLength: Double
    var isFavorite: Bool
    var status: Int
    var note: String
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .nullify) var material: Material?
    @Relationship(deleteRule: .nullify) var channel: Channel?
    @Relationship(deleteRule: .nullify) var tags: [Tag] = []
    @Relationship(deleteRule: .cascade, inverse: \UsageRecord.fabric) var usageRecords: [UsageRecord] = []

    var remainingLength: Double {
        max(0, length - usedLength)
    }

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名布料" : name
    }

    init(
        id: UUID = UUID(),
        name: String = "",
        length: Double = 0,
        width: Double = 0,
        purchasePrice: Double = 0,
        pricePerMeter: Double = 0,
        purchaseDate: Date = Date(),
        usedLength: Double = 0,
        isFavorite: Bool = false,
        status: Int = 0,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.length = length
        self.width = width
        self.purchasePrice = purchasePrice
        self.pricePerMeter = pricePerMeter
        self.purchaseDate = purchaseDate
        self.usedLength = usedLength
        self.isFavorite = isFavorite
        self.status = status
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - 使用记录

@Model
final class UsageRecord {
    @Attribute(.unique) var id: UUID
    var date: Date
    var length: Double
    var note: String

    @Relationship(inverse: \Fabric.usageRecords) var fabric: Fabric?

    init(id: UUID = UUID(), date: Date = Date(), length: Double = 0, note: String = "", fabric: Fabric? = nil) {
        self.id = id
        self.date = date
        self.length = length
        self.note = note
        self.fabric = fabric
    }
}

// MARK: - 作品 / 纸样 / 物品（第一版为基础记录，暂不做关联布料自动算成本）

@Model
final class Work {
    @Attribute(.unique) var id: UUID
    var name: String
    var progress: Double
    var startedAt: Date?
    var finishedAt: Date?
    var costPrice: Double
    var sellPrice: Double
    var timeHours: Double
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        progress: Double = 0,
        startedAt: Date? = nil,
        finishedAt: Date? = nil,
        costPrice: Double = 0,
        sellPrice: Double = 0,
        timeHours: Double = 0,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.progress = progress
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.costPrice = costPrice
        self.sellPrice = sellPrice
        self.timeHours = timeHours
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class Pattern {
    @Attribute(.unique) var id: UUID
    var name: String
    var price: Double
    var pieceCount: Int
    var sizeDesc: String
    var purchasedAt: Date?
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        price: Double = 0,
        pieceCount: Int = 0,
        sizeDesc: String = "",
        purchasedAt: Date? = nil,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.pieceCount = pieceCount
        self.sizeDesc = sizeDesc
        self.purchasedAt = purchasedAt
        self.note = note
        self.createdAt = createdAt
    }
}

@Model
final class Item {
    @Attribute(.unique) var id: UUID
    var name: String
    var price: Double
    var quantity: Int
    var sizeDesc: String
    var purchasedAt: Date?
    var note: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String = "",
        price: Double = 0,
        quantity: Int = 0,
        sizeDesc: String = "",
        purchasedAt: Date? = nil,
        note: String = "",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.price = price
        self.quantity = quantity
        self.sizeDesc = sizeDesc
        self.purchasedAt = purchasedAt
        self.note = note
        self.createdAt = createdAt
    }
}
