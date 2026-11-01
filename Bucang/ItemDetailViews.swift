import SwiftUI

// 其他详情页（2026-11-01）：参考布料详情，右上角齿轮菜单
struct OtherDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: OtherItem
    @State private var showingEdit = false
    @State private var showingDelete = false
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let first = item.imageFileNames.first,
                   let uiImage = FabricImageStore.loadImage(named: first) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFit().cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.name.isEmpty ? "未命名" : item.name)
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        Text(item.category.isEmpty ? "其他" : item.category)
                            .font(.caption).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(Color.black.opacity(0.45))
                            .cornerRadius(12)
                    }
                    if !item.quantityText.isEmpty {
                        Text("数量：\(item.quantityText)").font(.subheadline).foregroundColor(.secondary)
                    }
                    if item.hasPrice {
                        Text("价格 ¥\(String(format: "%.2f", item.price))").font(.subheadline)
                    }
                    if !item.channel.isEmpty {
                        Text("渠道：\(item.channel)").font(.subheadline).foregroundColor(.secondary)
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.body)
                    }
                    Text("创建：\(CSVValues.dateString(item.createdAt))").font(.caption).foregroundColor(.secondary)
                }
                .padding(16)
                .background(Design.card)
                .cornerRadius(Design.corner)
            }
            .padding(16)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("编辑", action: { showingEdit = true })
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { OtherEditView(item: item) }
        }
        .alert("删除条目", isPresented: $showingDelete) {
            Button("删除", role: .destructive) {
                store.deleteOtherItem(item)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(item.name.isEmpty ? "未命名" : item.name)」吗？")
        }
    }
}

// 心愿详情页（2026-11-01）：参考布料详情，右上角齿轮菜单
struct WishlistDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: WishlistItem
    @State private var showingEdit = false
    @State private var showingDelete = false
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let first = item.imageFileNames.first,
                   let uiImage = FabricImageStore.loadImage(named: first) {
                    Image(uiImage: uiImage)
                        .resizable().scaledToFit().cornerRadius(12)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(item.name.isEmpty ? "未命名心愿" : item.name)
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        Text(item.isPurchased ? "已购" : "待购")
                            .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(item.isPurchased ? Color.green : themeAccent)
                            .cornerRadius(12)
                    }
                    if item.hasEstimatedPrice {
                        Text("预估价 ¥\(String(format: "%.2f", item.estimatedPrice))").font(.subheadline)
                    }
                    if !item.note.isEmpty {
                        Text(item.note).font(.body)
                    }
                    Text("创建：\(CSVValues.dateString(item.createdAt))").font(.caption).foregroundColor(.secondary)
                }
                .padding(16)
                .background(Design.card)
                .cornerRadius(Design.corner)
                
                if !item.isPurchased {
                    Button("标为已购") {
                        item.isPurchased = true
                        store.save()
                    }
                    .buttonStyle(.borderedProminent).tint(themeAccent)
                    Button("转入库") {
                        // 转入库逻辑：创建布料
                        let fabric = Fabric(name: item.name,
                                          purchasePrice: item.hasEstimatedPrice ? item.estimatedPrice : 0,
                                          note: item.note,
                                          imageFileNames: item.imageFileNames,
                                          hasTotalPrice: item.hasEstimatedPrice)
                        store.fabrics.append(fabric)
                        store.save()
                        dismiss()
                    }
                    .buttonStyle(.bordered).tint(themeAccent)
                }
            }
            .padding(16)
        }
        .navigationTitle("心愿详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("编辑", action: { showingEdit = true })
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "gearshape") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { WishlistEditView(item: item, presetName: "") }
        }
        .alert("删除心愿", isPresented: $showingDelete) {
            Button("删除", role: .destructive) {
                store.deleteWishlistItem(item)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(item.name.isEmpty ? "未命名心愿" : item.name)」吗？")
        }
    }
}
