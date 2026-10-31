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
    @State private var pawOffset: CGFloat = -60
    @State private var pawRotation: Double = -20
    @State private var yarnScale: CGFloat = 0.5
    @State private var showYarnText = false

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 8) {
                // 猫咪图
                Image("SplashCat")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 200, height: 290)
                    .scaleEffect(scale)
                    .opacity(opacity)
                // 毛线团 + 猫爪拍动画（2026-10-31）
                ZStack {
                    // 毛线团
                    ZStack {
                        Circle()
                            .fill(Color(red: 0.98, green: 0.95, blue: 0.88))
                            .frame(width: 90, height: 90)
                            .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
                        // 毛线纹理（弧线）
                        ForEach(0..<3) { i in
                            Circle()
                                .trim(from: 0.1, to: 0.9)
                                .stroke(Color(red: 0.91, green: 0.51, blue: 0.05).opacity(0.4), lineWidth: 3)
                                .frame(width: 70 - CGFloat(i * 15), height: 70 - CGFloat(i * 15))
                                .rotationEffect(.degrees(Double(i * 60)))
                        }
                        // 布仓艺术字
                        Text("布仓")
                            .font(.system(size: 28, weight: .black, design: .rounded))
                            .foregroundColor(Color(red: 0.91, green: 0.51, blue: 0.05))
                            .opacity(showYarnText ? 1 : 0)
                    }
                    .scaleEffect(yarnScale)
                    // 猫爪（拍的动作）
                    Text("🐾")
                        .font(.system(size: 44))
                        .offset(x: 40, y: pawOffset)
                        .rotationEffect(.degrees(pawRotation))
                        .opacity(opacity)
                }
                .frame(height: 120)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.8, dampingFraction: 0.7)) {
                scale = 1.0
            }
            withAnimation(.easeIn(duration: 0.6)) {
                opacity = 1.0
            }
            // 毛线团弹出
            withAnimation(.spring(response: 0.6, dampingFraction: 0.6).delay(0.5)) {
                yarnScale = 1.0
            }
            withAnimation(.easeIn(duration: 0.4).delay(0.8)) {
                showYarnText = true
            }
            // 猫爪拍两下
            withAnimation(.easeInOut(duration: 0.35).delay(0.9)) {
                pawOffset = 10
                pawRotation = 10
            }
            withAnimation(.easeInOut(duration: 0.35).delay(1.25)) {
                pawOffset = -60
                pawRotation = -20
            }
            withAnimation(.easeInOut(duration: 0.35).delay(1.6)) {
                pawOffset = 10
                pawRotation = 10
            }
            withAnimation(.easeInOut(duration: 0.35).delay(1.95)) {
                pawOffset = -60
                pawRotation = -20
            }
        }
    }
}
