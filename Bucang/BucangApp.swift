import SwiftUI

// 布仓 Bucang V3：底部导航只有两项，布仓｜设置。
// 本机 JSON 存储（Documents/bucang-store.json），图片在 Documents/bucang-images/，
// 不做 iCloud 同步、不做订阅。目标 iOS 16。
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
            BucangView()
                .tabItem { Label("布仓", systemImage: "square.grid.2x2") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
        .tint(Design.accent)
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
