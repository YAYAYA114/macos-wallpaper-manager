import SwiftUI

enum AppLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh"
    case english = "en"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

/// 应用内语言切换。视图通过 `@ObservedObject var l10n = L10n.shared` 观察,
/// 切换语言后所有使用 `tr()` 的文案立即刷新。
final class L10n: ObservableObject {
    static let shared = L10n()

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage") }
    }

    private init() {
        let saved = UserDefaults.standard.string(forKey: "appLanguage")
        language = AppLanguage(rawValue: saved ?? "") ?? .chinese
    }
}

/// 取当前语言的文案
func tr(_ zh: String, _ en: String) -> String {
    L10n.shared.language == .chinese ? zh : en
}
