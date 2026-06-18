import Foundation

/// Wallhaven 在线壁纸源(免 API Key,仅请求 SFW 内容)。
enum WallhavenAPI {
    enum Sorting: String, CaseIterable, Identifiable {
        case toplist
        case favorites
        case views
        case dateAdded = "date_added"
        case random

        var id: String { rawValue }

        var label: String {
            switch self {
            case .toplist: return tr("热门榜单", "Toplist")
            case .favorites: return tr("最多收藏", "Most Favorited")
            case .views: return tr("浏览最多", "Most Viewed")
            case .dateAdded: return tr("最新", "Latest")
            case .random: return tr("随机", "Random")
            }
        }

        /// 仅热门榜单(toplist)支持时间范围(日 / 周 / 月…)
        var supportsTopRange: Bool { self == .toplist }
    }

    /// 热门榜单的时间范围(配合 sorting=toplist 使用)
    enum TopRange: String, CaseIterable, Identifiable {
        case day = "1d"
        case threeDays = "3d"
        case week = "1w"
        case month = "1M"
        case threeMonths = "3M"
        case sixMonths = "6M"
        case year = "1y"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .day: return tr("今日", "Daily")
            case .threeDays: return tr("近三天", "Last 3 Days")
            case .week: return tr("本周", "Weekly")
            case .month: return tr("本月", "Monthly")
            case .threeMonths: return tr("近三月", "Last 3 Months")
            case .sixMonths: return tr("近半年", "Last 6 Months")
            case .year: return tr("今年", "Yearly")
            }
        }
    }

    struct Wallpaper: Decodable, Identifiable, Hashable {
        struct Thumbs: Decodable, Hashable {
            let large: String
            let original: String
            let small: String
        }

        let id: String
        let resolution: String
        let path: String      // 原图直链
        let fileType: String
        let thumbs: Thumbs

        enum CodingKeys: String, CodingKey {
            case id, resolution, path, thumbs
            case fileType = "file_type"
        }

        var fileExtension: String {
            fileType.components(separatedBy: "/").last ?? "jpg"
        }
    }

    private struct SearchResponse: Decodable {
        struct Meta: Decodable {
            let currentPage: Int
            let lastPage: Int

            enum CodingKeys: String, CodingKey {
                case currentPage = "current_page"
                case lastPage = "last_page"
            }
        }

        let data: [Wallpaper]
        let meta: Meta
    }

    struct SearchResult {
        let wallpapers: [Wallpaper]
        let currentPage: Int
        let lastPage: Int
    }

    static let apiKeyKey = "wallhavenAPIKey"

    static var apiKey: String {
        UserDefaults.standard.string(forKey: apiKeyKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    static func search(query: String, sorting: Sorting, topRange: TopRange = .month,
                       page: Int, atLeast: String? = nil, nsfw: Bool = false) async throws -> SearchResult {
        var components = URLComponents(string: "https://wallhaven.cc/api/v1/search")!
        var queryItems = [
            URLQueryItem(name: "categories", value: "111"),
            // NSFW 内容需要 API Key;无 Key 时接口会静默返回空列表
            URLQueryItem(name: "purity", value: nsfw ? "001" : "100"),
            URLQueryItem(name: "sorting", value: sorting.rawValue),
            URLQueryItem(name: "page", value: String(page)),
        ]
        // 时间范围只对热门榜单生效(日 / 周 / 月…)
        if sorting.supportsTopRange {
            queryItems.append(URLQueryItem(name: "topRange", value: topRange.rawValue))
        }
        if nsfw && !apiKey.isEmpty {
            queryItems.append(URLQueryItem(name: "apikey", value: apiKey))
        }
        if let atLeast {
            queryItems.append(URLQueryItem(name: "atleast", value: atLeast))
        }
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }
        components.queryItems = queryItems

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return SearchResult(wallpapers: decoded.data,
                            currentPage: decoded.meta.currentPage,
                            lastPage: decoded.meta.lastPage)
    }

    /// 下载原图到临时位置,返回 (临时文件, 扩展名);由壁纸库负责归档命名
    static func downloadToTemp(_ wallpaper: Wallpaper) async throws -> (URL, String) {
        guard let url = URL(string: wallpaper.path) else { throw URLError(.badURL) }
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return (tempURL, wallpaper.fileExtension)
    }
}
