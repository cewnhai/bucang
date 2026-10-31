import SwiftUI

// 卡片显示信息明细（2026-10-31）：二级菜单
struct CardDisplaySettingsView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            Section("布料卡片上显示哪些字段，顺序固定") {
                ForEach(Store.cardFieldOptions, id: \.key) { option in
                    Toggle(option.title, isOn: Binding(
                        get: { store.cardDisplayFields.contains(option.key) },
                        set: { on in
                            var keys = store.cardDisplayFields
                            if on {
                                if !keys.contains(option.key) { keys.append(option.key) }
                            } else {
                                keys.removeAll { $0 == option.key }
                            }
                            store.cardDisplayFields = Store.cardFieldOptions.map { $0.key }.filter { keys.contains($0) }
                            store.save()
                        }
                    ))
                }
            }
            Section {
                Text("全不选时卡片不显示附加信息；下次打开设置页会恢复默认 5 项。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("卡片显示信息")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 顶栏显示明细（2026-10-31）：二级菜单
struct TopBarSettingsView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            Section("布仓顶部一级 Tab 的可见性，布料始终显示、不可关闭") {
                ForEach([("fabric", "布料"), ("work", "成品"), ("brainstorm", "脑洞"), ("other", "其他"), ("wishlist", "心愿单")], id: \.0) { key, title in
                    if key == "fabric" {
                        HStack { Text(title); Spacer(); Text("始终显示").font(.caption).foregroundColor(.secondary) }
                    } else {
                        Toggle(title, isOn: Binding(
                            get: { (store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs).contains(key) },
                            set: { on in
                                var keys = store.visibleTabs.isEmpty ? Store.allTabKeys : store.visibleTabs
                                if on { if !keys.contains(key) { keys.append(key) } }
                                else { keys.removeAll { $0 == key } }
                                if !keys.contains("fabric") { keys.insert("fabric", at: 0) }
                                store.visibleTabs = Store.allTabKeys.filter { keys.contains($0) }
                                store.save()
                            }
                        ))
                    }
                }
            }
        }
        .navigationTitle("顶栏显示")
        .navigationBarTitleDisplayMode(.inline)
    }
}
