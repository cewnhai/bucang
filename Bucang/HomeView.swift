import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

// MARK: - V8 布仓主页：底部导航左项，顶部五 Tab + 吸顶统计卡 + 工具行 + 状态胶囊
// 吸顶方案（iOS 16 安全）：顶栏一级 Tab 固定在 VStack 顶部，不随列表滚动；
// 各 Tab 的统计卡做成 LazyVStack(pinnedViews: [.sectionHeaders]) 的 Section header，
// 随列表滚动吸顶固定在 Tab 栏正下方；工具行、状态胶囊、筛选 chips 随内容一起滚动。
// 布料 Tab 默认两列，可切整宽单列；脑洞 Tab（V8 新增）结构同理，自带统计卡。

enum BucangTab: String, CaseIterable, Identifiable {
    case fabric, work, brainstorm, other, wishlist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fabric: return "布料"
        case .work: return "成品"
        case .brainstorm: return "脑洞"
        case .other: return "其他"
        case .wishlist: return "心愿单"
        }
    }
}

// V8：只剩两态 —— 两列（默认） ⇄ 整宽单列。横向 1.5 卡模式已移除。
enum FabricViewMode: CaseIterable {
    case list, grid
    var icon: String {
        switch self {
        case .list: return "list.bullet"
        case .grid: return "square.grid.2x2"
        }
    }
    var label: String {
        switch self {
        case .list: return "整宽单列"
        case .grid: return "两列"
        }
    }
}

// V8 七级状态：rawValue 直接取 Store.statusCapsules 的中文名，
// 过滤时用 store.status(for:) == rawValue 比较；收藏单独按 isFavorite。
enum FabricStatusFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case favorite = "收藏"
    case unused = "未使用"
    case using = "使用中"
    case usedUp = "已用完"
    case partSold = "部分出售"
    case sold = "已出售"
    var id: String { rawValue }
    var title: String { rawValue }
}

enum FabricSortMethod: String, CaseIterable, Identifiable {
    case purchaseDate, saleDate, price, length, code, createdAt
    var id: String { rawValue }
    var title: String {
        switch self {
        case .purchaseDate: return "购买时间"
        case .saleDate: return "出售时间"
        case .price: return "价格"
        case .length: return "米数"
        case .code: return "编号"
        case .createdAt: return "创建时间"
        }
    }
}

// MARK: - 脑洞转成品（详情页与表单共用）：
// 新建 Work（标题→名称，内容→备注），把新成品 id 追加进 linkedWorkIds，
// 状态置 已立项，记录 convertedWorkId；已转过则直接返回。
private func brainstormConvertToWork(store: Store, brainstorm: Brainstorm) {
    guard brainstorm.convertedWorkId == nil else { return }
    let work = Work(name: brainstorm.title, note: brainstorm.content)
    store.addWork(work)
    if !brainstorm.linkedWorkIds.contains(work.id) { brainstorm.linkedWorkIds.append(work.id) }
    brainstorm.status = "已立项"
    brainstorm.convertedWorkId = work.id
    store.save()
}

struct BucangView: View {
    @EnvironmentObject private var store: Store
    @State private var tab: BucangTab = .fabric
    @State private var showOutbound = false
    @State private var statsExpanded = true
    @State private var hideAmounts: Bool = false
    @State private var searchText = ""
    @State private var viewMode: FabricViewMode = .grid
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
    @State private var showingTabSelection = false
    @State private var saleFabric: Fabric?
    @State private var showingSale = false
    @State private var showingUsageDetail = false
    @State private var showingSaleFlow = false
    private var visibleTabs: [BucangTab] {
        let keys = store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs
        var list = BucangTab.allCases.filter { keys.contains($0.rawValue) }
        if !list.contains(.fabric) { list.insert(.fabric, at: 0) }
        return list
    }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var filteredFabrics: [Fabric] {
        var list = store.fabrics
        switch statusFilter {
        case .all: break
        case .favorite: list = list.filter { $0.isFavorite }
        case .unused, .using, .usedUp, .partSold, .sold:
            list = list.filter { store.status(for: $0) == statusFilter.rawValue }
        }
        if !filterMaterials.isEmpty { list = list.filter { filterMaterials.contains($0.materialName) } }
        if !filterColors.isEmpty { list = list.filter { filterColors.contains($0.colorName) } }
        if !filterTagIDs.isEmpty { list = list.filter { !$0.tagIds.filter { filterTagIDs.contains($0) }.isEmpty } }
        if !filterChannels.isEmpty { list = list.filter { filterChannels.contains($0.channelName) } }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !keyword.isEmpty {
            list = list.filter { fabric in
                let tagNames = store.tags(for: fabric).map { $0.name }.joined(separator: " ")
                let workNames = store.works(for: fabric.id).map { $0.name }.joined(separator: " ")
                return fabric.name.localizedCaseInsensitiveContains(keyword)
                    || fabric.code.localizedCaseInsensitiveContains(keyword)
                    || fabric.subCodes.joined(separator: " ").localizedCaseInsensitiveContains(keyword)
                    || fabric.materialName.localizedCaseInsensitiveContains(keyword)
                    || fabric.composition.localizedCaseInsensitiveContains(keyword)
                    || fabric.colorName.localizedCaseInsensitiveContains(keyword)
                    || tagNames.localizedCaseInsensitiveContains(keyword)
                    || fabric.channelName.localizedCaseInsensitiveContains(keyword)
                    || fabric.merchantName.localizedCaseInsensitiveContains(keyword)
                    || fabric.usageNotes.localizedCaseInsensitiveContains(keyword)
                    || fabric.brainstorm.localizedCaseInsensitiveContains(keyword)
                    || fabric.note.localizedCaseInsensitiveContains(keyword)
                    || workNames.localizedCaseInsensitiveContains(keyword)
            }
        }
        let sorted: [Fabric]
        switch sortMethod {
        case .purchaseDate: sorted = list.sorted { ($0.purchaseDate ?? Date.distantPast) > ($1.purchaseDate ?? Date.distantPast) }
        case .saleDate: sorted = list.sorted { (store.lastSaleDate(for: $0.id) ?? Date.distantPast) > (store.lastSaleDate(for: $1.id) ?? Date.distantPast) }
        case .price: sorted = list.sorted { $0.purchasePrice > $1.purchasePrice }
        case .length: sorted = list.sorted { $0.length > $1.length }
        case .code: sorted = list.sorted { store.hierarchicalCompare($0, $1) == .orderedAscending }
        case .createdAt: sorted = list.sorted { $0.createdAt > $1.createdAt }
        }
        return sortAscending ? sorted.reversed() : sorted
    }

    private var hasActiveFilter: Bool {
        !filterMaterials.isEmpty || !filterColors.isEmpty || !filterTagIDs.isEmpty || !filterChannels.isEmpty
    }

    private var partSoldCount: Int {
        store.fabrics.filter { store.status(for: $0) == "部分出售" }.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 顶栏一级 Tab：固定在顶部，不随列表滚动（只显示设置里开启的，布料始终显示）。
                tabBar
                // 内容区：各 Tab 自己的滚动视图；布料/脑洞的统计卡在各自滚动区内吸顶。
                Group {
                    switch tab {
                    case .fabric:
                        fabricTabView
                    case .work:
                        WorksListView()
                    case .brainstorm:
                        BrainstormListView()
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
            .sheet(isPresented: $showingTabSelection) {
                NavigationStack {
                    Form {
                        Section {
                            ForEach(BucangTab.allCases) { t in
                                if t == .fabric {
                                    HStack { Text(t.title); Spacer(); Text("始终显示").font(.caption).foregroundColor(.secondary) }
                                } else {
                                    Toggle(t.title, isOn: Binding(
                                        get: { (store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs).contains(t.rawValue) },
                                        set: { on in
                                            var keys = store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs
                                            if on { if !keys.contains(t.rawValue) { keys.append(t.rawValue) } }
                                            else { keys.removeAll { $0 == t.rawValue } }
                                            if !keys.contains("fabric") { keys.insert("fabric", at: 0) }
                                            store.visibleTabs = Store.allTabKeys.filter { keys.contains($0) }
                                            if !store.visibleTabs.contains(tab.rawValue) { tab = .fabric }
                                            store.save()
                                        }
                                    ))
                                }
                            }
                        } header: {
                            Text("顶栏显示")
                        } footer: {
                            Text("布料是主 Tab，始终固定显示，不可关闭；若当前选中的 Tab 被隐藏，会自动切回布料。")
                        }
                    }
                    .navigationTitle("顶栏")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { showingTabSelection = false } } }
                }
            }
            .sheet(isPresented: $showingSale) {
                if let saleFabric {
                    NavigationStack { SaleFormView(fabric: saleFabric) }
                }
            }
            .sheet(isPresented: $showingUsageDetail) { NavigationStack { UsageDetailSheetView() } }
            .sheet(isPresented: $showingSaleFlow) { NavigationStack { SaleFlowSheetView() } }
            .onChange(of: store.visibleTabs) { keys in
                if !keys.isEmpty && !keys.contains(tab.rawValue) { tab = .fabric }
            }
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
                    .fill(themeAccent)
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

    // MARK: - 顶栏 Tab（固定，不滚动）

    private var tabBar: some View {
        HStack(spacing: 0) {
            ForEach(visibleTabs) { t in
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
                            .fill(tab == t ? themeAccent : Color.clear)
                            .frame(height: 2)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
            }
            Button(action: { showingTabSelection = true }) {
                Image(systemName: "ellipsis").foregroundColor(.secondary).padding(.horizontal, 4)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .background(Design.background)
    }

    // MARK: - 布料 Tab：统计卡吸顶 + 内容滚动

    private var fabricTabView: some View {
        ScrollView {
            LazyVStack(pinnedViews: [.sectionHeaders], spacing: 0) {
                Section {
                    fabricToolbar
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    statusCapsuleRow
                    if hasActiveFilter {
                        activeFilterRow
                            .padding(.bottom, 4)
                    }
                    fabricCards
                } header: {
                    // 统计卡吸顶：固定在 Tab 栏正下方，内容从卡片下面滚过。
                    fabricStatsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .background(Design.background)
                }
            }
        }
    }

    private var fabricStatsCard: some View {
        VStack(spacing: 10) {
            HStack {
                Button(action: { showOutbound.toggle() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                        Text(showOutbound ? "入库" : "出库")
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
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            statColumn(label: "售出块数", value: "\(store.soldPieceCount)")
                            Divider().frame(height: 36).background(Color.white.opacity(0.4))
                            statColumn(label: "售出米数", value: "\(LengthUnitHelper.format(store.totalSoldMeters, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                            Divider().frame(height: 36).background(Color.white.opacity(0.4))
                            statColumn(label: "售出回款", value: hideAmounts ? "****" : "¥\(String(format: "%.2f", store.soldRevenue))", valueColor: Design.priceAccent)
                        }
                        if store.totalMeters > 0 {
                            Text("已售出占比 \(String(format: "%.1f", store.totalSoldMeters / store.totalMeters * 100))%")
                                .font(.caption).foregroundColor(.white.opacity(0.85))
                        }
                        Button(action: { showingSaleFlow = true }) {
                            Text("出售记录流水")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Color.white.opacity(0.2))
                                .cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        if store.soldPiecesTotal() > 0 {
                            Text("另有份数出售 \(store.soldPiecesTotal()) 份（不计入售出米数，不扣剩余长度）")
                                .font(.caption).foregroundColor(.white.opacity(0.85))
                        }
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
                                .font(.subheadline).fontWeight(.bold).foregroundColor(Design.priceAccent).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        statColumn(label: "总米数", value: "\(LengthUnitHelper.format(store.totalMeters, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        VStack(spacing: 2) {
                            HStack(spacing: 4) {
                                Text("消耗米数").font(.caption).foregroundColor(.white.opacity(0.85))
                                Button(action: { showingUsageDetail = true }) {
                                    Image(systemName: "arrow.left").font(.caption).foregroundColor(.white)
                                }
                                .buttonStyle(.plain)
                            }
                            Text("\(LengthUnitHelper.format(store.totalConsumed, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .frame(maxWidth: .infinity)
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        statColumn(label: "剩余米数", value: "\(LengthUnitHelper.format(store.totalRemaining, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                    }
                }
            }
        }
        .padding(14)
        .background(ThemeStatsBackground(themeName: store.themeName))
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private var fabricToolbar: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜名称 / 编号 / 材质 / 颜色 / 成品…", text: $searchText)
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
            // 两列 ⇄ 整宽单列：按钮显示点按后要切换到的模式图标。
            toolbarButton(icon: viewMode == .grid ? "list.bullet" : "square.grid.2x2", action: {
                viewMode = viewMode == .grid ? .list : .grid
            })
            toolbarButton(icon: "line.3.horizontal.decrease.circle", action: { showingFilter = true })
            toolbarButton(icon: "arrow.up.arrow.down", action: { showingSort = true })
            toolbarButton(icon: "square.and.arrow.down", action: { showingImportExport = true })
        }
    }

    private var statusCapsuleRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FabricStatusFilter.allCases) { status in
                    ChipButton(
                        title: status == .partSold ? "部分出售 (\(partSoldCount))" : status.title,
                        selected: statusFilter == status,
                        accent: themeAccent
                    ) {
                        statusFilter = status
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }

    private var activeFilterRow: some View {
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
    }

    private var fabricCards: some View {
        Group {
            if filteredFabrics.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    if !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("家里没有匹配的布，可以买")
                            .font(.headline)
                        Button("加入心愿单") { showingWishlistAdd = true }
                            .buttonStyle(.borderedProminent).tint(Design.accent)
                    } else {
                        EmptyPlaceholderView(icon: "scissors", title: "还没有布料", subtitle: "点右下 + 新增，或去设置里导入原数据")
                    }
                    Spacer(minLength: 40)
                }
                .padding()
            } else if viewMode == .list {
                LazyVStack(spacing: 12) {
                    ForEach(filteredFabrics) { fabric in
                        NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                            FabricCardView(fabric: fabric, onAddUsage: {
                                usageFabric = fabric; showingUsage = true
                            }, onAddSale: {
                                saleFabric = fabric; showingSale = true
                            })
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(filteredFabrics) { fabric in
                        NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                            FabricCardView(fabric: fabric, onAddUsage: {
                                usageFabric = fabric; showingUsage = true
                            }, onAddSale: {
                                saleFabric = fabric; showingSale = true
                            }, compact: true)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 80)
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

    private func statColumn(label: String, value: String, valueColor: Color = .white) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(valueColor).lineLimit(1).minimumScaleFactor(0.7)
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
}

struct FilterPanelView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    @Binding var filterMaterials: Set<String>
    @Binding var filterColors: Set<String>
    @Binding var filterTagIDs: Set<UUID>
    @Binding var filterChannels: Set<String>

    private var channels: [String] {
        // 设置渠道选项 + 数据里已有但不在选项里的渠道名（旧数据仍可筛选）。
        let fromOptions = store.channelOptions
        let fromData = store.fabrics.map { $0.channelName }.filter { !$0.isEmpty }
        let fromSales = store.saleRecords.map { $0.channel }.filter { !$0.isEmpty }
        return Array(Set(fromOptions + fromData + fromSales)).sorted()
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

// MARK: - 消耗明细（统计卡“消耗米数”旁的左箭头打开）：全部使用记录，时间倒序。
struct UsageDetailSheetView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    private var records: [UsageRecord] {
        store.usageRecords.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            if records.isEmpty {
                Text("还没有使用记录").foregroundColor(.secondary)
            } else {
                ForEach(records) { record in
                    let fabric = store.fabric(for: record.fabricId)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fabric?.displayName ?? "已删除布料")
                                .font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Text("\(LengthUnitHelper.format(record.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        HStack {
                            if let code = fabric?.code, !code.isEmpty {
                                Text(code).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text(CSVValues.dateFormatter.string(from: record.date))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if !record.note.isEmpty {
                            Text(record.note).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("消耗明细")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}

// MARK: - 出售记录流水（统计卡出库视图的按钮打开）：全部出售记录，时间倒序。
// 长度出售显示长度，份数出售显示「{n}份」。
struct SaleFlowSheetView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    private var records: [SaleRecord] {
        store.saleRecords.sorted { $0.date > $1.date }
    }
    var body: some View {
        List {
            if records.isEmpty {
                Text("还没有出售记录").foregroundColor(.secondary)
            } else {
                ForEach(records) { record in
                    let fabric = store.fabric(for: record.fabricId)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(fabric?.displayName ?? "已删除布料")
                                .font(.subheadline).fontWeight(.semibold)
                            Spacer()
                            Text(record.isPieces
                                 ? "\(record.pieces)份"
                                 : "\(LengthUnitHelper.format(record.length, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))")
                                .font(.subheadline).fontWeight(.semibold)
                        }
                        HStack {
                            if let code = fabric?.code, !code.isEmpty {
                                Text(code).font(.caption).foregroundColor(.secondary)
                            }
                            if !record.channel.isEmpty {
                                Text(record.channel).font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("¥\(String(format: "%.2f", record.price))")
                                .font(.caption).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                            Text(CSVValues.dateFormatter.string(from: record.date))
                                .font(.caption).foregroundColor(.secondary)
                        }
                        if !record.note.isEmpty {
                            Text(record.note).font(.caption).foregroundColor(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("出售记录流水")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("完成") { dismiss() } } }
    }
}

// MARK: - 脑洞 Tab（V8 新增）

struct BrainstormListView: View {
    @EnvironmentObject private var store: Store
    @State private var searchText = ""
    @State private var viewMode: FabricViewMode = .grid
    @State private var showingAddForm = false
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var filtered: [Brainstorm] {
        let list = store.brainstorms.sorted { $0.createdAt > $1.createdAt }
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return list }
        return list.filter {
            $0.title.localizedCaseInsensitiveContains(keyword)
                || $0.content.localizedCaseInsensitiveContains(keyword)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(pinnedViews: [.sectionHeaders], spacing: 0) {
                Section {
                    searchRow
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                    cardsSection
                } header: {
                    // 脑洞统计卡同样吸顶，固定在 Tab 栏正下方。
                    brainstormStatsCard
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 6)
                        .background(Design.background)
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(themeAccent)
                .frame(width: 56, height: 56)
                .overlay(Image(systemName: "plus").foregroundColor(.white).font(.title2))
                .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 4)
                .padding(.trailing, 20)
                .padding(.bottom, 20)
                .onTapGesture { showingAddForm = true }
        }
        .sheet(isPresented: $showingAddForm) {
            NavigationStack { BrainstormFormView(brainstorm: nil) }
        }
    }

    private var brainstormStatsCard: some View {
        let total = store.brainstorms.count
        let thinking = store.brainstorms.filter { $0.status == "想法中" }.count
        let approved = store.brainstorms.filter { $0.status == "已立项" }.count
        let dropped = store.brainstorms.filter { $0.status == "已放弃" }.count
        return VStack(spacing: 10) {
            HStack {
                Text("脑洞灵感")
                    .font(.headline).fontWeight(.bold).foregroundColor(.white)
                Spacer()
                Text("\(total) 条想法")
                    .font(.subheadline).foregroundColor(.white.opacity(0.85))
            }
            HStack(spacing: 0) {
                bsStatColumn(label: "想法数", value: "\(total)")
                Divider().frame(height: 36).background(Color.white.opacity(0.4))
                bsStatColumn(label: "想法中", value: "\(thinking)")
                Divider().frame(height: 36).background(Color.white.opacity(0.4))
                bsStatColumn(label: "已立项", value: "\(approved)")
                Divider().frame(height: 36).background(Color.white.opacity(0.4))
                bsStatColumn(label: "已放弃", value: "\(dropped)")
            }
        }
        .padding(14)
        .background(ThemeStatsBackground(themeName: store.themeName))
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
    }

    private func bsStatColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("搜标题 / 灵感内容…", text: $searchText)
                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) { Image(systemName: "xmark.circle.fill").foregroundColor(.secondary) }
                        .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Design.card)
            .cornerRadius(12)
            // 两列 ⇄ 整宽：按钮显示点按后要切换到的模式图标。
            Button(action: { viewMode = viewMode == .grid ? .list : .grid }) {
                Image(systemName: viewMode == .grid ? "list.bullet" : "square.grid.2x2")
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Design.card)
                    .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private var cardsSection: some View {
        Group {
            if filtered.isEmpty {
                VStack(spacing: 12) {
                    Spacer(minLength: 40)
                    EmptyPlaceholderView(icon: "lightbulb", title: "还没有脑洞", subtitle: "点右下 + 把灵感记下来，可关联布料 / 成品 / 其他")
                    Spacer(minLength: 40)
                }
                .padding()
            } else if viewMode == .list {
                LazyVStack(spacing: 12) {
                    ForEach(filtered) { brainstorm in
                        NavigationLink(destination: BrainstormDetailView(brainstorm: brainstorm)) {
                            BrainstormCardView(brainstorm: brainstorm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    ForEach(filtered) { brainstorm in
                        NavigationLink(destination: BrainstormDetailView(brainstorm: brainstorm)) {
                            BrainstormCardView(brainstorm: brainstorm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
        .padding(.bottom, 80)
    }
}

struct BrainstormCardView: View {
    @EnvironmentObject private var store: Store
    var brainstorm: Brainstorm

    private var statusColor: Color {
        switch brainstorm.status {
        case "已立项": return Color.green
        case "已放弃": return Color.gray
        default: return Color.orange
        }
    }

    private func linkCapsules() -> [String] {
        var out: [String] = []
        for id in brainstorm.linkedFabricIds {
            if let fabric = store.fabric(for: id) {
                let code = fabric.code.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append("布料·" + (code.isEmpty ? "未命名" : code))
            }
        }
        for id in brainstorm.linkedWorkIds {
            if let work = store.work(for: id) {
                let name = work.name.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append("成品·" + (name.isEmpty ? "未命名" : name))
            }
        }
        for id in brainstorm.linkedOtherIds {
            if let other = store.otherItems.first(where: { $0.id == id }) {
                let name = other.name.trimmingCharacters(in: .whitespacesAndNewlines)
                out.append("其他·" + (name.isEmpty ? "未命名" : name))
            }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(brainstorm.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名脑洞" : brainstorm.title)
                    .font(.headline).lineLimit(1)
                Spacer()
                Text(brainstorm.status)
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColor)
                    .cornerRadius(10)
            }
            let summary = String(brainstorm.content.prefix(60))
            if !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(summary)
                    .font(.subheadline).foregroundColor(.secondary).lineLimit(2)
            }
            let capsules = linkCapsules()
            if !capsules.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(capsules, id: \.self) { capsule in
                            Text(capsule)
                                .font(.caption)
                                .foregroundColor(Design.accent)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .background(Design.accentSoft)
                                .cornerRadius(10)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Design.card)
        .cornerRadius(Design.smallCorner)
    }
}

struct BrainstormDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var brainstorm: Brainstorm
    @State private var showingEdit = false
    @State private var showingDeleteConfirm = false
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var statusColor: Color {
        switch brainstorm.status {
        case "已立项": return Color.green
        case "已放弃": return Color.gray
        default: return Color.orange
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(brainstorm.status)
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .background(statusColor)
                        .cornerRadius(12)
                    Spacer()
                    Text(CSVValues.dateFormatter.string(from: brainstorm.createdAt))
                        .font(.caption).foregroundColor(.secondary)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("灵感内容").font(.headline)
                    if brainstorm.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("暂无内容").font(.subheadline).foregroundColor(.secondary)
                    } else {
                        Text(brainstorm.content).font(.subheadline)
                    }
                }
                if !brainstorm.imageFileNames.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("参考图").font(.headline)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                            ForEach(brainstorm.imageFileNames, id: \.self) { name in
                                if let uiImage = FabricImageStore.loadImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(minWidth: 0, maxWidth: .infinity)
                                        .aspectRatio(1, contentMode: .fill)
                                        .clipped()
                                        .cornerRadius(8)
                                }
                            }
                        }
                    }
                }
                linkedSection
                VStack(spacing: 10) {
                    if brainstorm.convertedWorkId == nil {
                        Button(action: { brainstormConvertToWork(store: store, brainstorm: brainstorm) }) {
                            Label("转成品", systemImage: "hammer")
                                .font(.headline).foregroundColor(.white)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(themeAccent).cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(action: {}) {
                            Label("已转成品", systemImage: "checkmark.circle")
                                .font(.headline).foregroundColor(.secondary)
                                .frame(maxWidth: .infinity).padding(.vertical, 12)
                                .background(Color.gray.opacity(0.15)).cornerRadius(12)
                        }
                        .buttonStyle(.plain)
                        .disabled(true)
                    }
                    Button(role: .destructive, action: { showingDeleteConfirm = true }) {
                        Label("删除脑洞", systemImage: "trash")
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle(brainstorm.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "脑洞详情" : brainstorm.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("编辑") { showingEdit = true }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { BrainstormFormView(brainstorm: brainstorm) }
        }
        .alert("删除这个脑洞？参考图会一起删除，已关联的成品不受影响。", isPresented: $showingDeleteConfirm) {
            Button("删除", role: .destructive) {
                store.deleteBrainstorm(brainstorm)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        }
    }

    private var linkedSection: some View {
        let fabrics = brainstorm.linkedFabricIds.compactMap { store.fabric(for: $0) }
        let works = brainstorm.linkedWorkIds.compactMap { store.work(for: $0) }
        let others = brainstorm.linkedOtherIds.compactMap { id in store.otherItems.first { $0.id == id } }
        return VStack(alignment: .leading, spacing: 8) {
            Text("关联明细").font(.headline)
            if fabrics.isEmpty && works.isEmpty && others.isEmpty {
                Text("暂无关联").font(.subheadline).foregroundColor(.secondary)
            } else {
                ForEach(fabrics) { fabric in
                    NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                        linkedRow(icon: "scissors", title: fabric.displayName, sub: fabric.code)
                    }
                    .buttonStyle(.plain)
                }
                ForEach(works) { work in
                    linkedRow(icon: "hammer", title: work.name.isEmpty ? "未命名成品" : work.name, sub: "")
                }
                ForEach(others) { other in
                    linkedRow(icon: "tag", title: other.name.isEmpty ? "未命名" : other.name, sub: other.category)
                }
            }
        }
    }

    private func linkedRow(icon: String, title: String, sub: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundColor(Design.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline).foregroundColor(.primary)
                if !sub.isEmpty {
                    Text(sub).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(Design.card)
        .cornerRadius(Design.smallCorner)
    }
}

struct BrainstormFormView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var brainstorm: Brainstorm?

    @State private var title: String
    @State private var content: String
    @State private var imageNames: [String]
    @State private var selFabrics: Set<UUID>
    @State private var selWorks: Set<UUID>
    @State private var selOthers: Set<UUID>
    @State private var statusSel: String
    @State private var photoItems: [PhotosPickerItem] = []

    init(brainstorm: Brainstorm?) {
        self.brainstorm = brainstorm
        _title = State(initialValue: brainstorm?.title ?? "")
        _content = State(initialValue: brainstorm?.content ?? "")
        _imageNames = State(initialValue: brainstorm?.imageFileNames ?? [])
        _selFabrics = State(initialValue: Set(brainstorm?.linkedFabricIds ?? []))
        _selWorks = State(initialValue: Set(brainstorm?.linkedWorkIds ?? []))
        _selOthers = State(initialValue: Set(brainstorm?.linkedOtherIds ?? []))
        _statusSel = State(initialValue: brainstorm?.status ?? "想法中")
    }

    private var isNew: Bool { brainstorm == nil }
    private var canSave: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        Form {
            Section("标题") {
                TextField("给这个想法起个标题", text: $title)
            }
            Section("灵感内容") {
                TextEditor(text: $content)
                    .frame(minHeight: 120)
            }
            Section("参考图") {
                photoEditor
            }
            Section("关联明细") {
                NavigationLink(destination: BrainstormLinkPickerView(
                    title: "关联布料",
                    options: store.fabrics.map { (id: $0.id, label: $0.displayName, sub: $0.code) },
                    selection: $selFabrics
                )) {
                    linkRowLabel(title: "布料", count: selFabrics.count)
                }
                NavigationLink(destination: BrainstormLinkPickerView(
                    title: "关联成品",
                    options: store.works.map { (id: $0.id, label: $0.name.isEmpty ? "未命名成品" : $0.name, sub: "") },
                    selection: $selWorks
                )) {
                    linkRowLabel(title: "成品", count: selWorks.count)
                }
                NavigationLink(destination: BrainstormLinkPickerView(
                    title: "关联其他",
                    options: store.otherItems.map { (id: $0.id, label: $0.name.isEmpty ? "未命名" : $0.name, sub: $0.category) },
                    selection: $selOthers
                )) {
                    linkRowLabel(title: "其他", count: selOthers.count)
                }
            }
            Section("状态") {
                Picker("状态", selection: $statusSel) {
                    Text("想法中").tag("想法中")
                    Text("已立项").tag("已立项")
                    Text("已放弃").tag("已放弃")
                }
                .pickerStyle(.segmented)
            }
            if let editing = brainstorm {
                Section {
                    if editing.convertedWorkId == nil {
                        Button("转成品") {
                            brainstormConvertToWork(store: store, brainstorm: editing)
                            statusSel = "已立项"
                        }
                    } else {
                        Button("已转成品") {}.disabled(true)
                    }
                } footer: {
                    Text("转为成品后，会在成品页新增一条记录（标题→名称，内容→备注），并自动关联。")
                }
            }
        }
        .navigationTitle(isNew ? "新建脑洞" : "编辑脑洞")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("保存") { saveForm() }.disabled(!canSave)
            }
        }
    }

    private func linkRowLabel(title: String, count: Int) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(count == 0 ? "未选择" : "已选 \(count)").foregroundColor(.secondary)
        }
    }

    private var photoEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !imageNames.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageNames, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let uiImage = FabricImageStore.loadImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 80, height: 80)
                                        .clipped()
                                        .cornerRadius(10)
                                } else {
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 80, height: 80)
                                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                }
                                Button(action: {
                                    imageNames.removeAll { $0 == name }
                                    FabricImageStore.delete(named: name)
                                }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                                .padding(2)
                            }
                        }
                    }
                }
                Text("点右上角 × 删除参考图（文件即时删除）")
                    .font(.caption).foregroundColor(.secondary)
            }
            PhotosPicker(selection: $photoItems, maxSelectionCount: 9, matching: .images, photoLibrary: .shared()) {
                Label("从相册选择参考图", systemImage: "photo.on.rectangle")
            }
            .onChange(of: photoItems) { items in
                guard !items.isEmpty else { return }
                let toLoad = items
                photoItems = []
                Task {
                    for item in toLoad {
                        if let data = try? await item.loadTransferable(type: Data.self),
                           let image = UIImage(data: data),
                           let name = FabricImageStore.saveUIImage(image) {
                            imageNames.append(name)
                        }
                    }
                }
            }
        }
    }

    private func saveForm() {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let editing = brainstorm {
            editing.title = trimmed
            editing.content = content
            editing.imageFileNames = imageNames
            editing.linkedFabricIds = Array(selFabrics)
            editing.linkedWorkIds = Array(selWorks)
            editing.linkedOtherIds = Array(selOthers)
            editing.status = statusSel
            store.save()
        } else {
            let created = Brainstorm(
                title: trimmed, content: content, imageFileNames: imageNames,
                linkedFabricIds: Array(selFabrics), linkedWorkIds: Array(selWorks),
                linkedOtherIds: Array(selOthers), status: statusSel
            )
            store.addBrainstorm(created)
        }
        dismiss()
    }
}

// 通用多选器：脑洞表单里关联布料 / 成品 / 其他用。
struct BrainstormLinkPickerView: View {
    var title: String
    var options: [(id: UUID, label: String, sub: String)]
    @Binding var selection: Set<UUID>

    var body: some View {
        List {
            if options.isEmpty {
                Text("暂无可选").foregroundColor(.secondary)
            } else {
                ForEach(options, id: \.id) { option in
                    Button(action: {
                        if selection.contains(option.id) { selection.remove(option.id) }
                        else { selection.insert(option.id) }
                    }) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label).foregroundColor(.primary)
                                if !option.sub.isEmpty {
                                    Text(option.sub).font(.caption).foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            if selection.contains(option.id) {
                                Image(systemName: "checkmark").foregroundColor(Design.accent)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
