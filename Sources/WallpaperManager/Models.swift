import Foundation

enum WallpaperKind: String, Codable, CaseIterable {
    case image
    case video
}

/// 壁纸显示方式(图片四种都支持;视频不支持居中)
enum WallpaperDisplayMode: String, Codable, CaseIterable, Identifiable {
    case fill
    case fit
    case stretch
    case center

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fill: return tr("填充屏幕", "Fill Screen")
        case .fit: return tr("适应屏幕", "Fit to Screen")
        case .stretch: return tr("拉伸", "Stretch")
        case .center: return tr("居中", "Center")
        }
    }

    var supportsVideo: Bool { self != .center }
}

struct WallpaperItem: Identifiable, Codable, Hashable {
    let id: UUID
    var path: String
    var kind: WallpaperKind
    var addedAt: Date
    var isFavorite: Bool
    /// 在线来源标识,如 "wallhaven:3q5k8y"、"pixiv:145778588",用于去重
    var sourceID: String?
    /// 导入时的原始文件路径,用于避免重复导入
    var originPath: String?
    /// 每张壁纸独立的显示设置(nil 表示默认值,兼容旧版数据)
    var displayMode: WallpaperDisplayMode?
    var soundEnabled: Bool?
    var volume: Double?

    var effectiveDisplayMode: WallpaperDisplayMode { displayMode ?? .fill }
    var effectiveSoundEnabled: Bool { soundEnabled ?? false }
    var effectiveVolume: Double { volume ?? 0.5 }

    var url: URL { URL(fileURLWithPath: path) }
    var fileName: String { url.lastPathComponent }

    init(path: String, kind: WallpaperKind, sourceID: String? = nil, originPath: String? = nil) {
        self.id = UUID()
        self.path = path
        self.kind = kind
        self.addedAt = Date()
        self.isFavorite = false
        self.sourceID = sourceID
        self.originPath = originPath
    }
}

enum MediaFileType {
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "webp", "tiff", "tif", "bmp", "gif"]
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]

    static func kind(of url: URL) -> WallpaperKind? {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        return nil
    }
}
