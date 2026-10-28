import SwiftUI

// 布仓 Bucang：原创重做版入口。
// 本机 JSON 存储（Documents/bucang-store.json），图片在 Documents/bucang-images/，
// 不做 iCloud 同步、不做订阅。目标 iOS 16，不用旧数据框架。
// WebDAV 备份是可选的：用户在“我的”页自己填服务器地址，密码只进钥匙串。
@main
struct BucangApp: App {
    @StateObject private var store = Store()
    @StateObject private var webdav = WebDAVManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(webdav)
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: Store
    @State private var pendingShareZipURL: URL?
    @State private var showingShareZipConfirm = false
    @State private var shareZipSummary: String?
    @State private var showingShareZipSummary = false

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("首页", systemImage: "house.fill") }
            FabricListView()
                .tabItem { Label("布料", systemImage: "scissors") }
            CreationView()
                .tabItem { Label("创作", systemImage: "paintbrush") }
            StatsView()
                .tabItem { Label("统计", systemImage: "chart.bar") }
            ProfileView()
                .tabItem { Label("我的", systemImage: "person.crop.circle") }
        }
        .tint(Design.accent)
        // 文件 App 分享直导：用户在文件 App 长按 zip > 分享 > 布仓时，
        // 系统把文件 URL 交给本 App；只认 .zip 后缀，其他文件忽略。
        // 先弹确认，确认后才读文件并走和选择器同一条 ZipBackup.importZip。
        .onOpenURL { url in
            guard url.pathExtension.lowercased() == "zip" else { return }
            pendingShareZipURL = url
            showingShareZipConfirm = true
        }
        .alert("检测到分享的压缩包，是否导入到布仓？", isPresented: $showingShareZipConfirm) {
            Button("导入") {
                guard let url = pendingShareZipURL else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    shareZipSummary = ZipBackup.importZip(data, store: store).text
                } else {
                    shareZipSummary = "读不到分享的压缩包文件。"
                }
                pendingShareZipURL = nil
                showingShareZipSummary = true
            }
            Button("取消", role: .cancel) { pendingShareZipURL = nil }
        } message: {
            Text(pendingShareZipURL?.lastPathComponent ?? "")
        }
        .alert("导入结果", isPresented: $showingShareZipSummary) {
            Button("好", role: .cancel) {}
        } message: {
            Text(shareZipSummary ?? "")
        }
    }
}
