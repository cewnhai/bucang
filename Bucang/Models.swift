import Foundation

// MARK: - 字典：标签 / 材质 / 渠道
// iOS 16 本地存储：纯 Codable 类，不用旧数据框架。
// 关系只存 ID，不存对象引用，避免循环引用和 iOS 17 依赖。

final class Tag: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

final class Material: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

final class Channel: Identifiable, Codable {
    var id: UUID
    var name: String
    var sortOrder: Int

    init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
        self.id = id
        self.name = name
        self.sortOrder = sortOrder
    }
}

// MARK: - 布料

final class Fabric: Identifiable, Codable {
    var id: UUID
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

    // 只存 ID，不存对象引用。
    var materialId: UUID?
    var channelId: UUID?
    var tagIds: [UUID]

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
        updatedAt: Date = Date(),
        materialId: UUID? = nil,
        channelId: UUID? = nil,
        tagIds: [UUID] = []
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
        self.materialId = materialId
        self.channelId = channelId
        self.tagIds = tagIds
    }
}

// MARK: - 使用记录

final class UsageRecord: Identifiable, Codable {
    var id: UUID
    var date: Date
    var length: Double
    var note: String
    // 只存布料 ID，不存 Fabric 对象引用。
    var fabricId: UUID

    init(id: UUID = UUID(), date: Date = Date(), length: Double = 0, note: String = "", fabricId: UUID) {
        self.id = id
        self.date = date
        self.length = length
        self.note = note
        self.fabricId = fabricId
    }
}

// MARK: - 作品 / 纸样 / 物品（第一版为基础记录，暂不做关联布料自动算成本）

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

final class Pattern: Identifiable, Codable {
    var id: UUID
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

final class Item: Identifiable, Codable {
    var id: UUID
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

// MARK: - 本地存储：Documents/bucang-store.json

struct StoreData: Codable {
    var tags: [Tag] = []
    var materials: [Material] = []
    var channels: [Channel] = []
    var fabrics: [Fabric] = []
    var usageRecords: [UsageRecord] = []
    var works: [Work] = []
    var patterns: [Pattern] = []
    var items: [Item] = []
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

    init() {
        load()
    }

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("bucang-store.json")
    }

    private func load() {
        guard let url = fileURL,
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StoreData.self, from: data) else {
            return
        }
        tags = decoded.tags
        materials = decoded.materials
        channels = decoded.channels
        fabrics = decoded.fabrics
        usageRecords = decoded.usageRecords
        works = decoded.works
        patterns = decoded.patterns
        items = decoded.items
    }

    /// 每次数据变化后调用：先通知界面刷新（模型是类，直接改属性不会自动触发
    /// @Published），再把整份数据写回 JSON 文件。
    func save() {
        objectWillChange.send()
        guard let url = fileURL else { return }
        let data = StoreData(
            tags: tags, materials: materials, channels: channels,
            fabrics: fabrics, usageRecords: usageRecords,
            works: works, patterns: patterns, items: items
        )
        if let encoded = try? JSONEncoder().encode(data) {
            try? encoded.write(to: url, options: .atomic)
        }
    }

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
        return tags.filter { wanted.contains($0.id) }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    func usageRecords(for fabricId: UUID) -> [UsageRecord] {
        usageRecords.filter { $0.fabricId == fabricId }
            .sorted { $0.date > $1.date }
    }

    func fabric(for id: UUID) -> Fabric? {
        fabrics.first { $0.id == id }
    }

    // MARK: - 新增

    func addTag(_ tag: Tag) { tags.append(tag); save() }
    func addMaterial(_ material: Material) { materials.append(material); save() }
    func addChannel(_ channel: Channel) { channels.append(channel); save() }
    func addFabric(_ fabric: Fabric) { fabrics.append(fabric); save() }
    func addUsageRecord(_ record: UsageRecord) { usageRecords.append(record); save() }
    func addWork(_ work: Work) { works.append(work); save() }
    func addPattern(_ pattern: Pattern) { patterns.append(pattern); save() }
    func addItem(_ item: Item) { items.append(item); save() }

    // MARK: - 删除（布料删除连带使用记录；字典删除把引用置空/剔除）

    func deleteTag(_ tag: Tag) {
        tags.removeAll { $0.id == tag.id }
        for fabric in fabrics {
            fabric.tagIds.removeAll { $0 == tag.id }
        }
        save()
    }

    func deleteMaterial(_ material: Material) {
        materials.removeAll { $0.id == material.id }
        for fabric in fabrics where fabric.materialId == material.id {
            fabric.materialId = nil
        }
        save()
    }

    func deleteChannel(_ channel: Channel) {
        channels.removeAll { $0.id == channel.id }
        for fabric in fabrics where fabric.channelId == channel.id {
            fabric.channelId = nil
        }
        save()
    }

    func deleteFabric(_ fabric: Fabric) {
        fabrics.removeAll { $0.id == fabric.id }
        usageRecords.removeAll { $0.fabricId == fabric.id }
        save()
    }

    func deleteUsageRecord(_ record: UsageRecord) {
        usageRecords.removeAll { $0.id == record.id }
        save()
    }

    func deleteWork(_ work: Work) {
        works.removeAll { $0.id == work.id }
        save()
    }

    func deletePattern(_ pattern: Pattern) {
        patterns.removeAll { $0.id == pattern.id }
        save()
    }

    func deleteItem(_ item: Item) {
        items.removeAll { $0.id == item.id }
        save()
    }

    /// 清空：按原代码行为，只清布料（含连带使用记录）、作品、纸样、物品，
    /// 字典（标签/材质/渠道）保留，以便重新导入时还能复用。
    func clearRecords() {
        fabrics.removeAll()
        usageRecords.removeAll()
        works.removeAll()
        patterns.removeAll()
        items.removeAll()
        save()
    }
}
