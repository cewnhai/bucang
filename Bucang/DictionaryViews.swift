import SwiftUI

// 字典管理（2026-10-31）：渠道/标签/材质的子菜单入口，独立板块
struct DictionaryManagementView: View {
    @EnvironmentObject private var store: Store
    var body: some View {
        List {
            NavigationLink(destination: ChannelSettingsView()) {
                HStack {
                    Text("渠道")
                    Spacer()
                    Text("\(store.channelOptions.count) 条").foregroundColor(.secondary).font(.caption)
                }
            }
            NavigationLink(destination: TagSettingsView()) {
                HStack {
                    Text("标签")
                    Spacer()
                    Text("\(store.tags.count) 个").foregroundColor(.secondary).font(.caption)
                }
            }
            NavigationLink(destination: MaterialSettingsView()) {
                HStack {
                    Text("材质")
                    Spacer()
                    Text("\(store.materialOptions.count) 条").foregroundColor(.secondary).font(.caption)
                }
            }
        }
        .navigationTitle("字典管理")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// 渠道设置明细（2026-10-31）：从设置页迁移
struct ChannelSettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newChannel = ""
    @State private var renamingChannel: String?
    @State private var renameText = ""
    var body: some View {
        Form {
            Section("新增渠道") {
                HStack {
                    TextField("渠道名称", text: $newChannel)
                    Button("添加") {
                        let name = newChannel.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !store.channelOptions.contains(name) else { return }
                        store.channelOptions.append(name); store.save(); newChannel = ""
                    }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                    .disabled(newChannel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("渠道列表") {
                ForEach(store.channelOptions, id: \.self) { option in
                    HStack {
                        Text(option)
                        Spacer()
                        Button("改名") { renamingChannel = option; renameText = option }
                            .font(.caption)
                        Button("删除", role: .destructive) {
                            store.channelOptions.removeAll { $0 == option }; store.save()
                        }
                        .font(.caption)
                    }
                }
            }
            Section {
                Text("布料渠道与出售渠道的选项；商家是渠道下二级自定义文本，在布料/出售表单里填。筛选面板的渠道组读这里，外加数据里已有但不在选项里的渠道名，旧数据仍可筛选。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("渠道")
        .navigationBarTitleDisplayMode(.inline)
        .alert("改名", isPresented: Binding(get: { renamingChannel != nil }, set: { if !$0 { renamingChannel = nil } })) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let old = renamingChannel {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty, let idx = store.channelOptions.firstIndex(of: old) {
                        store.channelOptions[idx] = name; store.save()
                    }
                }
                renamingChannel = nil
            }
            Button("取消", role: .cancel) { renamingChannel = nil }
        }
    }
}

// 材质设置明细（2026-10-31）：从设置页迁移
struct MaterialSettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newMaterial = ""
    @State private var renamingMaterial: String?
    @State private var renameText = ""
    var body: some View {
        Form {
            Section("新增材质") {
                HStack {
                    TextField("材质名称", text: $newMaterial)
                    Button("添加") {
                        let name = newMaterial.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty, !store.materialOptions.contains(name) else { return }
                        store.materialOptions.append(name); store.save(); newMaterial = ""
                    }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                    .disabled(newMaterial.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("材质列表") {
                ForEach(store.materialOptions, id: \.self) { option in
                    HStack {
                        Text(option)
                        Spacer()
                        Button("改名") { renamingMaterial = option; renameText = option }
                            .font(.caption)
                        Button("删除", role: .destructive) {
                            store.materialOptions.removeAll { $0 == option }; store.save()
                        }
                        .font(.caption)
                    }
                }
            }
            Section {
                Text("布料材质单选的选项，筛选面板直接读这里。")
                    .font(.caption).foregroundColor(.secondary)
            }
        }
        .navigationTitle("材质")
        .navigationBarTitleDisplayMode(.inline)
        .alert("改名", isPresented: Binding(get: { renamingMaterial != nil }, set: { if !$0 { renamingMaterial = nil } })) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let old = renamingMaterial {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty, let idx = store.materialOptions.firstIndex(of: old) {
                        store.materialOptions[idx] = name; store.save()
                    }
                }
                renamingMaterial = nil
            }
            Button("取消", role: .cancel) { renamingMaterial = nil }
        }
    }
}

// 标签设置明细（2026-10-31）：左填名称右加按钮格式
struct TagSettingsView: View {
    @EnvironmentObject private var store: Store
    @State private var newName = ""
    @State private var renamingTag: Tag?
    @State private var renameText = ""
    var body: some View {
        Form {
            Section("新增标签") {
                HStack {
                    TextField("标签名称", text: $newName)
                    Button("添加") {
                        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        if !store.tags.contains(where: { $0.name == name }) {
                            store.addTag(Tag(name: name, sortOrder: store.tags.count))
                            store.save()
                        }
                        newName = ""
                    }
                    .buttonStyle(.borderedProminent).tint(Design.accent)
                    .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            Section("标签列表") {
                ForEach(store.tags.sorted { $0.sortOrder < $1.sortOrder }) { tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                        Button("改名") { renamingTag = tag; renameText = tag.name }
                            .font(.caption)
                        Button("删除", role: .destructive) {
                            store.tags.removeAll { $0.id == tag.id }
                            store.save()
                        }
                        .font(.caption)
                    }
                }
            }
        }
        .navigationTitle("标签")
        .navigationBarTitleDisplayMode(.inline)
        .alert("改名", isPresented: Binding(get: { renamingTag != nil }, set: { if !$0 { renamingTag = nil } })) {
            TextField("新名称", text: $renameText)
            Button("确定") {
                if let tag = renamingTag {
                    let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !name.isEmpty {
                        tag.name = name
                        store.save()
                    }
                }
                renamingTag = nil
            }
            Button("取消", role: .cancel) { renamingTag = nil }
        }
    }
}
