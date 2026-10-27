import SwiftUI
import UniformTypeIdentifiers

// MARK: - 首页：总览仪表盘
// 暖灰白背景 + 白卡片 + 珊瑚橙主色，和布料/统计/我的页同一套设计。

struct HomeView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var webdav: WebDAVManager

    @State private var showingAddFabric = false
    @State private var showingImporter = false
    @State private var importSummary: String?
    @State private var showingSummary = false
    @State private var exportURLs: [URL] = []
    @State private var showingExporter = false
    @State private var showingWebDAVSheet = false

    private var totalLength: Double { store.fabrics.reduce(0) { $0 + $1.length } }
    private var totalRemaining: Double { store.fabrics.reduce(0) { $0 + $1.remainingLength } }
    private var totalUsed: Double { store.fabrics.reduce(0) { $0 + $1.usedLength } }
    private var totalValue: Double { store.fabrics.reduce(0) { $0 + $1.purchasePrice } }
    private var favoriteCount: Int { store.fabrics.filter { $0.isFavorite }.count }

    private var recentFabrics: [Fabric] {
        store.fabrics.sorted { $0.createdAt > $1.createdAt }.prefix(10).map { $0 }
    }

    private var materialDistribution: [(name: String, length: Double)] {
        var sums: [UUID: Double] = [:]
        var names: [UUID: String] = [:]
        for fabric in store.fabrics {
            if let mid = fabric.materialId {
                sums[mid, default: 0] += fabric.length
                names[mid] = store.material(for: mid)?.name ?? "未分类"
            } else {
                // 用一个固定 UUID 代表“未分类”，避免和真实材质撞键。
                let key = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
                sums[key, default: 0] += fabric.length
                names[key] = "未分类"
            }
        }
        return sums.map { (name: names[$0.key] ?? "未分类", length: $0.value) }
            .sorted { $0.length > $1.length }
            .prefix(6)
            .map { $0 }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "早上好"
        case 12..<14: return "中午好"
        case 14..<18: return "下午好"
        case 18..<23: return "晚上好"
        default: return "夜深了"
        }
    }

    private var dateText: String {
        let f = DateFormatter()
        f.dateFormat = "M月d日 EEEE"
        f.locale = Locale(identifier: "zh_CN")
        return f.string(from: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 大标题区
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(greeting)，布仓")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("\(dateText) · 你的布料库今天也在等你开工")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding(.top, 8)

                    // 统计卡片：2 列网格
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatCardView(icon: "scissors", title: "布料总数", value: "\(store.fabrics.count) 块")
                        StatCardView(icon: "ruler", title: "总长度", value: "\(String(format: "%.1f", totalLength)) 米")
                        StatCardView(icon: "leaf", title: "剩余长度", value: "\(String(format: "%.1f", totalRemaining)) 米")
                        StatCardView(icon: "scissors.circle", title: "已用长度", value: "\(String(format: "%.1f", totalUsed)) 米")
                        StatCardView(icon: "yensign.circle", title: "总价值", value: "¥\(String(format: "%.0f", totalValue))")
                        StatCardView(icon: "star.fill", title: "收藏", value: "\(favoriteCount) 块")
                    }

                    // 快捷操作
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "快捷操作")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            QuickActionButton(icon: "plus", title: "新增布料") { showingAddFabric = true }
                            QuickActionButton(icon: "square.and.arrow.down", title: "导入 CSV") { showingImporter = true }
                            QuickActionButton(icon: "icloud.and.arrow.up", title: "WebDAV 备份") { showingWebDAVSheet = true }
                            QuickActionButton(icon: "square.and.arrow.up", title: "导出 CSV") {
                                exportURLs = CSVExporter.exportFiles(store: store)
                                showingExporter = true
                            }
                        }
                    }

                    // 最近布料：横向卡片
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "最近布料", subtitle: "点一张卡片进去看详情、加使用记录和图片")
                        if recentFabrics.isEmpty {
                            CardView {
                                EmptyPlaceholderView(icon: "scissors", title: "还没有布料", subtitle: "点快捷操作新增，或去导入原来的 CSV")
                            }
                        } else {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 12) {
                                    ForEach(recentFabrics) { fabric in
                                        NavigationLink(destination: FabricDetailView(fabric: fabric)) {
                                            VStack(alignment: .leading, spacing: 8) {
                                                FabricCoverView(fabric: fabric, size: 120)
                                                    .frame(width: 120, height: 90)
                                                    .clipped()
                                                    .cornerRadius(12)
                                                Text(fabric.displayName)
                                                    .font(.subheadline)
                                                    .fontWeight(.semibold)
                                                    .foregroundColor(.primary)
                                                    .lineLimit(1)
                                                Text("\(String(format: "%.1f", fabric.length)) 米 · 剩 \(String(format: "%.1f", fabric.remainingLength)) 米")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(10)
                                            .background(Design.card)
                                            .cornerRadius(Design.corner)
                                            .shadow(color: Color.black.opacity(0.05), radius: 6, x: 0, y: 2)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }

                    // 材质分布：自定义条形
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "材质分布", subtitle: "按总长度排，看你囤得最多的是哪种料")
                        CardView {
                            VStack(spacing: 14) {
                                if materialDistribution.isEmpty {
                                    EmptyPlaceholderView(icon: "chart.bar", title: "暂无数据", subtitle: "加了布料后这里会自动统计")
                                } else {
                                    let maxLength = materialDistribution.map { $0.length }.max() ?? 1
                                    ForEach(materialDistribution, id: \.name) { item in
                                        BarRowView(
                                            label: item.name,
                                            valueText: "\(String(format: "%.1f", item.length)) 米",
                                            fraction: maxLength > 0 ? item.length / maxLength : 0
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
            .background(Design.background)
            .navigationTitle("首页")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingAddFabric) {
                NavigationStack { FabricEditView(fabric: nil) }
            }
            .sheet(isPresented: $showingWebDAVSheet) {
                NavigationStack {
                    ScrollView {
                        WebDAVBackupView()
                            .padding()
                    }
                    .background(Design.background)
                    .navigationTitle("WebDAV 备份")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("完成") { showingWebDAVSheet = false }
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [UTType.commaSeparatedText],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    let summary = CSVImporter.importFiles(urls, store: store)
                    importSummary = summary.text
                    showingSummary = true
                case .failure(let error):
                    importSummary = "选择文件失败：\(error.localizedDescription)"
                    showingSummary = true
                }
            }
            .alert("导入结果", isPresented: $showingSummary) {
                Button("好", role: .cancel) {}
            } message: {
                Text(importSummary ?? "")
            }
            .sheet(isPresented: $showingExporter) {
                ActivityView(urls: exportURLs)
            }
        }
    }
}
