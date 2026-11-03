import SwiftUI

// 其他分类多级管理（2026-11-01）：字典管理二级菜单
// 一级分类列表，每行 > 进入子分类管理；子菜单内可新增/改名/删除
struct OtherCategorySettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newName = ""
    @State private var renamingId: UUID?
    @State private var renameText = ""
    
    private var topLevels: [OtherCategory] {
        store.otherCategoryTree.filter { $0.parentId == nil }.sorted { $0.order < $1.order }
    }
    
    private func addTopLevel() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let maxOrder = topLevels.map { $0.order }.max() ?? -1
        store.otherCategoryTree.append(OtherCategory(name: name, parentId: nil, order: maxOrder + 1))
        store.save()
        newName = ""
    }
    
    private func delete(_ cat: OtherCategory) {
        // 删除一级：其子分类一并删除；使用该分类的条目改成"其他"
        let idsToDelete = Set([cat.id] + store.otherCategoryTree.filter { $0.parentId == cat.id }.map { $0.id })
        let namesToDelete = Set(store.otherCategoryTree.filter { idsToDelete.contains($0.id) }.map { $0.name })
        store.otherCategoryTree.removeAll { idsToDelete.contains($0.id) }
        for item in store.otherItems where namesToDelete.contains(item.category) {
            item.category = "其他"
        }
        store.save()
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("新增一级分类", text: $newName)
                    Button("添加") { addTopLevel() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("一级分类") {
                ForEach(topLevels) { cat in
                    NavigationLink(destination: OtherSubCategoryView(parent: cat)) {
                        HStack {
                            if renamingId == cat.id {
                                TextField("名称", text: $renameText, onCommit: {
                                    let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if !n.isEmpty, let idx = store.otherCategoryTree.firstIndex(where: { $0.id == cat.id }) {
                                        store.otherCategoryTree[idx].name = n
                                        store.save()
                                    }
                                    renamingId = nil
                                })
                            } else {
                                Button(action: {
                                    renamingId = cat.id
                                    renameText = cat.name
                                }) {
                                    HStack {
                                        Text(cat.name).foregroundColor(.primary)
                                        Spacer()
                                        Text("\(store.otherCategoryTree.filter { $0.parentId == cat.id }.count) 个子分类")
                                            .font(.caption).foregroundColor(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .contextMenu {
                        Button("改名") {
                            renamingId = cat.id
                            renameText = cat.name
                        }
                        Button("删除", role: .destructive) { delete(cat) }
                    }
                }
                .onDelete { offsets in
                    for idx in offsets {
                        delete(topLevels[idx])
                    }
                }
                .onMove { from, to in
                    var sorted = topLevels
                    sorted.move(fromOffsets: from, toOffset: to)
                    for (i, cat) in sorted.enumerated() {
                        if let idx = store.otherCategoryTree.firstIndex(where: { $0.id == cat.id }) {
                            store.otherCategoryTree[idx].order = i
                        }
                    }
                    store.save()
                }
            }
        }
        .navigationTitle("其他分类")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}

// 子分类管理
struct OtherSubCategoryView: View {
    @EnvironmentObject private var store: Store
    var parent: OtherCategory
    @State private var newName = ""
    @State private var renamingId: UUID?
    @State private var renameText = ""
    
    private var children: [OtherCategory] {
        store.otherCategoryTree.filter { $0.parentId == parent.id }.sorted { $0.order < $1.order }
    }
    
    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let maxOrder = children.map { $0.order }.max() ?? -1
        store.otherCategoryTree.append(OtherCategory(name: name, parentId: parent.id, order: maxOrder + 1))
        store.save()
        newName = ""
    }
    
    private func delete(_ cat: OtherCategory) {
        store.otherCategoryTree.removeAll { $0.id == cat.id }
        for item in store.otherItems where item.category == cat.name {
            item.category = parent.name
        }
        store.save()
    }
    
    var body: some View {
        List {
            Section {
                HStack {
                    TextField("新增子分类", text: $newName)
                    Button("添加") { add() }
                        .buttonStyle(.borderedProminent)
                        .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("子分类") {
                if children.isEmpty {
                    Text("暂无子分类").font(.caption).foregroundColor(.secondary)
                }
                ForEach(children) { cat in
                    HStack {
                        if renamingId == cat.id {
                            TextField("名称", text: $renameText, onCommit: {
                                let n = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !n.isEmpty, let idx = store.otherCategoryTree.firstIndex(where: { $0.id == cat.id }) {
                                    store.otherCategoryTree[idx].name = n
                                    store.save()
                                }
                                renamingId = nil
                            })
                        } else {
                            Text(cat.name)
                        }
                        Spacer()
                    }
                    .contextMenu {
                        Button("改名") {
                            renamingId = cat.id
                            renameText = cat.name
                        }
                        Button("删除", role: .destructive) { delete(cat) }
                    }
                }
                .onDelete { offsets in
                    for idx in offsets {
                        delete(children[idx])
                    }
                }
                .onMove { from, to in
                    var sorted = children
                    sorted.move(fromOffsets: from, toOffset: to)
                    for (i, cat) in sorted.enumerated() {
                        if let idx = store.otherCategoryTree.firstIndex(where: { $0.id == cat.id }) {
                            store.otherCategoryTree[idx].order = i
                        }
                    }
                    store.save()
                }
            }
        }
        .navigationTitle(parent.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
    }
}
