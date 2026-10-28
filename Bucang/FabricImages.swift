import SwiftUI
import PhotosUI
import UIKit
import AVKit

// MARK: - 布料视频存储（Documents/bucang-videos/<UUID>.mov）
// 与图片存储同 pattern：JSON 里只存文件名，字节存文件；删布料/删视频时删文件。
enum FabricVideoStore {
    static let directoryName = "bucang-videos"
    static func directoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName)
    }
    static func fileURL(for name: String) -> URL? {
        directoryURL()?.appendingPathComponent(name)
    }
    @discardableResult
    static func saveData(_ data: Data) -> String? {
        guard let dir = directoryURL() else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".mov"
        do { try data.write(to: dir.appendingPathComponent(name), options: .atomic); return name } catch { return nil }
    }
    static func delete(named name: String) {
        guard let url = fileURL(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

// 视频列表编辑器：从相册选视频（PhotosPicker .videos），点行播放（VideoPlayer）。
struct FabricVideoEditor: View {
    @Binding var videoNames: [String]
    var deleteFilesImmediately: Bool
    var onNamesChanged: () -> Void
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var playingURL: URL?
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if videoNames.isEmpty {
                Text("还没有视频").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(videoNames, id: \.self) { name in
                    HStack {
                        Image(systemName: "video.fill").foregroundColor(Design.accent)
                        Text(name).font(.caption).lineLimit(1)
                        Spacer()
                        Button("播放") {
                            if let url = FabricVideoStore.fileURL(for: name) { playingURL = url }
                        }.font(.caption)
                        Button(action: {
                            videoNames.removeAll { $0 == name }
                            if deleteFilesImmediately { FabricVideoStore.delete(named: name) }
                            onNamesChanged()
                        }) {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }.buttonStyle(.plain)
                    }
                }
            }
            PhotosPicker(selection: $selectedItems, matching: .videos, photoLibrary: .shared()) {
                Label("从相册选视频", systemImage: "video")
            }
            .buttonStyle(.bordered).tint(Design.accent)
            Text("视频存在本机 bucang-videos/，不进 JSON，只存文件名。").font(.caption).foregroundColor(.secondary)
        }
        .onChange(of: selectedItems) { items in
            guard !items.isEmpty else { return }
            let toLoad = items; selectedItems = []
            Task {
                for item in toLoad {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let name = FabricVideoStore.saveData(data) {
                        videoNames.append(name); onNamesChanged()
                    }
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { playingURL != nil },
            set: { if !$0 { playingURL = nil } }
        )) {
            if let url = playingURL {
                VideoPlayer(player: AVPlayer(url: url))
                    .ignoresSafeArea()
            }
        }
    }
}

// MARK: - 布料图片存储
// 图片字节不进 bucang-store.json，只存文件名在 Fabric.imageFileNames 里。
// 文件：Documents/bucang-images/<UUID>.jpg，JPEG，
// 长边压到约 1600px，质量 0.8，兼顾清晰度和体积。

enum FabricImageStore {
    static let directoryName = "bucang-images"

    static func directoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(directoryName)
    }

    static func fileURL(for name: String) -> URL? {
        directoryURL()?.appendingPathComponent(name)
    }

    private static func ensureDirectory() -> URL? {
        guard let dir = directoryURL() else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 把 UIImage 压成 JPEG 存盘，返回文件名；失败返回 nil。
    static func saveUIImage(_ image: UIImage) -> String? {
        guard let resized = resized(image, maxLongEdge: 1600),
              let data = resized.jpegData(compressionQuality: 0.8),
              let dir = ensureDirectory() else { return nil }
        let name = UUID().uuidString + ".jpg"
        let url = dir.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
            return name
        } catch {
            return nil
        }
    }

    /// 恢复（WebDAV / 其他来源）时按原文件名直接写盘，覆盖同名旧文件。
    @discardableResult
    static func saveData(_ data: Data, named name: String) -> Bool {
        guard let dir = ensureDirectory() else { return false }
        do {
            try data.write(to: dir.appendingPathComponent(name), options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func data(for name: String) -> Data? {
        guard let url = fileURL(for: name) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func loadImage(named name: String) -> UIImage? {
        guard let data = data(for: name) else { return nil }
        return UIImage(data: data)
    }

    static func delete(named name: String) {
        guard let url = fileURL(for: name) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private static func resized(_ image: UIImage, maxLongEdge: CGFloat) -> UIImage? {
        let w = image.size.width
        let h = image.size.height
        guard w > 0, h > 0 else { return image }
        let longEdge = max(w, h)
        guard longEdge > maxLongEdge else { return image }
        let scale = maxLongEdge / longEdge
        let newSize = CGSize(width: w * scale, height: h * scale)
        // UIGraphicsImageRenderer：iOS 10+，iOS 16 安全。
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - 相机选取（UIImagePickerController 封装，iOS 16 安全）
// 只在设备支持相机时才显示相机按钮；不支持时按钮不出现，不会崩。

struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    var onCancel: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onCancel: onCancel)
    }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onImage: (UIImage) -> Void
        var onCancel: () -> Void
        init(onImage: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onImage = onImage
            self.onCancel = onCancel
        }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            } else {
                onCancel()
            }
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}

// MARK: - 布料图片编辑器（详情页和编辑页共用）
// deleteFilesImmediately = true：详情页，删图即删文件（即时生效）。
// deleteFilesImmediately = false：编辑页，删图只从列表里去掉，
// 文件由编辑页在“保存”时删（被去掉的旧图）、在“取消”时删（新加的图），
// 这样点取消不会把原来图片弄丢。
struct FabricImageEditor: View {
    @Binding var imageNames: [String]
    var deleteFilesImmediately: Bool
    var onNamesChanged: () -> Void

    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var previewName: String?

    private var canUseCamera: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private func addImage(_ image: UIImage) {
        if let name = FabricImageStore.saveUIImage(image) {
            imageNames.append(name)
            onNamesChanged()
        }
    }

    private func removeImage(_ name: String) {
        imageNames.removeAll { $0 == name }
        if deleteFilesImmediately {
            FabricImageStore.delete(named: name)
        }
        onNamesChanged()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if imageNames.isEmpty {
                Text("还没有图片，点下面按钮为这块布料加一张")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(imageNames, id: \.self) { name in
                            ZStack(alignment: .topTrailing) {
                                if let uiImage = FabricImageStore.loadImage(named: name) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 96, height: 96)
                                        .clipped()
                                        .cornerRadius(12)
                                        .onTapGesture { previewName = name }
                                } else {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(width: 96, height: 96)
                                        .overlay(Image(systemName: "photo").foregroundColor(.secondary))
                                }
                                Button(action: { removeImage(name) }) {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundColor(.white)
                                        .background(Circle().fill(Color.black.opacity(0.6)))
                                }
                                .buttonStyle(.plain)
                                .padding(4)
                            }
                        }
                    }
                }
                Text("点图片可放大看，第一张会用作列表封面")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            HStack(spacing: 10) {
                PhotosPicker(selection: $selectedItems, matching: .images, photoLibrary: .shared()) {
                    Label("从相册选图", systemImage: "photo.on.rectangle")
                }
                .buttonStyle(.bordered)
                .tint(Design.accent)
                if canUseCamera {
                    Button(action: { showingCamera = true }) {
                        Label("拍照", systemImage: "camera")
                    }
                    .buttonStyle(.bordered)
                    .tint(Design.accent)
                }
            }
        }
        .onChange(of: selectedItems) { items in
            guard !items.isEmpty else { return }
            let toLoad = items
            selectedItems = []
            Task {
                for item in toLoad {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        addImage(image)
                    }
                }
            }
        }
        .sheet(isPresented: $showingCamera) {
            CameraPicker(
                onImage: { image in
                    showingCamera = false
                    addImage(image)
                },
                onCancel: { showingCamera = false }
            )
        }
        .fullScreenCover(item: Binding(
            get: { previewName.map { PreviewItem(name: $0) } },
            set: { previewName = $0?.name }
        )) { item in
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                if let uiImage = FabricImageStore.loadImage(named: item.name) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .ignoresSafeArea()
                }
                Button(action: { previewName = nil }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundColor(.white)
                        .padding()
                }
            }
        }
    }

    private struct PreviewItem: Identifiable {
        var name: String
        var id: String { name }
    }
}

// 列表封面小图：有图显示首图，无图显示剪刀占位。
struct FabricCoverView: View {
    var fabric: Fabric
    var size: CGFloat = 56
    var body: some View {
        if let first = fabric.imageFileNames.first,
           let uiImage = FabricImageStore.loadImage(named: first) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipped()
                .cornerRadius(12)
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Design.accentSoft)
                .frame(width: size, height: size)
                .overlay(
                    Image(systemName: "scissors")
                        .foregroundColor(Design.accent)
                )
        }
    }
}
