import SwiftUI

// 成品详情页（2026-11-01）：参考布料详情布局，右上角工具栏
struct WorkDetailView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var work: Work
    @State private var showingEdit = false
    @State private var showingDelete = false
    @State private var showingBrainstormPicker = false
    @State private var showingLongImage = false
    @State private var longImage: UIImage?
    private var themeAccent: Color { ThemeHelper.accent(store.themeName) }
    private var workSummary: String {
        var parts: [String] = []
        parts.append(work.name.isEmpty ? "未命名成品" : work.name)
        parts.append(work.isFinished ? "已完成" : "制作中")
        if work.isSold { parts.append("已出售") }
        if !work.note.isEmpty { parts.append(work.note) }
        return parts.joined(separator: "\n")
    }
    private func generateLongImage() {
        let view = VStack(alignment: .leading, spacing: 10) {
            Text("喵了个咪 · 成品详情").font(.headline)
            Text(workSummary).font(.body)
        }
        .padding(24)
        .frame(width: 360)
        .background(Color.white)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        renderer.proposedSize = .init(width: 360, height: 600)
        if let image = renderer.uiImage {
            longImage = image
            showingLongImage = true
        }
    }
    
    private var linkedBrainstorms: [Brainstorm] {
        store.brainstorms.filter { $0.linkedWorkIds.contains(work.id) }
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 图片
                if let first = work.imageFileNames.first,
                   let uiImage = FabricImageStore.loadImage(named: first) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .cornerRadius(12)
                }
                // 基本信息
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(work.name.isEmpty ? "未命名成品" : work.name)
                            .font(.title2).fontWeight(.bold)
                        Spacer()
                        Text(work.isFinished ? "已完成" : "制作中")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(work.isFinished ? Color.green : themeAccent)
                            .cornerRadius(12)
                    }
                    if !work.colorName.isEmpty {
                        Text("颜色：\(work.colorName)").font(.subheadline).foregroundColor(.secondary)
                    }
                    if let start = work.startedAt {
                        Text("开始：\(CSVValues.dateString(start))").font(.subheadline).foregroundColor(.secondary)
                    }
                    if let finish = work.finishedAt {
                        Text("完成：\(CSVValues.dateString(finish))").font(.subheadline).foregroundColor(.secondary)
                    }
                    if !work.note.isEmpty {
                        Text(work.note).font(.body)
                    }
                }
                .padding(16)
                .background(Design.card)
                .cornerRadius(Design.corner)
                
                // 关联脑洞
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("关联脑洞").font(.headline)
                        Spacer()
                        Button(action: { showingBrainstormPicker = true }) {
                            Image(systemName: "chevron.right").foregroundColor(.secondary)
                        }
                    }
                    if linkedBrainstorms.isEmpty {
                        Text("暂无关联脑洞").font(.caption).foregroundColor(.secondary)
                    } else {
                        ForEach(linkedBrainstorms) { bs in
                            BrainstormRowLink(bs: bs)
                        }
                    }
                }
                .padding(16)
                .background(Design.card)
                .cornerRadius(Design.corner)
                
                // 费用
                VStack(alignment: .leading, spacing: 8) {
                    Text("费用").font(.headline)
                    Text("总成本 ¥\(String(format: "%.2f", store.workTotalCost(for: work)))")
                        .font(.subheadline)
                    if work.hasLaborCost {
                        Text("工费 ¥\(String(format: "%.2f", work.laborCost))").font(.caption).foregroundColor(.secondary)
                    }
                    if work.isSold {
                        Text("已售出\(work.hasSalePrice ? " ¥\(String(format: "%.2f", work.salePrice))" : "")")
                            .font(.subheadline).foregroundColor(.green)
                    }
                }
                .padding(16)
                .background(Design.card)
                .cornerRadius(Design.corner)
            }
            .padding(16)
        }
        .navigationTitle("成品详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Button("编辑", action: { showingEdit = true })
                    ShareLink(item: workSummary, preview: SharePreview(work.displayName)) {
                        Label("分享", systemImage: "square.and.arrow.up")
                    }
                    Button("生成长图", action: { generateLongImage() })
                    Button("删除", role: .destructive) { showingDelete = true }
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack { WorkEditView(work: work) }
        }
        .alert("删除成品", isPresented: $showingDelete) {
            Button("删除", role: .destructive) {
                store.deleteWork(work)
                dismiss()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定删除「\(work.name.isEmpty ? "未命名成品" : work.name)」吗？")
        }
        .sheet(isPresented: $showingBrainstormPicker) {
            NavigationStack {
                BrainstormPickerView(work: work)
            }
        }
        .sheet(isPresented: $showingLongImage) {
            if let longImage {
                NavigationStack {
                    VStack {
                        Image(uiImage: longImage).resizable().scaledToFit().padding()
                        ShareLink(item: Image(uiImage: longImage), preview: SharePreview("成品长图")) {
                            Label("分享长图", systemImage: "square.and.arrow.up")
                        }.buttonStyle(.borderedProminent).tint(themeAccent)
                    }
                    .navigationTitle("长图")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { showingLongImage = false } } }
                }
            }
        }
    }
}

// 脑洞选择器：关联脑洞到成品
struct BrainstormPickerView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.dismiss) private var dismiss
    var work: Work
    
    var body: some View {
        List(store.brainstorms.sorted { $0.createdAt > $1.createdAt }) { bs in
            Button(action: {
                if !bs.linkedWorkIds.contains(work.id) {
                    bs.linkedWorkIds.append(work.id)
                    store.save()
                }
                dismiss()
            }) {
                HStack {
                    Text(bs.title.isEmpty ? "未命名脑洞" : bs.title).lineLimit(1)
                    Spacer()
                    if bs.linkedWorkIds.contains(work.id) {
                        Image(systemName: "checkmark").foregroundColor(.green)
                    }
                }
            }
        }
        .navigationTitle("关联脑洞")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 脑洞行（独立 View，避免编译器类型检查超时）
struct BrainstormRowLink: View {
    var bs: Brainstorm
    var body: some View {
        NavigationLink(destination: BrainstormDetailView(brainstorm: bs)) {
            HStack {
                Text(bs.title.isEmpty ? "未命名脑洞" : bs.title).lineLimit(1)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }
}
