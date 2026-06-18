import Foundation

/// 在线图源的最低分辨率筛选。
/// Wallhaven 走服务端 `atleast` 参数;Pixiv 接口不支持,在客户端按宽高过滤。
enum ResolutionFilter: String, CaseIterable, Identifiable {
    case any
    case fhd
    case qhd
    case uhd4k
    case uhd5k

    var id: String { rawValue }

    var label: String {
        switch self {
        case .any: return tr("不限分辨率", "Any Resolution")
        case .fhd: return "≥ 1920×1080"
        case .qhd: return "≥ 2560×1440"
        case .uhd4k: return "≥ 3840×2160"
        case .uhd5k: return "≥ 5120×2880"
        }
    }

    var minSize: (width: Int, height: Int)? {
        switch self {
        case .any: return nil
        case .fhd: return (1920, 1080)
        case .qhd: return (2560, 1440)
        case .uhd4k: return (3840, 2160)
        case .uhd5k: return (5120, 2880)
        }
    }

    /// Wallhaven `atleast` 参数值
    var wallhavenAtLeast: String? {
        guard let minSize else { return nil }
        return "\(minSize.width)x\(minSize.height)"
    }

    /// 客户端过滤(竖图按短边比较,横竖都不冤枉)
    func matches(width: Int, height: Int) -> Bool {
        guard let minSize else { return true }
        let long = max(width, height), short = min(width, height)
        return long >= minSize.width && short >= minSize.height
    }
}
