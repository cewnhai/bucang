import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - V3 布仓主页：底部导航左项，顶部四 Tab + 吸顶统计卡 + 工具行 + 状态胶囊
// 统计卡与顶栏、工具行都在列表滚动区域之外（固定不动），符合“吸顶”要求。
// 统计卡按原型：深蓝底白字，左“切到出库/入库”，中 N 份布料，右图表 + 展开收起。

enum BucangTab: String, CaseIterable, Identifiable {
    case fabric, work, other, wishlist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fabric: return "布料"
        case .work: return "成品"
        case .other: return "其他"
        case .wishlist: return "心愿单"
        }
    }
}

enum FabricViewMode: CaseIterable {
    case list, grid, horizontal
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        case .horizontal: return "rectangle.split.2x1"
        }
    }
    var label: String {
        switch self {
        case .list: return "上下滑动"
        case .grid: return "左右两列"
        case .horizontal: return "左右滑动"
        }
    }
}

enum FabricStatusFilter: String, CaseIterable, Identifiable {
    case all, favorite, unused, inUse, usedUp, sold
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .favorite: return "收藏"
        case .unused: return "未使用"
        case .inUse: return "使用中"
        case .usedUp: return "已用完"
        case .sold: return "已出售"
        }
    }
}

enum FabricSortMethod: String, CaseIterable, Identifiable {
    case purchaseDate, saleDate, price, length, code
    var id: String { rawValue }
    var title: String {
        switch self {
        case .purchaseDate: return "购买时间"
        case .saleDate: return "出售时间"
        case .price: return "价格"
        case .length: return "米数"
        case .code: return "编号"
        }
    }
}

struct BucangView: View {
    @EnvironmentObject private var store: Store
    @State private var tab: BucangTab = .fabric
    @State private var showOutbound = false
    @State private var statsExpanded = true
    @State private var hideAmounts: Bool = false
    @State private var searchText = ""
    @State private var viewMode: FabricViewMode = .list
    @State private var statusFilter: FabricStatusFilter = .all
    @State private var sortMethod: FabricSortMethod = .purchaseDate
    @State private var sortAscending = false
    @State private var filterMaterials: Set<String> = []
    @State private var filterColors: Set<String> = []
    @State private var filterTagIDs: Set<UUID> = []
    @State private var filterChannels: Set<String> = []
    @State private var showingFilter = false
    @State private var showingSort = false
    @State private var showingImportExport = false
    @State private var showingSimilar = false
    @State private var showingAddFabric = false
    @State private var showingWishlistPicker = false
    @State private var convertedFabric: Fabric?
    @State private var showingConvertedEdit = false
    @State private var usageFabric: Fabric?
    @State private var showingUsage = false
    @State private var showingWishlistAdd = false

    private var filteredFabrics: [Fabric] {
        var list = store.fabrics
        switch statusFilter {
        case .all: break
        case .favorite: list = list.filter { $0.isFavorite }
        case .unused: list = list.filter { store.status(for: $0) == "未使用" }
        case .inUse: list = list.filter { store.status(for: $0) == "使用中" }
        case .usedUp: list = list.filter { store.status(for: $0) == "已用完" }
        case .sold: list = list.filter { store.status(for: $0) == "已出售" }
        }
        if !filterMaterials.isEmpty { list = list.filter { filterMaterials.contains($0.materialName) } }
        if !filterColors.isEmpty { list = list.filter { filterColors.contains($0.colorName) } }
        if !filterTagIDs.isEmpty { list = list.filter { !$0.tagIds.filter { filterTagIDs.contains($0) }.isEmpty } }
        if !filterChannels.isEmpty { list = list.filter { filterChannels.contains($0.channelName) } }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            list = list.filter { fabric in
                let tagNames = store.tags(for: fabric).map { $0.name }.joined(separator: " ")
                return fabric.name.localizedCaseInsensitiveContains(keyword)
                    || fabric.code.localizedCaseInsensitiveContains(keyword)
                    || fabric.materialName.localizedCaseInsensitiveContains(keyword)
                    || fabric.composition.localizedCaseInsensitiveContains(keyword)
                    || fabric.colorName.localizedCaseInsensitiveContains(keyword)
                    || tagNames.localizedCaseInsensitiveContains(keyword)
                    || fabric.channelName.localizedCaseInsensitiveContains(keyword)
                    || fabric.usageNotes.localizedCaseInsensitiveContains(keyword)
                    || fabric.note.localizedCaseInsensitiveContains(keyword)
            }
        }
        let sorted: [Fabric]
        switch sortMethod {
        case .purchaseDate: sorted = list.sorted { $0.purchaseDate > $1.purchaseDate }
        case .saleDate: sorted = list.sorted { (store.lastSaleDate(for: $0.id) ?? Date.distantPast) > (store.lastSaleDate(for: $1.id) ?? Date.distantPast) }
        case .price: sorted = list.sorted { $0.purchasePrice > $1.purchasePrice }
        case .length: sorted = list.sorted { $0.length > $1.length }
        case .code: sorted = list.sorted { $0.code < $1.code }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    private var hasActiveFilter: Bool {
        !filterMaterials.isEmpty || !filterColors.isEmpty || !filterTagIDs.isEmpty || !filterChannels.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶栏
                HStack(spacing: 0) {
                    ForEach(BucangTab.allCases) { t in
                        Button(action: { tab = t }) {
                            VStack(spacing: 4) {
                                HStack(spacing: 2) {
                                    Text(t.title)
                                        .fontWeight(tab == t ? .bold : .regular)
                                        .foregroundColor(tab == t ? .primary : .secondary)
                                    if t == .wishlist && !store.wishlistItems.isEmpty {
                                        Text("\(store.wishlistItems.count)")
                                            .font(.caption2).fontWeight(.bold)
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6).padding(.vertical, 2)
                                            .background(Color.orange)
                                            .cornerRadius(10)
                                    }
                                }
                                Rectangle()
                                    .fill(tab == t ? Design.accent : Color.clear)
                                    .frame(height: 2)
                            }
                        }
                        .buttonStyle(.plain)
                        .frame(maxWidth: .infinity)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .background(Design.background)

                if tab == .fabric {
                    // 统计卡（深蓝，白字，浅深色都可读）
                    VStack(spacing: 10) {
                        HStack {
                            Button(action: { showOutbound.toggle() }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.left.arrow.right")
                                    Text(showOutbound ? "切到入库" : "切到出库")
                                }
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                            Spacer()
                            Text("\(store.fabrics.count) 份布料")
                                .font(.headline).fontWeight(.bold).foregroundColor(.white)
                            Spacer()
                            HStack(spacing: 12) {
                                NavigationLink(destination: ChartsView()) {
                                    Image(systemName: "chart.bar").foregroundColor(.white)
                                }
                                Button(action: { statsExpanded.toggle() }) {
                                    Image(systemName: statsExpanded ? "chevron.up" : "chevron.down").foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        if statsExpanded {
                            if showOutbound {
                                HStack(spacing: 0) {
                                    statColumn(label: "售出块数", value: "\(store.soldPieceCount)")
                                    Divider().frame(height: 36).background(Color.white.opacity(0.4))
                                    statColumn(label: "售出米数", value: "\(LengthUnitHelper.format(store.totalSoldMeters, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                    Divider().frame(height: 36).background(Color.white.opacity(0.4))
                                    statColumn(label: "售出回款", value: hideAmounts ? "****" : "¥\(String(format: "%.2f", store.soldRevenue))")
                                }
                            } else {
                                HStack(spacing: 0) {
                                    VStack(spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text("总价值").font(.caption).foregroundColor(.white.opacity(0.85))
                                            Button(action: { hideAmounts.toggle() }) {
                                                Image(systemName: hideAmounts ? "eye.slash" : "eye").font(.caption).foregroundColor(.white)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                        Text(hideAmounts ? "****" : "¥\(String(format: "%.2f", store.totalValue))")
                                            .font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                                    }
                                    .frame(maxWidth: .infinity)
                                    Divider().frame(height: 36).background(Color.white.opacity(0.4))
                                    statColumn(label: "总米数", value: "\(LengthUnitHelper.format(store.totalMeters, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                    Divider().frame(height: 36).background(Color.white.opacity(0.4))
                                    statColumn(label: "消耗米数", value: "\(LengthUnitHelper.format(store.totalConsumed, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                    Divider().frame(height: 36).background(Color.white.opacity(0.4))
                                    statColumn(label: "剩余米数", value: "\(LengthUnitHelper.format(store.totalRemaining, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Design.accent)
                    .cornerRadius(Design.corner)
                    .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // 工具行
                    HStack(spacing: 8) {
                        HStack(spacing: 6) {
                            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                            TextField("搜名称 / 编号 / 材质 / 颜色…", text: $searchText)
                            if !searchText.isEmpty {
                                Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                                    .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 10).padding(.vertical, 8)
                        .background(Design.card)
                        .cornerRadius(12)
                        Button(action: { showingSimilar = true }) {
                            Image(systemName: "camera").foregroundColor(Design.accent)
                                .frame(width: 36, height: 36).background(Design.card).cornerRadius(10)
                        }
                        .buttonStyle(.plain)
                        toolbarButton(icon: viewMode.icon, action: {
                            if let next = FabricViewMode.allCases.first(where: { $0 != viewMode }) {
                                // 循环切换：列表 -> 网格 -> 横向 -> 列表
                                switch viewMode {
                                case .list: viewMode = .grid
                                case .grid: viewMode = .horizontal
                                case .horizontal: viewMode = .list
                                }
                                _ = next
                            }
                        })
                        toolbarButton(icon: "line.3.horizontal.decrease.circle", action: { showingFilter = true })
                        toolbarButton(icon: "arrow.up.arrow.down", action: { showingSort = true })
                        toolbarButton(icon: "square.and.arrow.down", action: { showingImportExport = true })
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 10)

                    // 状态胶囊
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FabricStatusFilter.allCases) { status in
                                ChipButton(title: status.title, selected: statusFilter == status) {
                                    statusFilter = status
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                    if hasActiveFilter {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                Text("已选：").font(.caption).foregroundColor(.secondary)
                                ForEach(Array(filterMaterials), id: \.self) { value in
                                    filterChip(label: "材质：\(value)", clear: { filterMaterials.remove(value) })
                                }
                                ForEach(Array(filterColors), id: \.self) { value in
                                    filterChip(label: "颜色：\(value)", clear: { filterColors.remove(value) })
                                }
                                ForEach(Array(filterTagIDs), id: \.self) { id in
                                    if let tag = store.tags.first(where: { $0.id == id }) {
                                        filterChip(label: "标签：\(tag.name)", clear: { filterTagIDs.remove(id) })
                                    }
                                }
                                ForEach(Array(filterChannels), id: \.self) { value in
                                    filterChip(label: "渠道：\(value)", clear: { filterChannels.remove(value) })
                                }
                                Button("清除全部") {
                                    filterMaterials.removeAll(); filterColors.removeAll(); filterTagIDs.removeAll(); filterChannels.removeAll()
                                }
                                .font(.caption)
                            }
                            .padding(.horizontal, 16)
                        }
                        .padding(.bottom, 4)
                    }
                }

                // 内容区
                Group {
                    switch tab {
                    case .fabric:
                        fabricContent
                    case .work:
                        WorksListView()
                    case .other:
                        OtherListView()
                    case .wishlist:
                        WishlistListView()
                    }
                }
            }
            .background(Design.background)
            .navigationTitle("布仓")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { hideAmounts = store.hideAmounts }
            .sheet(isPresented: $showingFilter) {
                NavigationStack {
                    FilterPanelView(
                        filterMaterials: $filterMaterials, filterColors: $filterColors,
                        filterTagIDs: $filterTagIDs, filterChannels: $filterChannels
                    )
                }
            }
            .sheet(isPresented: $showingSort) {
                NavigationStack {
                    Form {
                        Section("排序方式") {
                            ForEach(FabricSortMethod.allCases) { method in
                                Button(action: { sortMethod = method }) {
                                    HStack { Text(method.title); Spacer(); if sortMethod == method { Image(systemName: "checkmark") } }
                                }
                                .foregroundColor(.primary)
                            }
                        }
                        Section("顺序") {
                            Picker("顺序", selection: $sortAscending) {
                                Text("降序").tag(false)
                                Text("升序").tag(true)
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    .navigationTitle("排序")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showingSort = false } } }
                }
            }
            .sheet(isPresented: $showingImportExport) { NavigationStack { ImportExportSheetView() } }
            .sheet(isPresented: $showingSimilar) { NavigationStack { SimilarSearchView() } }
            .sheet(isPresented: $showingAddFabric) { NavigationStack { FabricEditView(fabric: nil) } }
            .sheet(isPresented: $showingWishlistPicker) { NavigationStack { WishlistPickerView(onPick: convertWishlist) } }
            .sheet(isPresented: $showingConvertedEdit) {
                if let convertedFabric {
                    NavigationStack { FabricEditView(fabric: convertedFabric) }
                }
            }
            .sheet(isPresented: $showingUsage) {
                if let usageFabric {
                    NavigationStack { UsageFormView(fabric: usageFabric) }
                }
            }
            .sheet(isPresented: $showingWishlistAdd) {
                NavigationStack { WishlistEditView(item: nil, presetName: searchText) }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if tab == .fabric {
                // 长按 = 从心愿单转入库，点按 = 新增布料；不用 Button 包手势，
                // 避免 Button 的点击抢走长按手势。
                Circle()
                    .fill(Design.accent)
                    .frame(width: 56, height: 56)
                    .overlay(Image(systemName: "plus").foregroundColor(.white).font(.title2))
                    .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                    .onTapGesture { showingAddFabric = true }
                    .onLongPressGesture { showingWishlistPicker = true }
            }
        }
    }

    private func convertWishlist(_ item: WishlistItem) {
        let fabric = Fabric(name: item.name, note: item.note, imageFileNames: item.imageFileNames)
        // 心愿单照片文件已在 bucang-images/，新布料直接复用文件名，不复制字节。
        store.addFabric(fabric)
        convertedFabric = fabric
        showingWishlistPicker = false
        showingConvertedEdit = true
    }

    private func toolbarButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .foregroundColor(.primary)
                .frame(width: 36, height: 36)
                .background(Design.card)
                .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }

    private func statColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func filterChip(label: String, clear: @escaping () -> Void) -> some View {
        Button(action: clear) {
            HStack(spacing: 4) {
                Text(label).font(.caption)
                Image(systemName: "xmark").font(.caption2)
            }
            .foregroundColor(Design.accent)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Design.accentSoft)
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var fabricContent: some View {
        Group {
            if filteredFabrics.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("家里没有匹配的布，可以买")
                            .font(.headline)
                        Button("加入心愿单") { showingWishlistAdd = true }
                            .buttonStyle(.borderedProminent).tint(Design.accent)
                    } else {
                        EmptyPlaceholderView(icon: "scissors", title: "还没有布料", subtitle: "点右下 + 新增，或去设置里导入原数据")
                    }
                    Spacer()
                }
                .padding()
            } else {
                switch viewMode {
                case .list:
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(filteredFabrics) { fabric in
                                NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                                    FabricCardView(fabric: fabric, onAddUsage: {
                                        usageFabric = fabric; showingUsage = true
                                    })
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.bottom, 80)
                    }
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            ForEach(filteredFabrics) { fabric in
                                NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                                    FabricCardView(fabric: fabric, onAddUsage: {
                                        usageFabric = fabric; showingUsage = true
                                    }, compact: true)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .padding(.bottom, 80)
                    }
                case .horizontal:
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(filteredFabrics) { fabric in
                                NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                                    FabricCardView(fabric: fabric, onAddUsage: {
                                        usageFabric = fabric; showingUsage = true
                                    })
                                    .frame(width: 280)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}

struct FilterPanelView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var filterMaterials: Set<String>
    @Binding var filterColors: Set<String>
    @Binding var filterTagIDs: Set<UUID>
    @Binding var filterChannels: Set<String>

    private var channels: [String] {
        Array(Set(store.fabrics.map { $0.channelName }.filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        List {
            Section("材质") {
                ForEach(store.materialOptions, id: \.self) { option in
                    Button(action: {
                        if filterMaterials.contains(option) { filterMaterials.remove(option) } else { filterMaterials.insert(option) }
                    }) {
                        HStack { Text(option); Spacer(); if filterMaterials.contains(option) { Image(systemName: "checkmark") } }
                    }
                    .foregroundColor(.primary)
                }
            }
            Section("颜色") {
                ForEach(FabricColors.all) { option in
                    Button(action: {
                        if filterColors.contains(option.name) { filterColors.remove(option.name) } else { filterColors.insert(option.name) }
                    }) {
                        HStack {
                            Circle().fill(option.color).frame(width: 20, height: 20)
                                .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 1))
                            Text(option.name)
                            Spacer()
                            if filterColors.contains(option.name) { Image(systemName: "checkmark") }
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
            Section("标签") {
                if store.tags.isEmpty { Text("还没有标签").foregroundColor(.secondary) }
                else {
                    ForEach(store.tags.sorted { $0.sortOrder < $1.sortOrder }) { tag in
                        Button(action: {
                            if filterTagIDs.contains(tag.id) { filterTagIDs.remove(tag.id) } else { filterTagIDs.insert(tag.id) }
                        }) {
                            HStack { Text(tag.name); Spacer(); if filterTagIDs.contains(tag.id) { Image(systemName: "checkmark") } }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            Section("渠道") {
                if channels.isEmpty { Text("还没有渠道").foregroundColor(.secondary) }
                else {
                    ForEach(channels, id: \.self) { channel in
                        Button(action: {
                            if filterChannels.contains(channel) { filterChannels.remove(channel) } else { filterChannels.insert(channel) }
                        }) {
                            HStack { Text(channel); Spacer(); if filterChannels.contains(channel) { Image(systemName: "checkmark") } }
                        }
                        .foregroundColor(.primary)
                    }
                }
            }
            Section {
                Button("清除全部筛选条件", role: .destructive) {
                    filterMaterials.removeAll(); filterColors.removeAll(); filterTagIDs.removeAll(); filterChannels.removeAll()
                }
            }
        }
        .navigationTitle("筛选")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}

struct WishlistPickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var onPick: (WishlistItem) -> Void
    var body: some View {
        List {
            if store.wishlistItems.isEmpty {
                Text("心愿单是空的，先在心愿单页加一条").foregroundColor(.secondary)
            } else {
                ForEach(store.wishlistItems) { item in
                    Button(action: { onPick(item) }) {
                        HStack {
                            Text(item.name.isEmpty ? "未命名心愿" : item.name)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                    .foregroundColor(.primary)
                }
            }
        }
        .navigationTitle("从心愿单转入库")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
    }
}
