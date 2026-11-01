import SwiftUI

// 卡片显示信息明细（2026-10-31）：二级菜单
struct CardDisplaySettingsView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        Form {
            // 2026-11-01：已选字段可长按拖动排序（编辑模式）
            Section("已选字段（右上角编辑后长按拖动排序）") {
                ForEach(store.cardDisplayFields, id: \.self) { key in
                    if let option = Store.cardFieldOptions.first(where: { $0.key == key }) {
                        Text(option.title)
                    }
                }
                .onMove { from, to in
                    store.cardDisplayFields.move(fromOffsets: from, toOffset: to)
                    store.save()
                }
                .onDelete { offsets in
                    store.cardDisplayFields.remove(atOffsets: offsets)
                    store.save()
                }
            }
            Section("可选字段") {
                ForEach(Store.cardFieldOptions, id: \.key) { option in
                    if !store.cardDisplayFields.contains(option.key) {
                        Button(action: {
                            store.cardDisplayFields.append(option.key)
                            store.save()
                        }) {
                            HStack {
                                Text(option.title)
                                Spacer()
                                Image(systemName: "plus.circle").foregroundColor(.green)
                            }
                        }
                    }
                }
            }
            Section {
                Text("全不选时卡片不显示附加信息；下次打开设置页会恢复默认 5 项。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("卡片显示信息")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
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
