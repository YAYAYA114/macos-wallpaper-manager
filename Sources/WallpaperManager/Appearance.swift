import SwiftUI
import AppKit

/// 应用的深浅色外观(跟随系统 / 浅色 / 深色)。
/// 设计上和 AppLanguage 一脉相承:一个带 rawValue 的枚举,存进 UserDefaults。
enum AppAppearance: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return tr("跟随系统", "Follow System")
        case .light: return tr("浅色", "Light")
        case .dark: return tr("深色", "Dark")
        }
    }

    /// 对应的 macOS 外观;nil 表示交还给系统(跟随系统)
    private var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }

    /// 把外观套用到整个 App(包括菜单栏弹出菜单)
    func apply() {
        NSApp.appearance = nsAppearance
    }

    static let storageKey = "appAppearance"

    /// 读取已保存的选择;没存过就默认跟随系统
    static var current: AppAppearance {
        AppAppearance(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}
