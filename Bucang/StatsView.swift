import SwiftUI

// MARK: - 统计：全部由现有数据派生，不新增模型字段，不用 图表框架。
// 条形和圆环都是自定义 SwiftUI（GeometryReader / Circle.trim，iOS 16 安全）。

struct StatsView: View {
    @EnvironmentObject private var store: Store

    private var totalLength: Double { store.fabrics.reduce(0) { $0 + $1.length } }
    private var totalRemaining: Double { store.fabrics.reduce(0) { $0 + $1.remainingLength } }
    private var totalUsed: Double { store.fabrics.reduce(0) { $0 + $1.usedLength } }
    private var totalValue: Double { store.fabrics.reduce(0) { $0 + $1.purchasePrice } }

    private func groupedLength(by key: (Fabric) -> String) -> [(name: String, length: Double)] {
        var sums: [String: Double] = [:]
        for fabric in store.fabrics {
            sums[key(fabric), default: 0] += fabric.length
        }
        return sums.map { (name: $0.key, length: $0.value) }.sorted { $0.length > $1.length }
    }

    private var byMaterial: [(name: String, length: Double)] {
        groupedLength { store.material(for: $0.materialId)?.name ?? "未分类" }
    }

    private var byChannel: [(name: String, length: Double)] {
        groupedLength { store.channel(for: $0.channelId)?.name ?? "未分类" }
    }

    private var usageTotalLength: Double { store.usageRecords.reduce(0) { $0 + $1.length } }

    private func isThisMonth(_ date: Date) -> Bool {
        let cal = Calendar.current
        let now = cal.dateComponents([.year, .month], from: Date())
        let d = cal.dateComponents([.year, .month], from: date)
        return now.year == d.year && now.month == d.month
    }

    private var thisMonthNewFabrics: Int {
        store.fabrics.filter { isThisMonth($0.createdAt) }.count
    }

    private var thisMonthUsageLength: Double {
        store.usageRecords.filter { isThisMonth($0.date) }.reduce(0) { $0 + $1.length }
    }

    private var worksNotStarted: Int { store.works.filter { $0.progress <= 0 }.count }
    private var worksInProgress: Int { store.works.filter { $0.progress > 0 && $0.progress < 100 }.count }
    private var worksDone: Int { store.works.filter { $0.progress >= 100 }.count }
    private var averageWorkProgress: Double {
        guard !store.works.isEmpty else { return 0 }
        return store.works.reduce(0) { $0 + $1.progress } / Double(store.works.count) / 100.0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // 本月 / 全部摘要
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "本月 / 全部", subtitle: "本月指当前自然月")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatCardView(icon: "scissors", title: "本月新增布料", value: "\(thisMonthNewFabrics) 块")
                            StatCardView(icon: "scissors.circle", title: "本月使用长度", value: "\(String(format: "%.1f", thisMonthUsageLength)) 米")
                            StatCardView(icon: "ruler", title: "全部总长", value: "\(String(format: "%.1f", totalLength)) 米")
                            StatCardView(icon: "yensign.circle", title: "全部总价值", value: "¥\(String(format: "%.0f", totalValue))")
                        }
                    }

                    // 长度构成：剩余 vs 已用
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "长度构成", subtitle: "剩余和已用加起来就是总长")
                        CardView {
                            VStack(spacing: 14) {
                                HStack {
                                    Text("剩余")
                                    Spacer()
                                    Text("\(String(format: "%.1f", totalRemaining)) 米")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                ProgressBarView(fraction: totalLength > 0 ? totalRemaining / totalLength : 0, height: 10)
                                HStack {
                                    Text("已用")
                                    Spacer()
                                    Text("\(String(format: "%.1f", totalUsed)) 米")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                ProgressBarView(fraction: totalLength > 0 ? totalUsed / totalLength : 0, height: 10)
                            }
                        }
                    }

                    // 按材质
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "按材质统计", subtitle: "按总长度排")
                        CardView {
                            VStack(spacing: 14) {
                                if byMaterial.isEmpty {
                                    EmptyPlaceholderView(icon: "chart.bar", title: "暂无数据", subtitle: "加了布料后这里会自动统计")
                                } else {
                                    let maxLength = byMaterial.map { $0.length }.max() ?? 1
                                    ForEach(byMaterial, id: \.name) { item in
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

                    // 按渠道
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "按渠道统计", subtitle: "按总长度排")
                        CardView {
                            VStack(spacing: 14) {
                                if byChannel.isEmpty {
                                    EmptyPlaceholderView(icon: "chart.bar", title: "暂无数据", subtitle: "加了布料后这里会自动统计")
                                } else {
                                    let maxLength = byChannel.map { $0.length }.max() ?? 1
                                    ForEach(byChannel, id: \.name) { item in
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

                    // 使用记录
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "使用记录")
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                            StatCardView(icon: "list.clipboard", title: "使用次数", value: "\(store.usageRecords.count) 次")
                            StatCardView(icon: "scissors.circle", title: "累计使用长度", value: "\(String(format: "%.1f", usageTotalLength)) 米")
                        }
                    }

                    // 作品进度
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "作品进度", subtitle: "按进度 0%、进行中、100% 分")
                        CardView {
                            HStack(spacing: 20) {
                                RingView(
                                    fraction: averageWorkProgress,
                                    centerText: store.works.isEmpty ? "—" : "\(Int(averageWorkProgress * 100))%"
                                )
                                .frame(width: 90, height: 90)
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("未开始：\(worksNotStarted) 个")
                                    Text("进行中：\(worksInProgress) 个")
                                    Text("已完成：\(worksDone) 个")
                                    Text("平均进度：\(store.works.isEmpty ? "暂无作品" : "\(Int(averageWorkProgress * 100))%")")
                                        .foregroundColor(.secondary)
                                }
                                .font(.subheadline)
                                Spacer()
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
            }
            .background(Design.background)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
