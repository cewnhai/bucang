import SwiftUI

// 布仓 Bucang：原创重做版入口。
// 本机 JSON 存储（Documents/bucang-store.json），不联网、不做 iCloud 同步、
// 不做订阅，第一版不存图片。目标 iOS 16，不用旧数据框架。
@main
struct BucangApp: App {
    @StateObject private var store = Store()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
        }
    }
}

struct ContentView: View {
    var body: some View {
        TabView {
            FabricListView()
                .tabItem { Label("布料", systemImage: "scissors") }
            WorkListView()
                .tabItem { Label("作品", systemImage: "tshirt") }
            PatternListView()
                .tabItem { Label("纸样", systemImage: "doc") }
            ItemListView()
                .tabItem { Label("物品", systemImage: "bag") }
            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
