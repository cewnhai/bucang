import SwiftUI

// 布仓 Bucang V3：底部导航只有两项，布仓｜设置。
// 本机 JSON 存储（Documents/bucang-store.json），图片在 Documents/bucang-images/，
// 不做 iCloud 同步、不做订阅。目标 iOS 16。
@main
struct BucangApp: App {
    @StateObject private var store = Store()
    @StateObject private var webdav = WebDAVManager()
    @State private var showingSplash = true

    init() {
        // 返回按钮只留 "<"：把 "Back" 文字设为透明，保留系统右滑返回手势。
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backButtonAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.clear]
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(webdav)
                if showingSplash {
                    SplashView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
            .onAppear {
                // 开屏 2 秒后淡出
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                    withAnimation(.easeOut(duration: 0.5)) {
                        showingSplash = false
                    }
                }
            }
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

// 开屏动画（2026-10-31）：橘白猫猫头线条画，缩放+淡入，配"布仓"字。
struct SplashView: View {
    @State private var scale: CGFloat = 0.8
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 16) {
                Image("SplashCat")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 220, height: 320)
                    .scaleEffect(scale)
                    .opacity(opacity)
                Text("布仓")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundColor(Color(red: 0.91, green: 0.51, blue: 0.05))
                    .opacity(opacity)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                scale = 1.0
            }
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1.0
            }
        }
    }
}
