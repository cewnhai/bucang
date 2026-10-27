import SwiftUI
import SwiftData

// 布仓 Bucang：原创重做版入口。
// 本机 SwiftData，不联网、不做 iCloud 同步、不做订阅，第一版不存图片。
@main
struct BucangApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            Fabric.self,
            Tag.self,
            Material.self,
            Channel.self,
            UsageRecord.self,
            Work.self,
            Pattern.self,
            Item.self
        ])
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
