import SwiftUI
import AppKit
import AVFoundation
import ImageIO

/// 本地壁纸库的右侧详情面板(Wallpaper Engine 风格):
/// 大预览、文件信息、来源跳转、每张壁纸独立的显示方式与声音设置。
struct WallpaperInspectorView: View {
    static let preferredWidth: CGFloat = 280

    let itemID: UUID
    @Binding var displaySelection: String?
    var onClose: () -> Void = {}

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var engine = WallpaperEngine.shared
    @ObservedObject private var l10n = L10n.shared

    @State private var fileSizeText = "—"
    @State private var dimensionsText = "—"
    @State private var durationText: String?

    private var item: WallpaperItem? { library.item(id: itemID) }

    var body: some View {
        if let item {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    preview(item)
                    quickActions(item)
                    settingsSection(item)
                    infoSection(item)
                }
                .padding(.vertical, 14)
                .padding(.leading, 14)
                // 系统设置为"始终显示滚动条"(连接鼠标时的默认值)时,
                .scrollIndicators(.never)
                // 此时给内容右侧多让出滚动条的宽度
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity)
            }
            // 面板内容较短,隐藏悬浮滚动条,避免它盖住右对齐的信息值
            .scrollIndicators(.never)
            .task(id: item.url) {
                await loadMetadata(item)
            }
        } else {
            ContentUnavailableView {
                Label(tr("未选择壁纸", "No Selection"), systemImage: "photo")
            } description: {
                Text(tr("在左侧选择一张壁纸查看详情。", "Select a wallpaper to see its details."))
            }
        }
    }

    // MARK: - 预览与操作

    private var header: some View {
        HStack {
            Text(tr("壁纸详情", "Details"))
                .font(.headline)
            Spacer()
            Button {
                onClose()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
                    .imageScale(.large)
            }
            .buttonStyle(.plain)
            .help(tr("关闭", "Close"))
        }
    }

    private func preview(_ item: WallpaperItem) -> some View {
        ZStack(alignment: .topTrailing) {
            // 与网格使用相同的缩略图尺寸,直接命中缓存,展开面板时无需重新生成
            LocalThumbnailView(url: item.url)
                .frame(height: 170)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.1))
                }

            if engine.isActive(item) {
                Label(tr("使用中", "Active"), systemImage: "checkmark.circle.fill")
                    .font(.caption2.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.green.opacity(0.85), in: Capsule())
                    .padding(8)
            }
        }
    }

    private func quickActions(_ item: WallpaperItem) -> some View {
        HStack(spacing: 8) {
            Button {
                library.toggleFavorite(item)
            } label: {
                Label(item.isFavorite ? tr("取消收藏", "Unfavorite") : tr("收藏", "Favorite"),
                      systemImage: item.isFavorite ? "heart.fill" : "heart")
                    .frame(maxWidth: .infinity)
            }

            Button {
                NSWorkspace.shared.activateFileViewerSelecting([item.url])
            } label: {
                Label(tr("访达", "Finder"), systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .help(tr("在访达中显示", "Show in Finder"))

            Button(role: .destructive) {
                library.remove(item)
            } label: {
                Label(tr("移除", "Remove"), systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .help(tr("从库中移除", "Remove from Library"))
        }
        .labelStyle(.iconOnly)
        .controlSize(.large)
    }

    // MARK: - 设置

    @ViewBuilder
    private func settingsSection(_ item: WallpaperItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(tr("显示设置", "Display Settings"))

            Picker(tr("显示方式", "Mode"), selection: displayModeBinding(item)) {
                ForEach(WallpaperDisplayMode.allCases.filter { item.kind == .image || $0.supportsVideo }) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)

            if item.kind == .video {
                Toggle(tr("播放声音", "Play sound"), isOn: soundBinding(item))

                HStack {
                    Image(systemName: "speaker.fill")
                        .foregroundStyle(.secondary)
                    Slider(value: volumeBinding(item), in: 0...1)
                    Image(systemName: "speaker.wave.3.fill")
                        .foregroundStyle(.secondary)
                    Text("\(Int(item.effectiveVolume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(!item.effectiveSoundEnabled)
            }

            if engine.isActive(item) {
                Text(tr("此壁纸正在使用中,调整会即时生效。",
                        "This wallpaper is active — changes apply immediately."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 信息

    @ViewBuilder
    private func infoSection(_ item: WallpaperItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(tr("信息", "Info"))

            infoRow(tr("类型", "Type"),
                    item.kind == .video ? tr("视频壁纸", "Video") : tr("图片壁纸", "Image"))
            infoRow(tr("分辨率", "Dimensions"), dimensionsText)
            if let durationText {
                infoRow(tr("时长", "Duration"), durationText)
            }
            infoRow(tr("文件大小", "File Size"), fileSizeText)
            infoRow(tr("添加日期", "Added"), item.addedAt.formatted(date: .abbreviated, time: .shortened))
            infoRow(tr("文件名", "File Name"), item.fileName)

            if let sourceID = item.sourceID, let (name, url) = Self.sourceLink(for: sourceID) {
                HStack {
                    Text(tr("来源", "Source"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(name) {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.link)
                    .help(url.absoluteString)
                }
                .font(.caption)
            } else if item.originPath != nil {
                infoRow(tr("来源", "Source"), tr("本地导入", "Local import"))
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            // 值的宽度锁定为剩余空间,超长中间截断、悬停看全文。
            // 注意不能加 .textSelection:macOS 上它会让 Text 拒绝截断,
            // 把整个面板内容撑得比面板还宽(信息被窗口边缘硬切的元凶)。
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .help(value)
        }
        .font(.caption)
    }

    /// 在线来源的展示名与原页面链接
    static func sourceLink(for sourceID: String) -> (String, URL)? {
        let parts = sourceID.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let (source, id) = (parts[0], parts[1])
        let link: String?
        let name: String
        switch source {
        case "wallhaven": name = "Wallhaven"; link = "https://wallhaven.cc/w/\(id)"
        case "pixiv": name = "Pixiv"; link = "https://www.pixiv.net/artworks/\(id)"
        case "yandere": name = "Yande.re"; link = "https://yande.re/post/show/\(id)"
        case "konachan": name = "Konachan"; link = "https://konachan.com/post/show/\(id)"
        default: return nil
        }
        guard let link, let url = URL(string: link) else { return nil }
        return (name, url)
    }

    // MARK: - 设置绑定(写入即持久化;使用中的壁纸即时生效)

    private func displayModeBinding(_ item: WallpaperItem) -> Binding<WallpaperDisplayMode> {
        Binding(
            get: { library.item(id: item.id)?.effectiveDisplayMode ?? .fill },
            set: { newValue in
                library.updateItem(id: item.id) { $0.displayMode = newValue }
                if let updated = library.item(id: item.id) { engine.refreshIfActive(updated) }
            })
    }

    private func soundBinding(_ item: WallpaperItem) -> Binding<Bool> {
        Binding(
            get: { library.item(id: item.id)?.effectiveSoundEnabled ?? false },
            set: { newValue in
                library.updateItem(id: item.id) { $0.soundEnabled = newValue }
                if let updated = library.item(id: item.id) { engine.refreshIfActive(updated) }
            })
    }

    private func volumeBinding(_ item: WallpaperItem) -> Binding<Double> {
        Binding(
            get: { library.item(id: item.id)?.effectiveVolume ?? 0.5 },
            set: { newValue in
                library.updateItem(id: item.id) { $0.volume = newValue }
                if let updated = library.item(id: item.id) { engine.refreshIfActive(updated) }
            })
    }

    // MARK: - 元数据

    private func loadMetadata(_ item: WallpaperItem) async {
        durationText = nil
        fileSizeText = "—"
        dimensionsText = "—"

        if let attrs = try? FileManager.default.attributesOfItem(atPath: item.path),
           let bytes = attrs[.size] as? Int64 {
            fileSizeText = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        }

        switch item.kind {
        case .image:
            if let source = CGImageSourceCreateWithURL(item.url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
               let width = props[kCGImagePropertyPixelWidth] as? Int,
               let height = props[kCGImagePropertyPixelHeight] as? Int {
                dimensionsText = "\(width) × \(height)"
            }
        case .video:
            let asset = AVURLAsset(url: item.url)
            if let track = try? await asset.loadTracks(withMediaType: .video).first,
               let size = try? await track.load(.naturalSize) {
                dimensionsText = "\(Int(abs(size.width))) × \(Int(abs(size.height)))"
            }
            if let duration = try? await asset.load(.duration) {
                let seconds = Int(duration.seconds.rounded())
                durationText = String(format: "%d:%02d", seconds / 60, seconds % 60)
            }
        }
    }
}
