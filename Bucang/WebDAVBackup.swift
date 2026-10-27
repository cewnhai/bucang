import SwiftUI
import Foundation
import Security

// MARK: - 密码只存钥匙串（Security 框架，iOS 16 安全，无第三方库）
// 服务器地址、用户名、备份文件名存在 UserDefaults；密码绝不进 UserDefaults，
// 也绝不写进代码（仓库是公开的，代码里不能有任何真实地址和账号）。

enum KeychainHelper {
    private static let service = "com.example.bucang.webdav"
    private static let account = "webdav-password"

    static func save(_ password: String) {
        guard let data = password.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8) else { return nil }
        return password
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

// MARK: - WebDAV 备份管理器
// 布局（文档化，恢复时按同一布局找文件）：
//   备份 JSON：<服务器地址>/<备份文件名>，默认 bucang-backup.json
//   图片：    <服务器地址>/bucang-images/<图片文件名>
//   服务器地址由用户在 App 里填，例如 Alist 的 WebDAV 地址通常要带 /dav 后缀，
//   指向服务器根目录很多服务会返回 405。
// 认证：HTTP Basic Auth（Base64 用户名:密码），放在 Authorization 头里。

@MainActor
final class WebDAVManager: ObservableObject {
    @Published var serverURL: String = ""
    @Published var username: String = ""
    @Published var passwordInput: String = ""
    @Published var fileName: String = "bucang-backup.json"
    @Published var statusMessage: String = "尚未备份"
    @Published var errorMessage: String?
    @Published var lastBackupAt: Date?
    @Published var isBusy: Bool = false

    private enum DefaultsKey {
        static let server = "bucang.webdav.serverURL"
        static let username = "bucang.webdav.username"
        static let fileName = "bucang.webdav.fileName"
        static let lastBackupAt = "bucang.webdav.lastBackupAt"
    }

    init() {
        let defaults = UserDefaults.standard
        serverURL = defaults.string(forKey: DefaultsKey.server) ?? ""
        username = defaults.string(forKey: DefaultsKey.username) ?? ""
        let savedName = defaults.string(forKey: DefaultsKey.fileName) ?? ""
        if !savedName.isEmpty { fileName = savedName }
        lastBackupAt = defaults.object(forKey: DefaultsKey.lastBackupAt) as? Date
        passwordInput = KeychainHelper.load() ?? ""
        if lastBackupAt != nil {
            statusMessage = "上次备份：" + Self.dateString(lastBackupAt!)
        }
    }

    static func dateString(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: date)
    }

    func saveSettings() {
        let defaults = UserDefaults.standard
        defaults.set(serverURL.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.server)
        defaults.set(username.trimmingCharacters(in: .whitespacesAndNewlines), forKey: DefaultsKey.username)
        var name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("/") { name.removeFirst() }
        if name.isEmpty { name = "bucang-backup.json" }
        fileName = name
        defaults.set(name, forKey: DefaultsKey.fileName)
        if passwordInput.isEmpty {
            KeychainHelper.delete()
        } else {
            KeychainHelper.save(passwordInput)
        }
        errorMessage = nil
        statusMessage = "设置已保存到本机（密码只在钥匙串里）"
    }

    // MARK: - URL 拼接（正确处理末尾斜杠）

    private func trimmedBase() -> String {
        var base = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        return base
    }

    func backupURL() -> URL? {
        let base = trimmedBase()
        guard !base.isEmpty else { return nil }
        var name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix("/") { name.removeFirst() }
        if name.isEmpty { name = "bucang-backup.json" }
        return URL(string: base + "/" + name)
    }

    private func imagesBaseURL() -> URL? {
        let base = trimmedBase()
        guard !base.isEmpty else { return nil }
        return URL(string: base + "/bucang-images/")
    }

    private func imageURL(for name: String) -> URL? {
        guard let base = imagesBaseURL() else { return nil }
        return base.appendingPathComponent(name)
    }

    private func authHeader() -> String? {
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !user.isEmpty else { return nil }
        let raw = user + ":" + passwordInput
        guard let data = raw.data(using: .utf8) else { return nil }
        return "Basic " + data.base64EncodedString()
    }

    private func request(url: URL, method: String, body: Data? = nil, contentType: String? = nil) -> URLRequest {
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let auth = authHeader() {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        if let contentType {
            req.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        req.httpBody = body
        return req
    }

    private func httpStatus(_ response: URLResponse?) -> Int? {
        (response as? HTTPURLResponse)?.statusCode
    }

    private func plainError(_ error: Error) -> String {
        "网络错误：\(error.localizedDescription)"
    }

    // MARK: - 测试连接
    // 对服务器地址本身发 PROPFIND（Depth: 0）：
    // 200 / 207 / 404 都算“服务器通、账号对”（404 只是还没备份文件），
    // 401 是账号或密码不对，其他状态码如实报出来。不要求备份文件已存在。

    func testConnection() async {
        guard !trimmedBase().isEmpty, let url = URL(string: trimmedBase()) else {
            errorMessage = "请先填写服务器地址"
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        var req = request(url: url, method: "PROPFIND")
        req.setValue("0", forHTTPHeaderField: "Depth")
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            let status = httpStatus(response) ?? -1
            switch status {
            case 200, 207, 404:
                statusMessage = "连接成功：服务器可达，账号验证通过（HTTP \(status)）"
            case 401:
                errorMessage = "连接失败：HTTP 401，用户名或密码不对"
            default:
                errorMessage = "连接失败：服务器返回 HTTP \(status)"
            }
        } catch {
            errorMessage = plainError(error)
        }
    }

    // MARK: - 备份：先传 JSON，再逐张传图片
    // JSON 成功才更新上次备份时间；图片个别失败不推翻 JSON 备份，
    // 但会在状态里列出失败的图片名，不悄悄丢图。

    func backup(store: Store) async {
        guard let url = backupURL() else {
            errorMessage = "请先填写服务器地址"
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let data = StoreData(
            tags: store.tags, materials: store.materials, channels: store.channels,
            fabrics: store.fabrics, usageRecords: store.usageRecords,
            works: store.works, patterns: store.patterns, items: store.items
        )
        guard let json = try? JSONEncoder().encode(data) else {
            errorMessage = "备份失败：本机数据编码失败"
            return
        }
        do {
            let (_, response) = try await URLSession.shared.data(
                for: request(url: url, method: "PUT", body: json, contentType: "application/json")
            )
            let status = httpStatus(response) ?? -1
            guard (200...299).contains(status) else {
                if status == 401 {
                    errorMessage = "备份失败：HTTP 401，用户名或密码不对"
                } else {
                    errorMessage = "备份失败：服务器返回 HTTP \(status)"
                }
                return
            }
        } catch {
            errorMessage = plainError(error)
            return
        }

        // 图片：先尝试建 bucang-images 目录（已存在会返回 405 之类，忽略），再逐张 PUT。
        let imageNames = Array(Set(store.fabrics.flatMap { $0.imageFileNames })).sorted()
        var failedImages: [String] = []
        if !imageNames.isEmpty, let imagesBase = imagesBaseURL() {
            // MKCOL 建目录，失败也继续（目录可能已存在）。
            _ = try? await URLSession.shared.data(for: request(url: imagesBase, method: "MKCOL"))
            for name in imageNames {
                guard let data = FabricImageStore.data(for: name),
                      let imgURL = imageURL(for: name) else {
                    failedImages.append(name)
                    continue
                }
                do {
                    let (_, response) = try await URLSession.shared.data(
                        for: request(url: imgURL, method: "PUT", body: data, contentType: "image/jpeg")
                    )
                    let status = httpStatus(response) ?? -1
                    if !(200...299).contains(status) {
                        failedImages.append(name)
                    }
                } catch {
                    failedImages.append(name)
                }
            }
        }

        lastBackupAt = Date()
        UserDefaults.standard.set(lastBackupAt, forKey: DefaultsKey.lastBackupAt)
        let counts = countsText(store: store)
        if failedImages.isEmpty {
            statusMessage = "备份成功（\(Self.dateString(lastBackupAt!))）：\(counts)，图片 \(imageNames.count) 张"
        } else {
            statusMessage = "备份成功（\(Self.dateString(lastBackupAt!))）：\(counts)，图片有 \(failedImages.count) 张没传上去"
            errorMessage = "没传上去的图片：" + failedImages.prefix(5).joined(separator: "、")
        }
    }

    // MARK: - 恢复：先下 JSON 并校验通过，才替换本机数据
    // JSON 下载失败、HTTP 不是 200、解码失败，都不碰本机数据。
    // 图片逐张下，个别失败不推翻整次恢复，只在状态里列出缺失的图。

    func restore(store: Store) async {
        guard let url = backupURL() else {
            errorMessage = "请先填写服务器地址"
            return
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let jsonData: Data
        do {
            let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "GET"))
            let status = httpStatus(response) ?? -1
            if status == 401 {
                errorMessage = "恢复失败：HTTP 401，用户名或密码不对"
                return
            }
            guard status == 200 else {
                errorMessage = "恢复失败：服务器返回 HTTP \(status)，可能还没有备份文件"
                return
            }
            jsonData = data
        } catch {
            errorMessage = plainError(error)
            return
        }
        guard let decoded = try? JSONDecoder().decode(StoreData.self, from: jsonData) else {
            errorMessage = "恢复失败：云端备份文件解码失败，本机数据没有动"
            return
        }
        // 校验通过后才替换。
        store.tags = decoded.tags
        store.materials = decoded.materials
        store.channels = decoded.channels
        store.fabrics = decoded.fabrics
        store.usageRecords = decoded.usageRecords
        store.works = decoded.works
        store.patterns = decoded.patterns
        store.items = decoded.items
        store.save()

        let imageNames = Array(Set(store.fabrics.flatMap { $0.imageFileNames })).sorted()
        var missingImages: [String] = []
        for name in imageNames {
            guard let imgURL = imageURL(for: name) else {
                missingImages.append(name)
                continue
            }
            do {
                let (data, response) = try await URLSession.shared.data(for: request(url: imgURL, method: "GET"))
                let status = httpStatus(response) ?? -1
                if status == 200 {
                    FabricImageStore.saveData(data, named: name)
                } else {
                    missingImages.append(name)
                }
            } catch {
                missingImages.append(name)
            }
        }
        let counts = countsText(store: store)
        if missingImages.isEmpty {
            statusMessage = "恢复成功：\(counts)，图片 \(imageNames.count) 张"
        } else {
            statusMessage = "恢复成功：\(counts)，但有 \(missingImages.count) 张图片没下回来"
            errorMessage = "缺失的图片：" + missingImages.prefix(5).joined(separator: "、")
        }
    }

    func countsText(store: Store) -> String {
        "布料 \(store.fabrics.count) · 标签 \(store.tags.count) · 材质 \(store.materials.count) · 渠道 \(store.channels.count) · 作品 \(store.works.count) · 纸样 \(store.patterns.count) · 物品 \(store.items.count) · 使用记录 \(store.usageRecords.count)"
    }
}

// MARK: - WebDAV 备份卡片（“我的”页和首页快捷操作共用）

struct WebDAVBackupView: View {
    @EnvironmentObject private var store: Store
    @EnvironmentObject private var webdav: WebDAVManager
    @State private var showingRestoreConfirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "icloud.and.arrow.up")
                    .foregroundColor(Design.accent)
                Text("WebDAV 备份")
                    .font(.headline)
                Spacer()
                if webdav.isBusy {
                    ProgressView()
                }
            }
            Text("把整份数据（含图片）备份到你自己的 WebDAV 服务器，例如家里的 Alist。设置只存在本机，密码只存在系统钥匙串，不会写进代码。")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("服务器地址", text: $webdav.serverURL, prompt: Text("http://服务器IP:端口/dav"))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Text("Alist 这类服务的 WebDAV 地址通常要带 /dav 后缀，不要只填服务器根地址，否则很多服务会返回 405。")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField("用户名", text: $webdav.username, prompt: Text("WebDAV 用户名"))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            SecureField("密码", text: $webdav.passwordInput, prompt: Text("WebDAV 密码"))
                .textFieldStyle(.roundedBorder)
            TextField("备份文件名", text: $webdav.fileName, prompt: Text("bucang-backup.json"))
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
            Text("图片会存在服务器上的 bucang-images/ 目录里，和备份 JSON 在同一服务器地址下。")
                .font(.caption)
                .foregroundColor(.secondary)
            HStack(spacing: 10) {
                Button("保存设置", action: { webdav.saveSettings() })
                    .buttonStyle(.borderedProminent)
                    .tint(Design.accent)
                Button("测试连接") {
                    Task { await webdav.testConnection() }
                }
                .buttonStyle(.bordered)
                .tint(Design.accent)
            }
            HStack(spacing: 10) {
                Button("立即备份") {
                    Task { await webdav.backup(store: store) }
                }
                .buttonStyle(.borderedProminent)
                .tint(Design.accent)
                Button("从云端恢复", role: .destructive) {
                    showingRestoreConfirm = true
                }
                .buttonStyle(.bordered)
            }
            .disabled(webdav.isBusy)
            Text(webdav.statusMessage)
                .font(.caption)
                .foregroundColor(.secondary)
            if let last = webdav.lastBackupAt {
                Text("上次备份：\(WebDAVManager.dateString(last))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            if let error = webdav.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
        .alert("从云端恢复", isPresented: $showingRestoreConfirm) {
            Button("确认恢复", role: .destructive) {
                Task { await webdav.restore(store: store) }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("恢复会覆盖本机全部数据，恢复前请先导出 CSV 或先备份本机数据")
        }
    }
}
