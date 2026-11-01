import SwiftUI
import UIKit

// 其他详情页（2026-11-01）：参考布料详情，右上角齿轮菜单
struct OtherDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: OtherItem
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingLongImage = false
    @State private var longImage: UIImage?
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    private var itemSummary: String {
        var parts: [String] = []
        parts.append(item.name.isEmpty ? "未命名" : item.name)
        if !item.category.isEmpty { parts.append("分类：" + item.category) }
        if !item.note.isEmpty { parts.append(item.note) }
        return parts.joined(separator: "\n")
    }
    private func generateLongImage() {
        DispatchQueue.main.async {
            let view = VStack(alignment: .leading, spacing: 10) {
                Text("喵了个咪 · 其他详情").font(.headline)
                Text(self.itemSummary).font(.body)
            }
            .padding(24)
            .frame(width: 360)
            .background(Color.white)
            let hosting = UIHostingController(rootView: view)
            hosting.view.frame = CGRect(x: 0, y: 0, width: 360, height: 600)
            hosting.view.layoutIfNeeded()
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 600))
            let image = renderer.image { _ in
                hosting.view.drawHierarchy(in: hosting.view.bounds, afterScreenUpdates: true)
            }
            self.longImage = image
            self.showingLongImage = true
        }
    }
    
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
                    ShareLink(item: itemSummary, preview: SharePreview(item.name.isEmpty ? "未命名" : item.name)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button("生成长图", action: { generateLongImage() })
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { OtherEditView(item: item) }
        }
        .sheet(isPresented: $showingLongImage) {
            if let longImage {
                NavigationStack {
                    VStack {
                        Image(uiImage: longImage).resizable().scaledToFit().padding()
                        ShareLink(item: Image(uiImage: longImage), preview: SharePreview("其他长图")) {
                            Label("分享长图", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent).tint(themeAccent)
                    }
                    .navigationTitle("长图")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingLongImage = false } } }
                }
            }
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
    private var wishlistSummary: String {
        var parts: [String] = []
        parts.append(item.name.isEmpty ? "未命名心愿" : item.name)
        parts.append(item.isPurchased ? "已购" : "待购")
        if item.hasEstimatedPrice { parts.append(String(format: "预估 ¥%.2f", item.estimatedPrice)) }
        if !item.note.isEmpty { parts.append(item.note) }
        return parts.joined(separator: "\n")
    }
    
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
                    ShareLink(item: wishlistSummary, preview: SharePreview(item.name.isEmpty ? "未命名心愿" : item.name)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: { Image(systemName: "slider.horizontal.3") }
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
