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
    @State private var headerPhotoIndex = 0
    @State private var collapsedSections: Set<String> = []
    @State private var shareFileItem: ShareURLItem?
    @State private var sharePDFItem: ShareURLItem?
    struct ShareURLItem: Identifiable {
        let id = UUID()
        let url: URL
    }
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var photoHeader: some View {
        ZStack(alignment: .topTrailing) {
            if item.imageFileNames.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(ThemeHelper.accentSoft(store.themeName))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(Image(systemName: "archivebox").font(.largeTitle).foregroundColor(themeAccent))
            } else {
                TabView(selection: $headerPhotoIndex) {
                    ForEach(Array(item.imageFileNames.enumerated()), id: \.element) { idx, name in
                        Group {
                            if let uiImage = FabricImageStore.loadImage(named: name) {
                                Image(uiImage: uiImage).resizable().scaledToFill()
                            } else { Color.gray.opacity(0.15) }
                        }.tag(idx)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .aspectRatio(4 / 3, contentMode: .fit)
                .cornerRadius(16).clipped()
            }
            if item.imageFileNames.count > 1 {
                Text("\(headerPhotoIndex + 1) / \(item.imageFileNames.count)")
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.45)).cornerRadius(10).padding(8)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name.isEmpty ? "未命名" : item.name).font(.title3).fontWeight(.bold)
                Spacer()
                Text(item.category.isEmpty ? "其他" : item.category)
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.45)).cornerRadius(10)
            }
            HStack(spacing: 16) {
                if !item.quantityText.isEmpty {
                    Text("数量：\(item.quantityText)").font(.subheadline).foregroundColor(.secondary)
                }
                if item.hasPrice {
                    Text("价格 ¥\(String(format: "%.2f", item.price))").font(.subheadline).foregroundColor(.orange)
                }
            }
            if !item.channel.isEmpty {
                Text("渠道：\(item.channel)").font(.subheadline).foregroundColor(.secondary)
            }
        }
        .padding(16).background(Design.card).cornerRadius(Design.corner)
    }

    private func collapsibleSection<Content: View>(key: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        let collapsed = collapsedSections.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if collapsed { collapsedSections.remove(key) } else { collapsedSections.insert(key) }
            }) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up").foregroundColor(.secondary).font(.caption)
                }.padding(.vertical, 12)
            }.buttonStyle(.plain)
            if !collapsed { content().padding(.bottom, 12) }
        }
        .padding(.horizontal, 16).background(Design.card).cornerRadius(Design.corner)
    }
    private var itemSummary: String {
        var parts: [String] = []
        parts.append(item.name.isEmpty ? "未命名" : item.name)
        if !item.category.isEmpty { parts.append("分类：" + item.category) }
        if !item.note.isEmpty { parts.append(item.note) }
        return parts.joined(separator: "\n")
    }
    private func generateLongImage(showSheet: Bool = true) {
        let content = buildOtherLongContent()
        let size = otherLongSize(for: content)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            drawOtherLong(content, in: ctx.cgContext, size: size)
        }
        self.longImage = image
        if showSheet {
            DispatchQueue.main.async { self.showingLongImage = true }
        }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                photoHeader
                summaryCard
                HStack {
                    Spacer()
                    Button(action: {
                        if collapsedSections.isEmpty {
                            collapsedSections = ["images", "info"]
                        } else {
                            collapsedSections = []
                        }
                    }) {
                        Label(collapsedSections.isEmpty ? "全部收起" : "全部展开", systemImage: "chevron.down.circle")
                            .font(.subheadline).foregroundColor(themeAccent)
                    }
                }
                collapsibleSection(key: "images", title: "图片") {
                    if item.imageFileNames.isEmpty {
                        Text("暂无图片").font(.subheadline).foregroundColor(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(item.imageFileNames, id: \.self) { name in
                                Group {
                                    if let uiImage = FabricImageStore.loadImage(named: name) {
                                        Image(uiImage: uiImage).resizable().scaledToFill()
                                    } else { Color.gray.opacity(0.15) }
                                }
                                .frame(height: 100).clipped().cornerRadius(10)
                            }
                        }
                    }
                }
                collapsibleSection(key: "info", title: "基本信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        if !item.quantityText.isEmpty {
                            Text("数量：\(item.quantityText)").font(.subheadline)
                        }
                        if item.hasPrice {
                            Text("价格 ¥\(String(format: "%.2f", item.price))").font(.subheadline)
                        }
                        if !item.channel.isEmpty {
                            Text("渠道：\(item.channel)").font(.subheadline).foregroundColor(.secondary)
                        }
                        if !item.note.isEmpty {
                            Text("备注：\(item.note)").font(.subheadline)
                        }
                        Text("创建：\(CSVValues.dateString(item.createdAt))").font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .padding(16)
        }
        .navigationTitle("详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("编辑", action: { showingEdit = true })
                    Menu {
                        Button(action: {
                            let img: UIImage?
                            if let existing = longImage { img = existing }
                            else { generateLongImage(showSheet: false); img = longImage }
                            if let img = img, let data = img.pngData() {
                                let url = FileManager.default.temporaryDirectory
                                    .appendingPathComponent("其他长图-\(item.name.isEmpty ? "未命名" : item.name)-\(Int(Date().timeIntervalSince1970)).png")
                                try? data.write(to: url)
                                shareFileItem = ShareURLItem(url: url)
                            }
                        }) { Label("分享长图", systemImage: "photo") }
                        Button(action: {
                            if let url = generateLongPDF() { sharePDFItem = ShareURLItem(url: url) }
                        }) { Label("分享PDF", systemImage: "doc.richtext") }
                    } label: { Label("分享", systemImage: "square.and.arrow.up") }
                    Button("生成长图", action: {
                        if longImage == nil { generateLongImage() } else { showingLongImage = true }
                    })
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
                        HStack(spacing: 12) {
                            ShareLink(item: Image(uiImage: longImage), preview: SharePreview("其他长图")) {
                                Label("分享长图", systemImage: "square.and.arrow.up")
                            }.buttonStyle(.borderedProminent).tint(themeAccent)
                            Button(action: {
                                if let url = generateLongPDF() { sharePDFItem = ShareURLItem(url: url) }
                            }) { Label("分享PDF", systemImage: "doc.richtext") }.buttonStyle(.bordered).tint(themeAccent)
                        }
                        Text("长图分享为图片；PDF 里的文字可复制。").font(.caption).foregroundColor(.secondary)
                    }
                    .navigationTitle("长图")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingLongImage = false } } }
                    .sheet(item: $sharePDFItem) { item in ShareSheet(url: item.url) }
                }
            }
        }
        .sheet(item: $shareFileItem) { item in ShareSheet(url: item.url) }
        .sheet(item: $sharePDFItem) { item in ShareSheet(url: item.url) }
        .alert("删除条目", isPresented: $showingDelete) {
            Button("删除", role: .destructive) {
                store.deleteOtherItem(item)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(item.name.isEmpty ? "未命名" : item.name)」吗？")
        }
        .onAppear {
            if longImage == nil { generateLongImage(showSheet: false) }
        }
    }

    // MARK: - 长图 PDF（统一）
    private struct OtherLongContent {
        var lines: [String]
        var photos: [UIImage]
    }
    private func buildOtherLongContent() -> OtherLongContent {
        var l: [String] = []
        l.append("喵了个咪 · 其他详情")
        l.append("")
        l.append("名称：" + (item.name.isEmpty ? "未命名" : item.name))
        if !item.category.isEmpty { l.append("分类：" + item.category) }
        if !item.quantityText.isEmpty { l.append("数量：" + item.quantityText) }
        if item.hasPrice { l.append(String(format: "价格：¥%.2f", item.price)) }
        if !item.channel.isEmpty { l.append("渠道：" + item.channel) }
        if !item.note.isEmpty { l.append("备注：" + item.note) }
        let photos: [UIImage] = item.imageFileNames.compactMap { FabricImageStore.loadImage(named: $0) }
        return OtherLongContent(lines: l, photos: photos)
    }
    private func otherLongSize(for content: OtherLongContent) -> CGSize {
        let width: CGFloat = 720
        let lineHeight: CGFloat = 44
        let padding: CGFloat = 40
        let photoHeight: CGFloat = 400
        let totalPhotoHeight: CGFloat = CGFloat(content.photos.count) * (photoHeight + 16)
        return CGSize(width: width, height: padding * 2 + totalPhotoHeight + CGFloat(content.lines.count) * lineHeight + 40)
    }
    private func drawOtherLong(_ content: OtherLongContent, in cg: CGContext, size: CGSize) {
        let padding: CGFloat = 40
        let lineHeight: CGFloat = 44
        let photoHeight: CGFloat = 400
        UIColor.white.setFill()
        cg.fill(CGRect(origin: .zero, size: size))
        var y = padding
        for photo in content.photos {
            let photoRect = CGRect(x: padding, y: y, width: size.width - padding * 2, height: photoHeight)
            let imgAspect = photo.size.width / photo.size.height
            let rectAspect = photoRect.width / photoRect.height
            var drawRect: CGRect
            if imgAspect > rectAspect {
                let h = photoRect.height
                let w = h * imgAspect
                drawRect = CGRect(x: photoRect.minX - (w - photoRect.width) / 2, y: photoRect.minY, width: w, height: h)
            } else {
                let w = photoRect.width
                let h = w / imgAspect
                drawRect = CGRect(x: photoRect.minX, y: photoRect.minY - (h - photoRect.height) / 2, width: w, height: h)
            }
            UIGraphicsPushContext(cg)
            let uictx = UIGraphicsGetCurrentContext()
            uictx?.saveGState(); uictx?.addRect(photoRect); uictx?.clip()
            photo.draw(in: drawRect)
            uictx?.restoreGState()
            UIGraphicsPopContext()
            y += photoHeight + 16
        }
        if !content.photos.isEmpty { y += 4 }
        UIGraphicsPushContext(cg)
        for (i, line) in content.lines.enumerated() {
            let font = i == 0 ? UIFont.boldSystemFont(ofSize: 32) : UIFont.systemFont(ofSize: 28)
            (line as NSString).draw(at: CGPoint(x: padding, y: y), withAttributes: [.font: font, .foregroundColor: UIColor.black])
            y += lineHeight
        }
        UIGraphicsPopContext()
    }
    private func generateLongPDF() -> URL? {
        let content = buildOtherLongContent()
        let size = otherLongSize(for: content)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: size))
        let data = renderer.pdfData { ctx in
            ctx.beginPage()
            drawOtherLong(content, in: ctx.cgContext, size: size)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("其他详情-\(item.name.isEmpty ? "未命名" : item.name)-\(Int(Date().timeIntervalSince1970)).pdf")
        try? data.write(to: url)
        return url
    }
}
struct WishlistDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var item: WishlistItem
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var headerPhotoIndex = 0
    @State private var collapsedSections: Set<String> = []
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }

    private var photoHeader: some View {
        ZStack(alignment: .topTrailing) {
            if item.imageFileNames.isEmpty {
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.pink.opacity(0.15))
                    .aspectRatio(4 / 3, contentMode: .fit)
                    .overlay(Image(systemName: "heart").font(.largeTitle).foregroundColor(.pink))
            } else {
                TabView(selection: $headerPhotoIndex) {
                    ForEach(Array(item.imageFileNames.enumerated()), id: \.element) { idx, name in
                        Group {
                            if let uiImage = FabricImageStore.loadImage(named: name) {
                                Image(uiImage: uiImage).resizable().scaledToFill()
                            } else { Color.gray.opacity(0.15) }
                        }.tag(idx)
                    }
                }
                .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                .aspectRatio(4 / 3, contentMode: .fit)
                .cornerRadius(16).clipped()
            }
            if item.imageFileNames.count > 1 {
                Text("\(headerPhotoIndex + 1) / \(item.imageFileNames.count)")
                    .font(.caption).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.black.opacity(0.45)).cornerRadius(10).padding(8)
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(item.name.isEmpty ? "未命名心愿" : item.name).font(.title3).fontWeight(.bold)
                Spacer()
                Text(item.isPurchased ? "已购" : "待购")
                    .font(.caption).fontWeight(.semibold).foregroundColor(.white)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(item.isPurchased ? Color.green : themeAccent).cornerRadius(10)
            }
            if item.hasEstimatedPrice {
                Text("预估价 ¥\(String(format: "%.2f", item.estimatedPrice))").font(.subheadline).foregroundColor(.orange)
            }
        }
        .padding(16).background(Design.card).cornerRadius(Design.corner)
    }

    private func collapsibleSection<Content: View>(key: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        let collapsed = collapsedSections.contains(key)
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: {
                if collapsed { collapsedSections.remove(key) } else { collapsedSections.insert(key) }
            }) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Image(systemName: collapsed ? "chevron.down" : "chevron.up").foregroundColor(.secondary).font(.caption)
                }.padding(.vertical, 12)
            }.buttonStyle(.plain)
            if !collapsed { content().padding(.bottom, 12) }
        }
        .padding(.horizontal, 16).background(Design.card).cornerRadius(Design.corner)
    }
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
                photoHeader
                summaryCard
                HStack {
                    Spacer()
                    Button(action: {
                        if collapsedSections.isEmpty {
                            collapsedSections = ["images", "info"]
                        } else {
                            collapsedSections = []
                        }
                    }) {
                        Label(collapsedSections.isEmpty ? "全部收起" : "全部展开", systemImage: "chevron.down.circle")
                            .font(.subheadline).foregroundColor(themeAccent)
                    }
                }
                collapsibleSection(key: "images", title: "图片") {
                    if item.imageFileNames.isEmpty {
                        Text("暂无图片").font(.subheadline).foregroundColor(.secondary)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
                            ForEach(item.imageFileNames, id: \.self) { name in
                                Group {
                                    if let uiImage = FabricImageStore.loadImage(named: name) {
                                        Image(uiImage: uiImage).resizable().scaledToFill()
                                    } else { Color.gray.opacity(0.15) }
                                }
                                .frame(height: 100).clipped().cornerRadius(10)
                            }
                        }
                    }
                }
                collapsibleSection(key: "info", title: "基本信息") {
                    VStack(alignment: .leading, spacing: 8) {
                        if item.hasEstimatedPrice {
                            Text("预估价 ¥\(String(format: "%.2f", item.estimatedPrice))").font(.subheadline)
                        }
                        if !item.note.isEmpty {
                            Text("备注：\(item.note)").font(.subheadline)
                        }
                        Text("创建：\(CSVValues.dateString(item.createdAt))").font(.caption).foregroundColor(.secondary)
                    }
                }
                if !item.isPurchased {
                    VStack(spacing: 10) {
                        Button("标为已购") {
                            item.isPurchased = true
                            store.save()
                        }
                        .buttonStyle(.borderedProminent).tint(themeAccent)
                        Button("转入库") {
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
