import Foundation

/// Moebooru 系图站(yande.re / konachan.com)通用客户端。
/// 两站均为高分辨率动漫壁纸站,API 开放、免登录,支持标签搜索与分级过滤。
enum MoebooruSource: String, CaseIterable, Identifiable {
    case yandere
    case konachan

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .yandere: return "Yande.re"
        case .konachan: return "Konachan"
        }
    }

    var host: String {
        switch self {
        case .yandere: return "https://yande.re"
        case .konachan: return "https://konachan.com"
        }
    }
}

enum MoebooruAPI {
    static let pageSize = 30

    /// 浏览模式:标签搜索(最新 / 评分最高)或热门榜单(日 / 周 / 月)。
    /// 榜单接口不接受标签、不分页,返回当前周期内的热门图。
    enum BrowseMode: String, CaseIterable, Identifiable {
        case topRated
        case latest
        case popularDay
        case popularWeek
        case popularMonth

        var id: String { rawValue }

        var label: String {
            switch self {
            case .topRated: return tr("评分最高", "Top Rated")
            case .latest: return tr("最新", "Latest")
            case .popularDay: return tr("今日最热", "Popular Today")
            case .popularWeek: return tr("本周最热", "Popular This Week")
            case .popularMonth: return tr("本月最热", "Popular This Month")
            }
        }

        /// 热门榜单模式:走 popular_by_* 接口,无标签、无分页
        var isPopular: Bool { popularEndpoint != nil }

        /// 对应的 Moebooru 榜单接口路径
        var popularEndpoint: String? {
            switch self {
            case .popularDay: return "post/popular_by_day"
            case .popularWeek: return "post/popular_by_week"
            case .popularMonth: return "post/popular_by_month"
            case .topRated, .latest: return nil
            }
        }
    }

    struct Post: Decodable, Identifiable, Hashable {
        let id: Int
        let width: Int
        let height: Int
        let rating: String      // s / q / e
        let fileURL: String     // 原图
        let sampleURL: String?  // 中等尺寸样张,用作缩略图

        enum CodingKeys: String, CodingKey {
            case id, width, height, rating
            case fileURL = "file_url"
            case sampleURL = "sample_url"
        }

        var resolution: String { "\(width)x\(height)" }
        var thumbURL: String { sampleURL ?? fileURL }

        var fileExtension: String {
            let ext = (URL(string: fileURL)?.pathExtension ?? "jpg").lowercased()
            return ext.isEmpty ? "jpg" : ext
        }
    }

    private static func request(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(PixivAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
    }

    static func search(source: MoebooruSource, tags: String, r18: Bool,
                       sortByScore: Bool, minSize: (width: Int, height: Int)? = nil,
                       page: Int) async throws -> [Post] {
        var tagParts = tags.split(separator: " ").map(String.init)
        // 分级过滤:全年龄只看 safe;R-18 排除 safe(含 questionable/explicit),并屏蔽违规标签
        if r18 {
            tagParts.append("-rating:s")
            tagParts.append(contentsOf: ["-loli", "-shota"])
        } else {
            tagParts.append("rating:s")
        }
        if sortByScore {
            tagParts.append("order:score")
        }
        // 分辨率筛选下推到服务端,避免客户端过滤后单页只剩寥寥几张
        if let minSize {
            tagParts.append("width:>=\(minSize.width)")
            tagParts.append("height:>=\(minSize.height)")
        }

        var components = URLComponents(string: "\(source.host)/post.json")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: String(pageSize)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "tags", value: tagParts.joined(separator: " ")),
        ]

        let (data, response) = try await URLSession.shared.data(for: request(components.url!))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let posts = try JSONDecoder().decode([Post].self, from: data)
        // 只保留能用作壁纸的图片格式
        return posts.filter { MediaFileType.imageExtensions.contains($0.fileExtension) }
    }

    /// 热门榜单(今日 / 本周 / 本月)。接口不接受标签、不分页,返回当前周期的热门图。
    /// 分级与分辨率过滤交给调用方在客户端处理(接口本身不支持这些参数)。
    static func popular(source: MoebooruSource, mode: BrowseMode) async throws -> [Post] {
        guard let endpoint = mode.popularEndpoint else { return [] }
        let components = URLComponents(string: "\(source.host)/\(endpoint).json")!
        let (data, response) = try await URLSession.shared.data(for: request(components.url!))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        let posts = try JSONDecoder().decode([Post].self, from: data)
        return posts.filter { MediaFileType.imageExtensions.contains($0.fileExtension) }
    }

    private struct Tag: Decodable { let name: String }

    /// 标签自动补全:返回与前缀匹配、按使用量降序的标签名。失败时静默返回空数组。
    static func suggestTags(source: MoebooruSource, prefix: String) async throws -> [String] {
        let trimmed = prefix.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return [] }
        var components = URLComponents(string: "\(source.host)/tag.json")!
        components.queryItems = [
            URLQueryItem(name: "limit", value: "10"),
            URLQueryItem(name: "order", value: "count"),
            URLQueryItem(name: "name", value: "\(trimmed)*"),
        ]
        guard let url = components.url else { return [] }
        let (data, response) = try await URLSession.shared.data(for: request(url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 { return [] }
        let tags = (try? JSONDecoder().decode([Tag].self, from: data)) ?? []
        return tags.map(\.name)
    }

    /// 下载原图到临时位置,返回 (临时文件, 扩展名)
    static func downloadToTemp(_ post: Post) async throws -> (URL, String) {
        guard let url = URL(string: post.fileURL) else { throw URLError(.badURL) }
        let (tempURL, response) = try await URLSession.shared.download(for: request(url))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw URLError(.badServerResponse)
        }
        return (tempURL, post.fileExtension)
    }
}
