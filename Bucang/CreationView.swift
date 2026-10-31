import SwiftUI

// MARK: - V3 成品 / 其他 / 心愿单列表（嵌在布仓 NavigationStack 里，不自带 NavigationStack）

struct WorksListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var editingWork: Work?
    @State private var addingMaterialWork: Work?
    @State private var showSold = false
    @State private var isSingleColumn = false // 成品页本地二态：两列 ⇄ 整宽单列（无横向）
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var making: [Work] { store.works.filter { !$0.isFinished }.sorted { $0.createdAt > $1.createdAt } }
    private var finished: [Work] { store.works.filter { $0.isFinished }.sorted { $0.createdAt > $1.createdAt } }
    private var soldWorks: [Work] { store.works.filter { $0.isSold } }
    private var usedWorks: [Work] { store.works.filter { $0.isUsed } }
    private var totalCost: Double { store.works.reduce(0) { $0 + store.workTotalCost(for: $1) } }
    private var gridColumns: [GridItem] {
        isSingleColumn
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
    private var totalSoldAmount: Double { soldWorks.reduce(0) { $0 + ($1.hasSalePrice ? $1.salePrice : 0) } }

    private func workStatColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func workRow(_ work: Work) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(work.name.isEmpty ? "未命名成品" : work.name).font(.headline).lineLimit(1)
                Spacer()
                Text(work.isFinished ? "已完成" : "制作中").font(.caption).foregroundColor(work.isFinished ? .green : Design.accent)
            }
            if let start = work.startedAt {
                Text("开始：\(CSVValues.dateString(start))").font(.caption).foregroundColor(.secondary)
            }
            if let finish = work.finishedAt {
                Text("完成：\(CSVValues.dateString(finish))").font(.caption).foregroundColor(.secondary)
            }
            if work.hasLaborCost {
                Text("工费 ¥\(String(format: "%.2f", work.laborCost))")
                    .font(.caption).foregroundColor(.secondary)
            }
            let missingPrice = store.workCost(for: work).hasMissingPrice
            HStack(spacing: 2) {
                Text("总成本").font(.caption).foregroundColor(.secondary)
                Text("¥\(String(format: "%.2f", store.workTotalCost(for: work)))")
                    .font(.caption).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                if missingPrice {
                    Text("（部分布料无单价，未计入）").font(.caption).foregroundColor(.secondary)
                }
            }
            if work.isUsed {
                Text("已使用 \(work.usageCount) 次").font(.caption).foregroundColor(.secondary)
            }
            if work.isSold {
                Text("已售出\(work.hasSalePrice ? " ¥\(String(format: "%.2f", work.salePrice))" : "")\(work.saleDate.map { " · \(CSVValues.dateString($0))" } ?? "")")
                    .font(.caption).foregroundColor(.secondary)
            }
            Button("加用料") { addingMaterialWork = work }
                .font(.caption)
        }
        .padding(12)
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 成品统计栏（粘性在滚动区顶部，类比布料统计卡但更简单）。
                VStack(spacing: 8) {
                    HStack {
                        Picker("成品视图", selection: $showSold) {
                            Text("成品").tag(false)
                            Text("售出").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 100)
                        StatsBigNumberHeader(count: store.works.count, label: "件成品")
                            .padding(.leading, 8)
                        Spacer()
                    }
                    if showSold {
                        HStack(spacing: 0) {
                            workStatColumn(label: "已售出数", value: "\(soldWorks.count)")
                            Divider().frame(height: 36).background(Color.white.opacity(0.4))
                            workStatColumn(label: "总金额", value: "¥\(String(format: "%.2f", totalSoldAmount))")
                        }
                    } else {
                        HStack(spacing: 0) {
                            workStatColumn(label: "成品数", value: "\(store.works.count)")
                            Divider().frame(height: 36).background(Color.white.opacity(0.4))
                            workStatColumn(label: "已使用数", value: "已使用 \(usedWorks.count) 件，共 \(usedWorks.reduce(0) { $0 + $1.usageCount }) 次")
                            Divider().frame(height: 36).background(Color.white.opacity(0.4))
                            workStatColumn(label: "成本金额", value: "¥\(String(format: "%.2f", totalCost))")
                        }
                    }
                }
                .padding(14)
                .background(ThemeStatsBackground(themeName: store.themeName))
                .cornerRadius(Design.corner)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                HStack {
                    Picker("视图", selection: $isSingleColumn) {
                        Text("两列").tag(false)
                        Text("单列").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "制作中")
                    if making.isEmpty { Text("暂无制作中的成品").font(.caption).foregroundColor(.secondary) }
                    else {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(making) { work in
                                Button(action: { editingWork = work }) { workRow(work) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("删除", role: .destructive) { store.deleteWork(work) }
                                    }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "已完成")
                    if finished.isEmpty { Text("暂无已完成的成品").font(.caption).foregroundColor(.secondary) }
                    else {
                        LazyVGrid(columns: gridColumns, spacing: 12) {
                            ForEach(finished) { work in
                                Button(action: { editingWork = work }) { workRow(work) }
                                    .buttonStyle(.plain)
                                    .contextMenu {
                                        Button("删除", role: .destructive) { store.deleteWork(work) }
                                    }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { WorkEditView(work: nil) } }
        .sheet(item: $editingWork) { work in NavigationStack { WorkEditView(work: work) } }
        .sheet(item: $addingMaterialWork) { work in NavigationStack { WorkMaterialAddView(work: work) } }
        .overlay(alignment: .bottomTrailing) {
            TabFAB(accent: themeAccent) { showingAdd = true }
        }
    }
}

struct OtherListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var editingItem: OtherItem?
    @State private var searchText = ""
    @State private var selectedCategory = "全部"
    @State private var isSingleColumn = false // 其他页本地二态：两列 ⇄ 整宽（无横向）

    private var totalAmount: Double {
        store.otherItems.filter { $0.hasPrice }.reduce(0) { $0 + $1.price }
    }
    private var gridColumns: [GridItem] {
        isSingleColumn
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
    private var categoryNames: [String] { ["全部"] + store.otherCategories }

    private var filtered: [OtherItem] {
        var list = store.otherItems
        if selectedCategory != "全部" {
            list = list.filter { ($0.category.isEmpty ? "未分类" : $0.category) == selectedCategory }
        }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !q.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(q)
                || $0.note.localizedCaseInsensitiveContains(q)
                || $0.category.localizedCaseInsensitiveContains(q)
                || $0.channel.localizedCaseInsensitiveContains(q)
            }
        }
        return list.sorted { $0.createdAt > $1.createdAt }
    }

    private func otherStatColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func otherRow(_ item: OtherItem) -> some View {
        HStack(spacing: 12) {
            if let first = item.imageFileNames.first,
               let uiImage = FabricImageStore.loadImage(named: first) {
                Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 56, height: 56).clipped().cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12).fill(Design.accentSoft).frame(width: 56, height: 56)
                    .overlay(Image(systemName: "archivebox").foregroundColor(Design.accent))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name.isEmpty ? "未命名条目" : item.name).font(.headline).lineLimit(1)
                Text("\(item.quantityText.isEmpty ? "" : item.quantityText + " · ")\(item.hasPrice ? "¥\(String(format: "%.2f", item.price))" : "")")
                    .font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(12)
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 其他统计卡（粘性在滚动区顶部，类比成品统计栏）。
                VStack(spacing: 8) {
                    StatsBigNumberHeader(count: store.otherItems.count, label: "条其他")
                    HStack(spacing: 0) {
                        otherStatColumn(label: "条数", value: "\(store.otherItems.count)")
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        otherStatColumn(label: "分类数", value: "\(store.otherCategories.count)")
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        otherStatColumn(label: "合计金额", value: "¥\(String(format: "%.2f", totalAmount))")
                    }
                }
                .padding(14)
                .background(ThemeStatsBackground(themeName: store.themeName))
                .cornerRadius(Design.corner)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                TabSearchField(placeholder: "搜索 名称 / 备注 / 分类 / 渠道", text: $searchText)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(categoryNames, id: \.self) { cat in
                            Button(action: { selectedCategory = cat }) {
                                Text(cat)
                                    .font(.caption)
                                    .padding(.horizontal, 12).padding(.vertical, 6)
                                    .background(selectedCategory == cat ? Design.accent : Color.gray.opacity(0.15))
                                    .foregroundColor(selectedCategory == cat ? .white : .primary)
                                    .cornerRadius(14)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HStack {
                    Text("\(filtered.count) 条").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Picker("视图", selection: $isSingleColumn) {
                        Text("两列").tag(false)
                        Text("单列").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                }
                if filtered.isEmpty {
                    EmptyPlaceholderView(icon: "archivebox", title: "没有匹配的其他条目", subtitle: "其他是你自建分类的容器，最少填名称加照片就能存")
                } else {
                    LazyVGrid(columns: gridColumns, spacing: 12) {
                        ForEach(filtered) { item in
                            Button(action: { editingItem = item }) { otherRow(item) }
                                .buttonStyle(.plain)
                                .contextMenu { Button("删除", role: .destructive) { store.deleteOtherItem(item) } }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .overlay(alignment: .bottomTrailing) {
            TabFAB(accent: Design.accent) { showingAdd = true }
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { OtherEditView(item: nil) } }
        .sheet(item: $editingItem) { item in NavigationStack { OtherEditView(item: item) } }
    }
}

struct WishlistListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var editingItem: WishlistItem?
    @State private var showingClearConfirm = false
    @State private var searchText = ""
    @State private var convertingItem: WishlistItem?

    private var totalEstimate: Double {
        store.wishlistItems.filter { $0.hasEstimatedPrice }.reduce(0) { $0 + $1.estimatedPrice }
    }

    private var filtered: [WishlistItem] {
        let list = store.wishlistItems.sorted { $0.createdAt > $1.createdAt }
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return list }
        return list.filter {
            $0.name.localizedCaseInsensitiveContains(q)
            || $0.note.localizedCaseInsensitiveContains(q)
        }
    }

    private func wishlistStatColumn(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundColor(.white.opacity(0.85))
            Text(value).font(.subheadline).fontWeight(.bold).foregroundColor(.white).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }

    private func wishlistRow(_ item: WishlistItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let first = item.imageFileNames.first,
                   let uiImage = FabricImageStore.loadImage(named: first) {
                    Image(uiImage: uiImage).resizable().scaledToFill().frame(width: 56, height: 56).clipped().cornerRadius(12)
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(Design.accentSoft).frame(width: 56, height: 56)
                        .overlay(Image(systemName: "heart").foregroundColor(Design.accent))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name.isEmpty ? "未命名心愿" : item.name).font(.headline).lineLimit(1)
                    if !item.note.isEmpty { Text(item.note).font(.caption).foregroundColor(.secondary).lineLimit(2) }
                    if item.hasEstimatedPrice {
                        Text("预估 ¥\(String(format: "%.2f", item.estimatedPrice))")
                            .font(.caption).fontWeight(.semibold).foregroundColor(Design.priceAccent)
                    }
                }
                Spacer()
            }
            HStack {
                Spacer()
                Button(action: { convertingItem = item }) {
                    Text("转入库")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Design.accent)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .background(Design.card)
        .cornerRadius(Design.corner)
        .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
        .onTapGesture { editingItem = item }
    }

    /// 心愿单 → 布料入库：把首张照片复制成新的独立文件（避免与心愿单共用
    /// 文件导致删一处文件另一处失效），再按预估价建布料，最后删心愿单。
    private func convertToFabric(_ item: WishlistItem) {
        var copiedNames: [String] = []
        if let first = item.imageFileNames.first,
           let data = FabricImageStore.data(for: first) {
            let newName = UUID().uuidString + ".jpg"
            if FabricImageStore.saveData(data, named: newName) {
                copiedNames = [newName]
            }
        }
        let fabric = Fabric(
            name: item.name,
            purchasePrice: item.hasEstimatedPrice ? item.estimatedPrice : 0,
            note: item.note,
            imageFileNames: copiedNames,
            hasTotalPrice: item.hasEstimatedPrice
        )
        store.addFabric(fabric)
        store.deleteWishlistItem(item)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 心愿单统计卡（粘性在滚动区顶部）。
                VStack(spacing: 8) {
                    StatsBigNumberHeader(count: store.wishlistItems.count, label: "条心愿")
                    HStack(spacing: 0) {
                        wishlistStatColumn(label: "待购数", value: "\(store.wishlistItems.count)")
                        Divider().frame(height: 36).background(Color.white.opacity(0.4))
                        wishlistStatColumn(label: "预估金额", value: "¥\(String(format: "%.2f", totalEstimate))")
                    }
                }
                .padding(14)
                .background(ThemeStatsBackground(themeName: store.themeName))
                .cornerRadius(Design.corner)
                .shadow(color: Color.black.opacity(0.12), radius: 10, x: 0, y: 4)
                HStack {
                    Button("清空心愿单", role: .destructive) { showingClearConfirm = true }
                    Spacer()
                }
                TabSearchField(placeholder: "搜索 名称 / 想法备注", text: $searchText)
                if filtered.isEmpty {
                    EmptyPlaceholderView(icon: "heart", title: "心愿单是空的", subtitle: "逛店看中先丢进来，只当备忘；长按布料页右下 + 可以从心愿单转入库")
                } else {
                    ForEach(filtered) { item in
                        wishlistRow(item)
                            .contextMenu { Button("删除", role: .destructive) { store.deleteWishlistItem(item) } }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { WishlistEditView(item: nil, presetName: "") } }
        .sheet(item: $editingItem) { item in NavigationStack { WishlistEditView(item: item, presetName: "") } }
        .alert("清空心愿单", isPresented: $showingClearConfirm) {
            Button("清空", role: .destructive) {
                for item in store.wishlistItems { store.deleteWishlistItem(item) }
            }
            Button("取消", role: .cancel) {}
        } message: { Text("会删除全部心愿单条目，无法恢复。") }
        .alert("转入库", isPresented: Binding(
            get: { convertingItem != nil },
            set: { if !$0 { convertingItem = nil } }
        )) {
            Button("确认转入") {
                if let item = convertingItem { convertToFabric(item) }
                convertingItem = nil
            }
            Button("取消", role: .cancel) { convertingItem = nil }
        } message: {
            let raw = convertingItem?.name ?? ""
            let display = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "未命名心愿" : raw
            Text("将「\(display)」转为布料入库（照片复制一份、预估价带入总价），心愿单条目会删除。")
        }
        .overlay(alignment: .bottomTrailing) {
            TabFAB(accent: Design.accent) { showingAdd = true }
        }
    }
}
