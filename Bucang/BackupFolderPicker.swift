import SwiftUI

// MARK: - 备份目录选择器
// 通用：浏览远程目录、选择目标目录、新建文件夹

struct RemoteFolder: Identifiable, Hashable {
    let id: String  // Quark 用 fid，WebDAV 用 path
    let name: String
    let path: String
}

// MARK: - 目录服务协议
@MainActor
protocol FolderService: AnyObject {
    func listFolders(path: String) async throws -> [RemoteFolder]
    func createFolder(name: String, in path: String) async throws
    var displayName: String { get }
}

// MARK: - 目录选择器视图
struct BackupFolderPickerView: View {
    @Environment(\.dismiss) var dismiss
    var service: FolderService
    var currentPath: String
    var onSelect: (RemoteFolder) -> Void

    @State private var folders: [RemoteFolder] = []
    @State private var pathStack: [(id: String, name: String, path: String)] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showingCreate = false
    @State private var newFolderName = ""

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else {
                    ForEach(folders) { folder in
                        Button(action: {
                            // 进入子目录
                            pathStack.append((folder.id, folder.name, folder.path))
                            loadFolders()
                        }) {
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundColor(.orange)
                                Text(folder.name)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                if let error = errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                }
            }
            .navigationTitle(pathStack.last?.name ?? "选择目标目录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingCreate = true }) {
                        Image(systemName: "plus")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确定") {
                        let selected = pathStack.last.map {
                            RemoteFolder(id: $0.id, name: $0.name, path: $0.path)
                        } ?? RemoteFolder(id: "", name: "根目录", path: currentPath)
                        onSelect(selected)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .alert("新建文件夹", isPresented: $showingCreate) {
                TextField("文件夹名称", text: $newFolderName)
                Button("取消", role: .cancel) {}
                Button("创建") {
                    Task { await createFolder() }
                }
            }
            .onAppear {
                // 初始化路径栈
                if pathStack.isEmpty && !currentPath.isEmpty {
                    pathStack.append(("", "根目录", currentPath))
                }
                loadFolders()
            }
        }
    }

    private func loadFolders() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let path = pathStack.last?.path ?? currentPath
                let result = try await service.listFolders(path: path)
                await MainActor.run {
                    folders = result
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = "加载失败：\(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func createFolder() async {
        let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        do {
            let path = pathStack.last?.path ?? currentPath
            try await service.createFolder(name: name, in: path)
            await MainActor.run {
                newFolderName = ""
                loadFolders()
            }
        } catch {
            await MainActor.run {
                errorMessage = "创建失败：\(error.localizedDescription)"
            }
        }
    }
}
