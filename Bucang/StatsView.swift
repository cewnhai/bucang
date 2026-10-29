import SwiftUI

// MARK: - V3 统计图表页（自定义绘制，不用图表框架，iOS 16 安全）
// 按材质看金额分布、近 12 个月购入与消耗趋势、售出回款曲线（不含库存残值）。

struct ChartsView: View {
    @EnvironmentObject private var store: Store

    private func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }
    private func monthLabel(_ key: String) -> String {
        let parts = key.split(separator: "-")
        guard parts.count == 2 else { return key }
        return "\(parts[1])月"
    }
    private var last12Months: [String] {
        var keys: [String] = []
        let cal = Calendar.current
        for offset in (0..<12).reversed() {
            if let date = cal.date(byAdding: .month, value: -offset, to: Date()) {
                keys.append(monthKey(date))
            }
        }
        return keys
    }
    private var byMaterialAmount: [(name: String, value: Double)] {
        var sums: [String: Double] = [:]
        for fabric in store.fabrics where fabric.hasTotalPrice {
            let key = fabric.materialName.isEmpty ? "未填" : fabric.materialName
            sums[key, default: 0] += fabric.purchasePrice
        }
        return sums.map { (name: $0.key, value: $0.value) }.sorted { $0.value > $1.value }
    }
    private var monthlyPurchase: [String: Double] {
        var sums: [String: Double] = [:]
        for fabric in store.fabrics where fabric.hasPurchaseLength {
            // 购买日期未填的布料不进按月购入趋势（不默认今天）。
            guard let date = fabric.purchaseDate else { continue }
            sums[monthKey(date), default: 0] += fabric.length
        }
        return sums
    }
    private var monthlyConsumption: [String: Double] {
        var sums: [String: Double] = [:]
        for record in store.usageRecords {
            sums[monthKey(record.date), default: 0] += record.length
        }
        return sums
    }
    private var monthlySoldRevenue: [String: Double] {
        var sums: [String: Double] = [:]
        for record in store.saleRecords {
            sums[monthKey(record.date), default: 0] += record.price
        }
        return sums
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if store.totalMeters > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeaderView(title: "售出占比", subtitle: "售出米数 ÷ 购入总米数（购入总米数为 0 时不显示）")
                        CardView {
                            HStack {
                                Text("已售出米数占比")
                                Spacer()
                                let pct = store.totalSoldMeters / store.totalMeters * 100
                                Text(String(format: "%.1f%%", pct)).font(.headline)
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "按材质看金额分布", subtitle: "总价留空的布料不计入")
                    CardView {
                        VStack(spacing: 14) {
                            if byMaterialAmount.isEmpty {
                                EmptyPlaceholderView(icon: "chart.bar", title: "暂无数据", subtitle: "加了带总价的布料后这里会自动统计")
                            } else {
                                let maxValue = byMaterialAmount.map { $0.value }.max() ?? 1
                                ForEach(byMaterialAmount, id: \.name) { item in
                                    BarRowView(label: item.name, valueText: "¥\(String(format: "%.0f", item.value))", fraction: maxValue > 0 ? item.value / maxValue : 0)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "近 12 个月购入与消耗趋势", subtitle: "购入按购买日期，消耗按使用日期")
                    CardView {
                        VStack(spacing: 14) {
                            let purchase = monthlyPurchase
                            let consumption = monthlyConsumption
                            let maxValue = max(
                                last12Months.map { purchase[$0] ?? 0 }.max() ?? 0,
                                last12Months.map { consumption[$0] ?? 0 }.max() ?? 0,
                                1
                            )
                            ForEach(last12Months, id: \.self) { month in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(monthLabel(month)).font(.subheadline).fontWeight(.semibold)
                                    BarRowView(label: "购入", valueText: "\(LengthUnitHelper.format(purchase[month] ?? 0, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))", fraction: maxValue > 0 ? (purchase[month] ?? 0) / maxValue : 0)
                                    HStack {
                                        Text("消耗").font(.subheadline)
                                        Spacer()
                                        Text("\(LengthUnitHelper.format(consumption[month] ?? 0, unit: store.lengthUnit))\(LengthUnitHelper.suffix(unit: store.lengthUnit))").font(.subheadline).foregroundColor(.secondary)
                                    }
                                    ProgressBarView(fraction: maxValue > 0 ? (consumption[month] ?? 0) / maxValue : 0, height: 8)
                                }
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 12) {
                    SectionHeaderView(title: "售出回款曲线", subtitle: "按售出日期汇总，不含库存残值折算")
                    CardView {
                        VStack(alignment: .leading, spacing: 12) {
                            let values = last12Months.map { monthlySoldRevenue[$0] ?? 0 }
                            let maxValue = max(values.max() ?? 0, 1)
                            GeometryReader { geo in
                                let width = geo.size.width
                                let height: CGFloat = 140
                                let stepX = values.count > 1 ? width / CGFloat(values.count - 1) : width
                                ZStack {
                                    Path { path in
                                        for i in values.indices {
                                            let x = CGFloat(i) * stepX
                                            let y = height - CGFloat(values[i] / maxValue) * (height - 20)
                                            if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                                        }
                                    }
                                    .stroke(Design.accent, lineWidth: 2)
                                    ForEach(values.indices, id: \.self) { i in
                                        let x = CGFloat(i) * stepX
                                        let y = height - CGFloat(values[i] / maxValue) * (height - 20)
                                        Circle().fill(Design.accent).frame(width: 8, height: 8).position(x: x, y: y)
                                    }
                                }
                            }
                            .frame(height: 140)
                            HStack {
                                ForEach(last12Months, id: \.self) { month in
                                    Text(monthLabel(month)).font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity)
                                }
                            }
                            if values.allSatisfy({ $0 == 0 }) {
                                Text("暂无售出回款").font(.caption).foregroundColor(.secondary)
                            } else {
                                Text("近 12 个月售出回款合计：¥\(String(format: "%.2f", values.reduce(0, +)))")
                                    .font(.subheadline)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
        .background(Design.background)
        .navigationTitle("统计图表")
        .navigationBarTitleDisplayMode(.inline)
    }
}
