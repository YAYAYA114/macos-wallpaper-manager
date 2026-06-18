import AppKit
import QuickLookThumbnailing
import SwiftUI

/// 基于 QuickLook 的缩略图生成器,图片和视频都能出图,带内存缓存。
final class ThumbnailLoader {
    static let shared = ThumbnailLoader()

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 500
    }

    func thumbnail(for url: URL, size: CGSize) async -> NSImage? {
        // 缓存键带上文件修改时间,避免同名文件被替换后仍返回旧缩略图
        let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?.timeIntervalSince1970 ?? 0
        let key = "\(url.path)#\(mtime)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2,
            representationTypes: .thumbnail
        )
        guard let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else {
            return nil
        }
        let image = representation.nsImage
        cache.setObject(image, forKey: key)
        return image
    }
}

/// 异步加载本地文件缩略图的 SwiftUI 视图
struct LocalThumbnailView: View {
    let url: URL
    var size: CGSize = CGSize(width: 320, height: 200)

    @State private var image: NSImage?

    var body: some View {
        // 布局尺寸由透明底板决定(始终服从外部约束),图片只作为视觉覆盖层。
        // 直接用 aspectRatio(.fill) 的 Image 参与布局会按"填满高度所需的完整宽度"
        // 上报理想尺寸,把父容器(详情面板、甚至窗口)整体撑大。
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.15))
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .clipped()
            .task(id: url) {
                image = await ThumbnailLoader.shared.thumbnail(for: url, size: size)
            }
    }
}
