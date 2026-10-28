import SwiftUI

// MARK: - V3 成品 / 其他 / 心愿单列表（嵌在布仓 NavigationStack 里，不自带 NavigationStack）

struct WorksListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var editingWork: Work?
    @State private var addingMaterialWork: Work?

    private var making: [Work] { store.works.filter { !$0.isFinished }.sorted { $0.createdAt > $1.createdAt } }
    private var finished: [Work] { store.works.filter { $0.isFinished }.sorted { $0.createdAt > $1.createdAt } }

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
            let cost = store.workCost(for: work)
            Text("用料成本合计：¥\(String(format: "%.2f", cost.total))\(cost.hasMissingPrice ? "（部分布料无单价，未计入）" : "")")
                .font(.caption).foregroundColor(.secondary)
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
                HStack {
                    Spacer()
                    Button(action: { showingAdd = true }) {
                        Label("新建成品", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "制作中")
                    if making.isEmpty { Text("暂无制作中的成品").font(.caption).foregroundColor(.secondary) }
                    else {
                        ForEach(making) { work in
                            Button(action: { editingWork = work }) { workRow(work) }
                                .buttonStyle(.plain)
                                .contextMenu {
                                    Button("删除", role: .destructive) { store.deleteWork(work) }
                                }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "已完成")
                    if finished.isEmpty { Text("暂无已完成的成品").font(.caption).foregroundColor(.secondary) }
                    else {
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
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 80)
        }
        .sheet(isPresented: $showingAdd) { NavigationStack { WorkEditView(work: nil) } }
        .sheet(item: $editingWork) { work in NavigationStack { WorkEditView(work: work) } }
        .sheet(item: $addingMaterialWork) { work in NavigationStack { WorkMaterialAddView(work: work) } }
    }
}

struct OtherListView: View {
    @EnvironmentObject private var store: Store
    @State private var showingAdd = false
    @State private var editingItem: OtherItem?

    private var grouped: [(category: String, items: [OtherItem])] {
        var dict: [String: [OtherItem]] = [:]
        for item in store.otherItems {
            let key = item.category.isEmpty ? "未分类" : item.category
            dict[key, default: []].append(item)
        }
        return dict.map { (category: $0.key, items: $0.value.sorted { $0.createdAt > $1.createdAt }) }.sorted { $0.category < $1.category }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Spacer()
                    Button(action: { showingAdd = true }) { Label("新增条目", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Design.accent)
                }
                if grouped.isEmpty {
                    EmptyPlaceholderView(icon: "archivebox", title: "还没有其他条目", subtitle: "其他是你自建分类的容器，最少填名称加照片就能存")
                } else {
                    ForEach(grouped, id: \.category) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            SectionHeaderView(title: group.category)
                            ForEach(group.items) { item in
                                Button(action: { editingItem = item }) {
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
                                }
                                .buttonStyle(.plain)
                                .contextMenu { Button("删除", role: .destructive) { store.deleteOtherItem(item) } }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .padding(.bottom, 80)
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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button("清空心愿单", role: .destructive) { showingClearConfirm = true }
                    Spacer()
                    Button(action: { showingAdd = true }) { Label("新增心愿", systemImage: "plus") }
                        .buttonStyle(.borderedProminent).tint(Design.accent)
                }
                if store.wishlistItems.isEmpty {
                    EmptyPlaceholderView(icon: "heart", title: "心愿单是空的", subtitle: "逛店看中先丢进来，只当备忘；长按布料页右下 + 可以从心愿单转入库")
                } else {
                    ForEach(store.wishlistItems.sorted { $0.createdAt > $1.createdAt }) { item in
                        Button(action: { editingItem = item }) {
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
                                }
                                Spacer()
                            }
                            .padding(12)
                            .background(Design.card)
                            .cornerRadius(Design.corner)
                        }
                        .buttonStyle(.plain)
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
    }
}
