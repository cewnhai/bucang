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
    }
}
