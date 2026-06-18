import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // 恢复上次保存的深浅色外观
        AppAppearance.current.apply()
        // 恢复上次退出前的视频壁纸
        WallpaperEngine.shared.restoreVideoWallpapers()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // 关闭主窗口后继续驻留
        false
    }
}

@main
struct WallpaperManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("showInMenuBar") private var showInMenuBar = true

    var body: some Scene {
        Window("Wallpaper", id: "main") {
            MainWindowView()
        }
        .defaultSize(width: 1000, height: 640)

        Settings {
            SettingsView()
        }

        MenuBarExtra("Wallpaper", systemImage: "photo.on.rectangle.angled",
                     isInserted: $showInMenuBar) {
            MenuBarView()
        }
    }
}
