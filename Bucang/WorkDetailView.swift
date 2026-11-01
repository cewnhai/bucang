import SwiftUI
import UIKit

// 成品详情页（2026-11-01）：统一为布料详情布局（照片头 + 摘要卡 + 可折叠分区）
struct WorkDetailView: View {
@EnvironmentObject private var store: Store
@Environment(\.dismiss) private var dismiss
var work: Work
@State private var showingEdit = false
@State private var showingDelete = false
@State private var showingBrainstormPicker = false
@State private var headerPhotoIndex = 0
@State private var previewName: String?
// 长图 / 分享
@State private var showingLongImage = false
@State private var longImage: UIImage?
@State private var shareFileItem: ShareURLItem?
@State private var sharePDFItem: ShareURLItem?
/// 用于.sheet(item:) 驱动分享，避免白屏
struct ShareURLItem: Identifiable {
let id = UUID()
let url: URL
}
private var themeAccent: Color { ThemeHelper.accent(store.themeName)}

// MARK: - 照片头（多图轮播）
private var photoHeader: some View {
ZStack(alignment:.topTrailing) {
if work.imageFileNames.isEmpty {
RoundedRectangle(cornerRadius: 16)
.fill(ThemeHelper.accentSoft(store.themeName))
.aspectRatio(4 / 3, contentMode:.fit)
.overlay(
Image(systemName: "hammer")
.font(.largeTitle)
.foregroundColor(themeAccent)
)
} else {
TabView(selection: $headerPhotoIndex) {
ForEach(Array(work.imageFileNames.enumerated()), id: \.element) { idx, name in
Group {
if let uiImage = FabricImageStore.loadImage(named: name) {
Image(uiImage: uiImage)
.resizable()
.scaledToFill()
} else {
Color.gray.opacity(0.15)
}
}
.tag(idx)
.onTapGesture { previewName = name}
}
}
.tabViewStyle(PageTabViewStyle(indexDisplayMode:.never))
.aspectRatio(4 / 3, contentMode:.fit)
.cornerRadius(16)
.clipped()
}
if work.imageFileNames.count > 1 {
Text("\(headerPhotoIndex + 1) / \(work.imageFileNames.count)")
.font(.caption).foregroundColor(.white)
.padding(.horizontal, 8).padding(.vertical, 4)
.background(Color.black.opacity(0.45))
.cornerRadius(10)
.padding(8)
}
}
}

// MARK: - 摘要卡
private var summaryCard: some View {
VStack(alignment:.leading, spacing: 8) {
HStack {
Text("编号：\(work.code.isEmpty ? "—": work.code)")
.font(.caption).foregroundColor(.secondary)
Spacer()
Text(work.isFinished ? "已完成": "制作中")
.font(.caption).fontWeight(.semibold)
.foregroundColor(.white)
.padding(.horizontal, 8).padding(.vertical, 4)
.background(work.isFinished? Color.green: themeAccent)
.cornerRadius(10)
}
Text(work.name.isEmpty ? "未命名成品": work.name)
.font(.title3).fontWeight(.bold)
HStack(spacing: 16) {
if !work.colorName.isEmpty {
Text("颜色：\(work.colorName)").font(.subheadline).foregroundColor(.secondary)
}
Text("总成本 ¥\(String(format: "%.2f", store.workTotalCost(for: work)))")
.font(.subheadline).foregroundColor(.orange)
}
if work.isSold {
Text("已售出\(work.hasSalePrice ? " ¥\(String(format: "%.2f", work.salePrice))": "")")
.font(.subheadline).foregroundColor(.green)
}
}
.padding(16)
.background(Design.card)
.cornerRadius(Design.corner)
}

// MARK: - 可折叠分区
@State private var collapsedSections: Set<String> = []
private func collapsibleSection<Content: View>(key: String, title: String, @ViewBuilder content: () -> Content) -> some View {
let collapsed = collapsedSections.contains(key)
return VStack(alignment:.leading, spacing: 0) {
Button(action: {
if collapsed { collapsedSections.remove(key)} else { collapsedSections.insert(key)}
}) {
HStack {
Text(title).font(.headline)
Spacer()
Image(systemName: collapsed ? "chevron.down": "chevron.up")
.foregroundColor(.secondary).font(.caption)
}
.padding(.vertical, 12)
}
.buttonStyle(.plain)
if !collapsed {
content()
.padding(.bottom, 12)
}
}
.padding(.horizontal, 16)
.background(Design.card)
.cornerRadius(Design.corner)
}

private var linkedBrainstorms: [Brainstorm] {
store.brainstorms.filter { $0.linkedWorkIds.contains(work.id)}
}

// MARK: - 长图内容
private struct LongContent {
var lines: [String]
var photos: [UIImage]
}
private func buildLongContent() -> LongContent {
var l: [String] = []
l.append("喵了个咪 · 成品详情")
l.append("")
l.append("名称：" + (work.name.isEmpty ? "未命名成品": work.name))
if !work.code.isEmpty { l.append("编号：" + work.code)}
l.append("状态：" + (work.isFinished ? "已完成": "制作中"))
if !work.colorName.isEmpty { l.append("颜色：" + work.colorName)}
if let s = work.startedAt { l.append("开始：" + CSVValues.dateString(s))}
if let f = work.finishedAt { l.append("完成：" + CSVValues.dateString(f))}
l.append(String(format: "总成本：¥%.2f", store.workTotalCost(for: work)))
if work.hasLaborCost { l.append(String(format: "工费：¥%.2f", work.laborCost))}
if work.isSold { l.append("已售出" + (work.hasSalePrice? String(format: " ¥%.2f", work.salePrice): ""))}
if !work.note.isEmpty { l.append("备注：" + work.note)}
if !linkedBrainstorms.isEmpty {
l.append("")
l.append("")
for bs in linkedBrainstorms {
l.append("· " + (bs.title.isEmpty ? "未命名脑洞": bs.title))
}
}
let photos: [UIImage] = work.imageFileNames.compactMap { FabricImageStore.loadImage(named: $0)}
return LongContent(lines: l, photos: photos)
}
private func longContentSize(for content: LongContent) -> CGSize {
let width: CGFloat = 720
let lineHeight: CGFloat = 44
let padding: CGFloat = 40
let photoHeight: CGFloat = 400
let totalPhotoHeight: CGFloat = CGFloat(content.photos.count) * (photoHeight + 16)
let height = padding * 2 + totalPhotoHeight + CGFloat(content.lines.count) * lineHeight + 40
return CGSize(width: width, height: height)
}
private func drawLongContent(_ content: LongContent, in cg: CGContext, size: CGSize) {
let padding: CGFloat = 40
let lineHeight: CGFloat = 44
let photoHeight: CGFloat = 400
UIColor.white.setFill()
cg.fill(CGRect(origin:.zero, size: size))
var y = padding
for photo in content.photos {
let photoRect = CGRect(x: padding, y: y, width: size.width - padding * 2, height: photoHeight)
let imgAspect = photo.size.width / photo.size.height
let rectAspect = photoRect.width / photoRect.height
var drawRect: CGRect
if imgAspect > rectAspect {
let h = photoRect.height
let w = h * imgAspect
drawRect = CGRect(x: photoRect.minX - (w - photoRect.width) / 2, y: photoRect.minY, width: w, height: h)
} else {
let w = photoRect.width
let h = w / imgAspect
drawRect = CGRect(x: photoRect.minX, y: photoRect.minY - (h - photoRect.height) / 2, width: w, height: h)
}
UIGraphicsPushContext(cg)
let uictx = UIGraphicsGetCurrentContext()
uictx?.saveGState()
uictx?.addRect(photoRect)
uictx?.clip()
photo.draw(in: drawRect)
uictx?.restoreGState()
UIGraphicsPopContext()
y += photoHeight + 16
}
if !content.photos.isEmpty { y += 4}
UIGraphicsPushContext(cg)
for (i, line) in content.lines.enumerated() {
let font = i == 0 ? UIFont.boldSystemFont(ofSize: 32): UIFont.systemFont(ofSize: 28)
let attrs: [NSAttributedString.Key: Any] = [.font: font,.foregroundColor: UIColor.black]
(line as NSString).draw(at: CGPoint(x: padding, y: y), withAttributes: attrs)
y += lineHeight
}
UIGraphicsPopContext()
}
private func generateLongImage(showSheet: Bool = true) {
let content = buildLongContent()
let size = longContentSize(for: content)
let renderer = UIGraphicsImageRenderer(size: size)
let image = renderer.image { ctx in
drawLongContent(content, in: ctx.cgContext, size: size)
}
self.longImage = image
if showSheet {
DispatchQueue.main.async { self.showingLongImage = true}
}
}
private func generateLongPDF() -> URL? {
let content = buildLongContent()
let size = longContentSize(for: content)
let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin:.zero, size: size))
let data = renderer.pdfData { ctx in
ctx.beginPage()
drawLongContent(content, in: ctx.cgContext, size: size)
}
let url = FileManager.default.temporaryDirectory
.appendingPathComponent("成品长图-\(work.name.isEmpty ? "未命名": work.name)-\(Int(Date().timeIntervalSince1970)).pdf")
do {
try data.write(to: url)
return url
} catch {
return nil
}
}

var body: some View {
ScrollView {
VStack(alignment:.leading, spacing: 16) {
photoHeader
summaryCard
// 全部收起
HStack {
Spacer()
Button(action: {
if collapsedSections.isEmpty {
collapsedSections = ["images", "info", "brainstorm", "cost"]
} else {
collapsedSections = []
}
}) {
Label(collapsedSections.isEmpty ? "全部收起": "全部展开", systemImage: "chevron.down.circle")
.font(.subheadline).foregroundColor(themeAccent)
}
}
// 图片
collapsibleSection(key: "images", title: "图片") {
if work.imageFileNames.isEmpty {
Text("暂无图片").font(.subheadline).foregroundColor(.secondary)
} else {
LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 8)], spacing: 8) {
ForEach(work.imageFileNames, id: \.self) { name in
Button(action: { previewName = name}) {
Group {
if let uiImage = FabricImageStore.loadImage(named: name) {
Image(uiImage: uiImage).resizable().scaledToFill()
} else {
Color.gray.opacity(0.15)
}
}
.frame(height: 100)
.clipped()
.cornerRadius(10)
}
.buttonStyle(.plain)
}
}
}
}
// 基本信息
collapsibleSection(key: "info", title: "基本信息") {
VStack(alignment:.leading, spacing: 8) {
if !work.colorName.isEmpty {
Text("颜色：\(work.colorName)").font(.subheadline)
}
if let s = work.startedAt {
Text("开始日期：\(CSVValues.dateString(s))").font(.subheadline).foregroundColor(.secondary)
}
if let f = work.finishedAt {
Text("完成日期：\(CSVValues.dateString(f))").font(.subheadline).foregroundColor(.secondary)
}
if !work.note.isEmpty {
Text("备注：\(work.note)").font(.subheadline)
}
}
}
// 关联脑洞
collapsibleSection(key: "brainstorm", title: "关联脑洞") {
VStack(alignment:.leading, spacing: 8) {
HStack {
Spacer()
Button(action: { showingBrainstormPicker = true}) {
Image(systemName: "chevron.right").foregroundColor(.secondary)
}
}
if linkedBrainstorms.isEmpty {
Text("暂无关联脑洞").font(.caption).foregroundColor(.secondary)
} else {
ForEach(linkedBrainstorms) { bs in
BrainstormRowLink(bs: bs)
}
}
}
}
// 费用
collapsibleSection(key: "cost", title: "费用") {
VStack(alignment:.leading, spacing: 8) {
Text("总成本 ¥\(String(format: "%.2f", store.workTotalCost(for: work)))").font(.subheadline)
if work.hasLaborCost {
Text("工费 ¥\(String(format: "%.2f", work.laborCost))").font(.caption).foregroundColor(.secondary)
}
if work.isSold {
Text("已售出\(work.hasSalePrice ? " ¥\(String(format: "%.2f", work.salePrice))": "")")
.font(.subheadline).foregroundColor(.green)
}
}
}
}
.padding(16)
}
.navigationTitle("成品详情")
.navigationBarTitleDisplayMode(.inline)
.toolbar {
ToolbarItem(placement:.navigationBarTrailing) {
Menu {
Button("编辑", action: { showingEdit = true})
Menu {
Button(action: {
let img: UIImage?
if let existing = longImage {
img = existing
} else {
generateLongImage(showSheet: false)
img = longImage
}
if let img = img, let data = img.pngData() {
let url = FileManager.default.temporaryDirectory
.appendingPathComponent("成品长图-\(work.name.isEmpty ? "未命名": work.name)-\(Int(Date().timeIntervalSince1970)).png")
try? data.write(to: url)
shareFileItem = ShareURLItem(url: url)
}
}) {
Label("分享长图", systemImage: "photo")
}
Button(action: {
if let url = generateLongPDF() {
sharePDFItem = ShareURLItem(url: url)
}
}) {
Label("分享PDF", systemImage: "doc.richtext")
}
} label: {
Label("分享", systemImage: "square.and.arrow.up")
}
Button("生成长图", action: {
if longImage == nil {
generateLongImage()
} else {
showingLongImage = true
}
})
Button("删除", role:.destructive) { showingDelete = true}
} label: {
Image(systemName: "slider.horizontal.3")
}
}
}
.sheet(isPresented: $showingEdit) {
NavigationStack { WorkEditView(work: work)}
}
.alert("删除成品", isPresented: $showingDelete) {
Button("删除", role:.destructive) {
store.deleteWork(work)
dismiss()
}
Button("取消", role:.cancel) {}
} message: {
Text("确定删除「\(work.name.isEmpty ? "未命名成品": work.name)」吗？")
}
.sheet(isPresented: $showingBrainstormPicker) {
NavigationStack { BrainstormPickerView(work: work)}
}
.sheet(isPresented: $showingLongImage) {
if let longImage {
NavigationStack {
VStack {
Image(uiImage: longImage).resizable().scaledToFit().padding()
HStack(spacing: 12) {
ShareLink(item: Image(uiImage: longImage), preview: SharePreview("成品长图")) {
Label("分享长图", systemImage: "square.and.arrow.up")
}.buttonStyle(.borderedProminent).tint(themeAccent)
Button(action: {
if let url = generateLongPDF() {
sharePDFItem = ShareURLItem(url: url)
}
}) {
Label("分享PDF", systemImage: "doc.richtext")
}.buttonStyle(.bordered).tint(themeAccent)
}
Text("长图分享为图片；PDF 里的文字可复制。").font(.caption).foregroundColor(.secondary)
}
.navigationTitle("长图")
.toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { showingLongImage = false}}}
.sheet(item: $sharePDFItem) { item in
ShareSheet(url: item.url)
}
}
}
}
.sheet(item: $shareFileItem) { item in
ShareSheet(url: item.url)
}
.sheet(item: $sharePDFItem) { item in
ShareSheet(url: item.url)
}
.fullScreenCover(item: $previewName) { name in
if let uiImage = FabricImageStore.loadImage(named: name) {
NavigationStack {
Image(uiImage: uiImage)
.resizable().scaledToFit()
.navigationBarTitleDisplayMode(.inline)
.toolbar { ToolbarItem(placement:.cancellationAction) { Button("关闭") { previewName = nil}}}
}
}
}
.onAppear {
if longImage == nil {
generateLongImage(showSheet: false)
}
}
}
}

// 脑洞选择器：关联脑洞到成品
struct BrainstormPickerView: View {
@EnvironmentObject private var store: Store
@Environment(\.dismiss) private var dismiss
var work: Work

var body: some View {
List(store.brainstorms.sorted { $0.createdAt > $1.createdAt}) { bs in
Button(action: {
if !bs.linkedWorkIds.contains(work.id) {
bs.linkedWorkIds.append(work.id)
store.save()
}
dismiss()
}) {
HStack {
Text(bs.title.isEmpty ? "未命名脑洞": bs.title).lineLimit(1)
Spacer()
if bs.linkedWorkIds.contains(work.id) {
Image(systemName: "checkmark").foregroundColor(.green)
}
}
}
}
.navigationTitle("关联脑洞")
.navigationBarTitleDisplayMode(.inline)
}
}

// MARK: - 脑洞行（独立 View，避免编译器类型检查超时）
struct BrainstormRowLink: View {
var bs: Brainstorm
var body: some View {
NavigationLink(destination: BrainstormDetailView(brainstorm: bs)) {
HStack {
Text(bs.title.isEmpty ? "未命名脑洞": bs.title).lineLimit(1)
Spacer()
Image(systemName: "chevron.right").font(.caption).foregroundColor(.secondary)
}
.padding(.vertical, 4)
}
}
}

// String 作为 fullScreenCover 的 item 需要 Identifiable
extension String: Identifiable {
public var id: String { self}
}
