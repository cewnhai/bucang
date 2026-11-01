import SwiftUI
import WebKit
import CryptoKit
import Security

// MARK: - 夸克网盘备份
// 基于夸克官方 Agent Skill 的 API（drive-pc.quark.cn），非官方 iOS SDK
// OAuth 授权 + 分片上传 + 下载

// MARK: - Token 存储（钥匙串）
private enum QuarkKeychain {
    static let service = "com.example.bucang.quark"
    static let account = "oauth-token"

    static func save(_ token: String) {
        let data = Data(token.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - 夸克 API 客户端
@MainActor
class QuarkManager: ObservableObject {
    static let shared = QuarkManager()

    @Published var isAuthorized = false
    @Published var isBusy = false
    @Published var statusMessage = ""
    @Published var userNickname = ""
    @Published var backupFolderName = "喵了个咪备份"
    @Published var backupFolderFid = "0"
    @Published var showingFolderPicker = false

    private let baseURL = "https://drive-pc.quark.cn"
    private var authCookie: String? { QuarkKeychain.load() }

    init() {
        isAuthorized = QuarkKeychain.load() != nil
    }

    // MARK: - OAuth 登录
    @Published var showingLoginWeb = false

    func login() {
        // 打开网页登录，用户手动登录后提取 Cookie
        showingLoginWeb = true
    }

    func completeLoginWithCookies(_ cookies: [HTTPCookie]) {
        // 提取关键 Cookie 并保存
        let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !cookieString.isEmpty {
            QuarkKeychain.save(cookieString)
            isAuthorized = true
            statusMessage = "登录成功"
            showingLoginWeb = false
            Task { await fetchUserInfo() }
        } else {
            statusMessage = "未获取到登录信息，请确认已登录"
        }
    }


    func logout() {
        QuarkKeychain.delete()
        isAuthorized = false
        userNickname = ""
        statusMessage = "已取消授权"
    }

    // MARK: - 用户信息
    func fetchUserInfo() async {
        guard let token = authCookie else { return }
        let url = URL(string: "\(baseURL)/1/clouddrive/member?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "Cookie")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        do {
            let (data, _) = try await URLSession.shared.data(for: request)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let dataDict = json["data"] as? [String: Any],
               let nickname = dataDict["nickname"] as? String {
                userNickname = nickname
            }
        } catch {
            // 忽略错误
        }
    }

    // MARK: - 文件上传
    func uploadBackup(data: Data, fileName: String) async -> Bool {
        guard let token = authCookie else {
            statusMessage = "请先授权登录"
            return false
        }
        isBusy = true
        statusMessage = "正在上传..."
        defer { isBusy = false }

        do {
            // 1. 计算 MD5 和 SHA1
            let md5 = data.md5Hex
            let sha1 = data.sha1Hex

            // 2. 预上传
            let preResult = try await preUpload(fileName: fileName, size: data.count, token: token)
            guard let taskId = preResult["task_id"] as? String,
                  let uploadId = preResult["upload_id"] as? String,
                  let objKey = preResult["obj_key"] as? String,
                  let bucket = preResult["bucket"] as? String else {
                statusMessage = "预上传失败"
                return false
            }

            // 3. 更新哈希（秒传检查）
            let hashResult = try await updateHash(md5: md5, sha1: sha1, taskId: taskId, token: token)
            if let finish = hashResult["finish"] as? Bool, finish {
                // 秒传成功
                statusMessage = "上传成功（秒传）"
                return true
            }

            // 4. 获取上传授权并直传 OSS（单分片）
            let authResult = try await getUploadAuth(taskId: taskId, uploadId: uploadId, token: token)
            // bucket 和 objKey 已从 preUpload 结果解析
            // authResult 中包含 OSS 临时凭证，实际地址格式：
            // https://{bucket}.oss-cn-zhangjiakou.aliyuncs.com/{obj_key}
            let ossURLString = "https://\(bucket).oss-cn-zhangjiakou.aliyuncs.com/\(objKey)"
            guard let ossURL = URL(string: ossURLString) else {
                statusMessage = "OSS 地址无效"
                return false
            }
            var ossRequest = URLRequest(url: ossURL)
            ossRequest.httpMethod = "PUT"
            ossRequest.httpBody = data
            ossRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
            let (_, ossResponse) = try await URLSession.shared.data(for: ossRequest)
            if let http = ossResponse as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                statusMessage = "OSS 上传失败（HTTP \(http.statusCode)）"
                return false
            }

            // 5. 完成上传
            _ = try await finishUpload(taskId: taskId, token: token)
            statusMessage = "上传成功"
            return true
        } catch {
            statusMessage = "上传失败：\(error.localizedDescription)"
            return false
        }
    }

    private func preUpload(fileName: String, size: Int, token: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/1/clouddrive/file/upload/pre?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        request.setValue(token, forHTTPHeaderField: "Cookie")
        let now = Int(Date().timeIntervalSince1970 * 1000)
        let body: [String: Any] = [
            "ccp_hash_update": true,
            "parallel_upload": true,
            "pdir_fid": backupFolderFid,
            "dir_name": "",
            "file_name": fileName,
            "format_type": "application/zip",
            "l_created_at": now,
            "l_updated_at": now,
            "size": size
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "预上传响应解析失败"])
        }
        return dataDict
    }

    private func updateHash(md5: String, sha1: String, taskId: String, token: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/1/clouddrive/file/update/hash?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        request.setValue(token, forHTTPHeaderField: "Cookie")
        let body: [String: Any] = [
            "md5": md5,
            "sha1": sha1,
            "task_id": taskId
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any] else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "哈希更新响应解析失败"])
        }
        return dataDict
    }

    private func getUploadAuth(taskId: String, uploadId: String, token: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/1/clouddrive/file/upload/auth?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        request.setValue(token, forHTTPHeaderField: "Cookie")
        let body: [String: Any] = [
            "task_id": taskId,
            "upload_id": uploadId,
            "auth_type": "cos"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        let raw = String(data: data, encoding: .utf8) ?? ""
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传授权非 JSON：\(raw.prefix(200))"])
        }
        // 兼容：data 可能在顶层或嵌套
        if let dataDict = json["data"] as? [String: Any] {
            return dataDict
        }
        // 如果顶层就是数据，直接返回
        if json["auth_info"] != nil || json["auth_key"] != nil {
            return json
        }
        throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "上传授权格式未知：\(raw.prefix(200))"])
    }

    private func finishUpload(taskId: String, token: String) async throws -> [String: Any] {
        let url = URL(string: "\(baseURL)/1/clouddrive/file/upload/finish?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        request.setValue(token, forHTTPHeaderField: "Cookie")
        let body: [String: Any] = ["task_id": taskId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "完成上传响应解析失败"])
        }
        return json
    }

    // MARK: - 备份/恢复
    func backup(store: Store) async {
        guard isAuthorized else {
            statusMessage = "请先授权登录"
            return
        }
        isBusy = true
        statusMessage = "正在生成备份..."
        defer { isBusy = false }
        // 生成 StoreData JSON（与 WebDAV 一致）
        let data = StoreData(
            tags: store.tags, materials: store.materials, channels: store.channels,
            fabrics: store.fabrics, usageRecords: store.usageRecords,
            works: store.works, patterns: store.patterns, items: store.items,
            saleRecords: store.saleRecords, otherItems: store.otherItems, wishlistItems: store.wishlistItems,
            brainstorms: store.brainstorms,
            materialOptions: store.materialOptions, otherCategories: store.otherCategories,
            lengthUnit: store.lengthUnit, hideAmounts: store.hideAmounts, codePrefix: store.codePrefix,
            channelOptions: store.channelOptions, patternOptions: store.patternOptions, codeLevels: store.codeLevels,
            visibleTabs: store.visibleTabs, themeName: store.themeName
        )
        guard let json = try? JSONEncoder().encode(data) else {
            statusMessage = "备份失败：数据编码失败"
            return
        }
        statusMessage = "正在上传备份文件..."
        let ok = await uploadBackup(data: json, fileName: "bucang-backup.json")
        if ok {
            statusMessage = "备份成功"
        }
        // 图片备份后续版本再加
    }

    func restore(store: Store) async {
        statusMessage = "恢复功能开发中（先用备份文件手动恢复）"
    }
}


// MARK: - Data 哈希扩展
private extension Data {
    var md5Hex: String {
        let digest = Insecure.MD5.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    var sha1Hex: String {
        let digest = Insecure.SHA1.hash(data: self)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - 夸克备份 UI
struct QuarkBackupView: View {
    @EnvironmentObject private var store: Store
    @StateObject private var quark = QuarkManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cloud.fill")
                    .foregroundColor(Design.accent)
                Text("夸克网盘备份")
                    .font(.headline)
                Spacer()
                if quark.isBusy {
                    ProgressView()
                }
            }
            Text("把整份数据备份到夸克网盘。需要先授权登录，Token 只存系统钥匙串。")
                .font(.caption)
                .foregroundColor(.secondary)
            if quark.isAuthorized {
                if !quark.userNickname.isEmpty {
                    Text("已登录：\(quark.userNickname)")
                        .font(.subheadline)
                }
                HStack {
                    Text("备份目录：")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text(quark.backupFolderName)
                        .font(.subheadline)
                    Spacer()
                    Button("选择目录") {
                        quark.showingFolderPicker = true
                    }
                    .font(.subheadline)
                }
                HStack(spacing: 10) {
                    Button("立即备份") {
                        Task { await quark.backup(store: store) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Design.accent)
                    Button("从夸克恢复") {
                        Task { await quark.restore(store: store) }
                    }
                    .buttonStyle(.bordered)
                    .tint(Design.accent)
                    Button("取消授权") {
                        quark.logout()
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                }
            } else {
                Button("授权登录夸克网盘") {
                    quark.login()
                }
                .buttonStyle(.borderedProminent)
                .tint(Design.accent)
            }
            if !quark.statusMessage.isEmpty {
                Text(quark.statusMessage)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text("注意：夸克未提供官方 iOS SDK，此功能基于非官方 API，接口变更可能导致不可用。")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .padding(16)
        .background(Design.card)
        .cornerRadius(Design.corner)
        .sheet(isPresented: $quark.showingLoginWeb) {
            QuarkLoginWebView()
                .environmentObject(quark)
        }
        .sheet(isPresented: $quark.showingFolderPicker) {
            BackupFolderPickerView(
                service: quark,
                currentPath: quark.backupFolderFid,
                onSelect: { folder in
                    quark.backupFolderFid = folder.id
                    quark.backupFolderName = folder.name
                }
            )
        }
    }
}

// MARK: - 夸克网页登录
struct QuarkLoginWebView: View {
    @EnvironmentObject var quark: QuarkManager
    @Environment(\.dismiss) var dismiss
    @State private var webview: WKWebView?

    var body: some View {
        NavigationStack {
            QuarkWebViewRepresentable(webview: $webview)
            .navigationTitle("登录夸克网盘")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成登录") {
                        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
                            let quarkCookies = cookies.filter { $0.domain.contains("quark.cn") }
                            DispatchQueue.main.async {
                                quark.completeLoginWithCookies(quarkCookies)
                            }
                        }
                    }
                }
            }
        }
    }
}

struct QuarkWebViewRepresentable: UIViewRepresentable {
    @Binding var webview: WKWebView?

    func makeUIView(context: Context) -> WKWebView {
        let wv = WKWebView()
        // 用 PC 的 UA，避免跳到移动端下载页
        wv.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
        if let url = URL(string: "https://pan.quark.cn") {
            wv.load(URLRequest(url: url))
        }
        DispatchQueue.main.async { webview = wv }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Quark 目录服务
extension QuarkManager: FolderService {
    var displayName: String { "夸克网盘" }

    func listFolders(path: String) async throws -> [RemoteFolder] {
        guard let cookie = authCookie else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "未授权"])
        }
        let fid = path.isEmpty ? "0" : path
        let urlString = "https://drive-pc.quark.cn/1/clouddrive/file/sort?pr=ucpro&fr=pc&uc_param_str=&pdir_fid=\(fid)&_page=1&_size=100&_fetch_total=1&_fetch_sub_dirs=0&_sort=file_type:asc,updated_at:desc"
        guard let url = URL(string: urlString) else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "URL 无效"])
        }
        var request = URLRequest(url: url)
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let dataDict = json["data"] as? [String: Any],
              let list = dataDict["list"] as? [[String: Any]] else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "解析失败"])
        }
        return list.compactMap { item -> RemoteFolder? in
            guard let fid = item["fid"] as? String,
                  let name = item["file_name"] as? String,
                  let type = item["file_type"] as? Int, type == 0 else { return nil }
            return RemoteFolder(id: fid, name: name, path: fid)
        }
    }

    func createFolder(name: String, in path: String) async throws {
        guard let cookie = authCookie else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "未授权"])
        }
        let fid = path.isEmpty ? "0" : path
        let url = URL(string: "https://drive-pc.quark.cn/1/clouddrive/file?pr=ucpro&fr=pc&uc_param_str=")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(cookie, forHTTPHeaderField: "Cookie")
        request.setValue("https://pan.quark.cn/", forHTTPHeaderField: "Referer")
        let body: [String: Any] = [
            "pdir_fid": fid,
            "file_name": name,
            "dir_init_lock": false
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? Int, status == 200 else {
            throw NSError(domain: "Quark", code: -1, userInfo: [NSLocalizedDescriptionKey: "创建失败"])
        }
    }
}
