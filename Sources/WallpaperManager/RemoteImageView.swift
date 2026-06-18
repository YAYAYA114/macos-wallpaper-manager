import SwiftUI
import AppKit
import ImageIO

/// 支持自定义请求头的远程图片加载视图(AsyncImage 无法加 Referer,Pixiv 防盗链需要)。
/// 解码时统一下采样到缩略图尺寸:部分图源的样张是 1500px+ 的大图,
/// 原尺寸缓存会让常驻的多个图源页面内存持续膨胀。
struct RemoteImageView: View {
    let url: URL
    var headers: [String: String] = [:]

    @State private var image: NSImage?
    @State private var failed = false

    /// 缩略图最长边(@2x 渲染下足够覆盖 300pt 宽的卡片)
    private static let maxThumbPixel: CGFloat = 700

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 400
        return cache
    }()

    var body: some View {
        // 布局尺寸由透明底板决定,图片只作为视觉覆盖层(同 LocalThumbnailView,
        // 避免 fill 模式的图片按完整宽度上报理想尺寸而撑大父容器)
        Color.clear
            .overlay {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else if failed {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                        .overlay { Image(systemName: "photo").foregroundStyle(.tertiary) }
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.15))
                        .overlay { ProgressView().controlSize(.small) }
                }
            }
            .clipped()
            .task(id: url) {
                await load()
            }
    }

    private func load() async {
        let key = url.absoluteString as NSString
        if let cached = Self.cache.object(forKey: key) {
            image = cached
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (field, value) in headers {
            request.setValue(value, forHTTPHeaderField: field)
        }
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let loaded = Self.downsample(data) ?? NSImage(data: data) else {
            failed = true
            return
        }
        Self.cache.setObject(loaded, forKey: key)
        image = loaded
    }

    /// 用 ImageIO 直接解码出缩略图,避免原尺寸位图驻留内存
    private static func downsample(_ data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxThumbPixel,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
