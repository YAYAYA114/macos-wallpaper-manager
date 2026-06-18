import Foundation

/// Pixiv 排行榜图源(免登录,仅全年龄内容)。
/// 注意:i.pximg.net 有防盗链,所有图片请求必须带 Referer 头。
enum PixivAPI {
    static let referer = "https://www.pixiv.net/"
    static let sessionCookieKey = "pixivPHPSESSID"

    /// Cloudflare 会拦截"带登录 Cookie 但 UA 不像浏览器"的请求(URLSession 默认的
    /// CFNetwork UA 必中),所有 pixiv 请求都必须伪装成浏览器 UA。
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36"

    /// 加载 pixiv 图片(缩略图等)所需的请求头
    static var imageHeaders: [String: String] {
        ["Referer": referer, "User-Agent": userAgent]
    }

    /// 用户在设置里填入的 PHPSESSID Cookie(R-18 内容需要登录态)
    static var sessionCookie: String {
        UserDefaults.standard.string(forKey: sessionCookieKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    enum PixivError: LocalizedError {
        case authRequired
        case blocked

        var errorDescription: String? {
            switch self {
            case .authRequired:
                return tr("R-18 内容需要有效登录:请点击顶栏的钥匙按钮检查 PHPSESSID Cookie 是否过期,并确认账号已在 pixiv 设置中开启 R-18 显示。",
                          "R-18 content requires a valid sign-in: click the key button to check whether your PHPSESSID cookie has expired, and make sure R-18 is enabled in your pixiv account settings.")
            case .blocked:
                return tr("请求被 pixiv 拒绝(可能触发了风控),请稍后重试。",
                          "The request was rejected by pixiv (possibly rate-limited). Please try again later.")
            }
        }
    }

    enum RankingMode: String, CaseIterable, Identifiable {
        case daily
        case weekly
        case monthly
        case rookie
        case dailyR18 = "daily_r18"
        case weeklyR18 = "weekly_r18"
        case maleR18 = "male_r18"
        case femaleR18 = "female_r18"

        var id: String { rawValue }

        var isR18: Bool { rawValue.hasSuffix("r18") }

        /// 全年龄榜单与 R-18 榜单(pixiv 的 R-18 没有月榜/新人榜,但有受众向榜单)
        static let allAges: [RankingMode] = [.daily, .weekly, .monthly, .rookie]
        static let r18: [RankingMode] = [.dailyR18, .weeklyR18, .maleR18, .femaleR18]

        var label: String {
            switch self {
            case .daily: return tr("今日", "Daily")
            case .weekly: return tr("本周", "Weekly")
            case .monthly: return tr("本月", "Monthly")
            case .rookie: return tr("新人", "Rookie")
            case .dailyR18: return tr("今日", "Daily")
            case .weeklyR18: return tr("本周", "Weekly")
            case .maleR18: return tr("男性向", "For Men")
            case .femaleR18: return tr("女性向", "For Women")
            }
        }
    }

    struct Illust: Decodable, Identifiable, Hashable {
        let illustID: Int
        let title: String
        let userName: String
        let url: String        // 缩略图(480x960)
        let width: Int
        let height: Int

        enum CodingKeys: String, CodingKey {
            case illustID = "illust_id"
            case title
            case userName = "user_name"
            case url, width, height
        }

        var id: Int { illustID }
        var resolution: String { "\(width)x\(height)" }

        /// 从缩略图 URL 推导原图 URL(后缀可能是 jpg 或 png,下载时需回退尝试)
        var originalURLCandidates: [URL] {
            // 缩略图形如 https://i.pximg.net/c/480x960/img-master/img/.../145778588_p0_master1200.jpg
            var base = url
            if let range = base.range(of: "/c/480x960/img-master/") {
                base = base.replacingCharacters(in: range, with: "/img-original/")
            } else if let range = base.range(of: "/img-master/") {
                base = base.replacingCharacters(in: range, with: "/img-original/")
            }
            base = base.replacingOccurrences(of: "_master1200", with: "")
            let withoutExt = (base as NSString).deletingPathExtension
            let preferredExt = (base as NSString).pathExtension.lowercased()
            let exts = preferredExt == "png" ? ["png", "jpg"] : ["jpg", "png"]
            return exts.compactMap { URL(string: "\(withoutExt).\($0)") }
        }
    }

    private struct RankingResponse: Decodable {
        let contents: [Illust]
        /// 下一页页码;最后一页时接口返回 false,宽容解码为 nil
        let next: Int?

        enum CodingKeys: String, CodingKey { case contents, next }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            contents = try container.decode([Illust].self, forKey: .contents)
            next = try? container.decode(Int.self, forKey: .next)
        }
    }

    struct RankingResult {
        let illusts: [Illust]
        let hasMore: Bool
    }

    /// 仅在确实需要登录态的请求(R-18 榜单)上附带 Cookie:
    /// 无效/过期的 PHPSESSID 会触发 pixiv 的 Cloudflare 风控(403),
    /// 全年龄请求带上它反而会把不需要登录的接口也搞挂。
    private static func request(_ url: URL, includeSession: Bool = false) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        if includeSession && !sessionCookie.isEmpty {
            request.setValue("PHPSESSID=\(sessionCookie)", forHTTPHeaderField: "Cookie")
        }
        return request
    }

    static func ranking(mode: RankingMode, page: Int) async throws -> RankingResult {
        var components = URLComponents(string: "https://www.pixiv.net/ranking.php")!
        components.queryItems = [
            URLQueryItem(name: "mode", value: mode.rawValue),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "p", value: String(page)),
        ]
        let (data, response) = try await URLSession.shared.data(
            for: request(components.url!, includeSession: mode.isR18))
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            if http.statusCode == 403 {
                // R-18 榜单 403 = 未登录/Cookie 失效;全年龄 403 = 风控拦截
                throw mode.isR18 ? PixivError.authRequired : PixivError.blocked
            }
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(RankingResponse.self, from: data)
        // 以接口返回的 next 字段判断是否还有下一页(条目数不可靠,下架作品会让单页少于 50 条)
        return RankingResult(illusts: decoded.contents, hasMore: decoded.next != nil)
    }

    /// 下载原图到临时位置(自动尝试 jpg/png 后缀),返回 (临时文件, 扩展名);由壁纸库负责归档命名
    static func downloadToTemp(_ illust: Illust) async throws -> (URL, String) {
        for candidate in illust.originalURLCandidates {
            let (tempURL, response) = try await URLSession.shared.download(for: request(candidate))
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 200 {
                return (tempURL, candidate.pathExtension)
            }
        }
        throw URLError(.fileDoesNotExist)
    }
}
