import Foundation

/// 把搜索词翻译成图源通用的英文标签,提升非英文搜索的命中率。
/// wallhaven / yande.re / konachan 的标签体系基本都是英文,直接用中文搜索常常一无所获;
/// 检测到 CJK 等非 ASCII 字符时自动译为英文(免 Key 的公共翻译接口),失败则回退原词。
actor TranslationService {
    static let shared = TranslationService()

    private var cache: [String: String] = [:]

    /// 翻译结果:`resolved` 是实际用于搜索的词;`didTranslate` 标记是否发生了翻译。
    struct Resolved {
        let resolved: String
        let didTranslate: Bool
    }

    /// 含 CJK 等非拉丁字符时翻译为英文,否则原样返回。失败时回退原词。
    func resolve(_ text: String) async -> Resolved {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, needsTranslation(trimmed) else {
            return Resolved(resolved: trimmed, didTranslate: false)
        }
        if let cached = cache[trimmed] {
            return Resolved(resolved: cached, didTranslate: cached.caseInsensitiveCompare(trimmed) != .orderedSame)
        }
        guard let translated = await translate(trimmed), !translated.isEmpty else {
            return Resolved(resolved: trimmed, didTranslate: false)
        }
        cache[trimmed] = translated
        return Resolved(resolved: translated,
                        didTranslate: translated.caseInsensitiveCompare(trimmed) != .orderedSame)
    }

    /// 是否包含需要翻译的非 ASCII 字符(CJK、假名等)
    private func needsTranslation(_ text: String) -> Bool {
        text.unicodeScalars.contains { $0.value > 0x7F }
    }

    private func translate(_ text: String) async -> String? {
        var components = URLComponents(string: "https://translate.googleapis.com/translate_a/single")!
        components.queryItems = [
            URLQueryItem(name: "client", value: "gtx"),
            URLQueryItem(name: "sl", value: "auto"),
            URLQueryItem(name: "tl", value: "en"),
            URLQueryItem(name: "dt", value: "t"),
            URLQueryItem(name: "q", value: text),
        ]
        guard let url = components.url else { return nil }
        var request = URLRequest(url: url)
        request.setValue(PixivAPI.userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 8
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        // 返回结构:[ [ ["译文","原文",…], … ], …, "源语言", … ]
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let segments = root.first as? [Any] else { return nil }
        let pieces = segments.compactMap { ($0 as? [Any])?.first as? String }
        let result = pieces.joined().trimmingCharacters(in: .whitespacesAndNewlines)
        return result.isEmpty ? nil : result
    }
}
