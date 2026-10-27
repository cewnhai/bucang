import SwiftUI

// MARK: - 创作：作品 / 纸样 / 物品合在一个 Tab 里，用分段选择切换。
// 下面三个列表视图本身各带一个 NavigationStack（沿用原有实现，
// CRUD、搜索、编辑视图原样保留，不做危险重构），
// 所以这里不包 NavigationStack，只在上面放一个分段选择器，
// 切换时显示对应列表；列表自己的标题和加号按钮仍然有效。

struct CreationView: View {
    @State private var segment = 0

    var body: some View {
        VStack(spacing: 0) {
            Picker("创作", selection: $segment) {
                Text("作品").tag(0)
                Text("纸样").tag(1)
                Text("物品").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .background(Design.background)
            Group {
                switch segment {
                case 0:
                    WorkListView()
                case 1:
                    PatternListView()
                default:
                    ItemListView()
                }
            }
        }
        .background(Design.background)
    }
}
