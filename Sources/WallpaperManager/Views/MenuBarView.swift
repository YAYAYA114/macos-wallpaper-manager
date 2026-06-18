import SwiftUI
import AppKit

struct MenuBarView: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var engine = WallpaperEngine.shared
    @ObservedObject private var l10n = L10n.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(tr("打开 Wallpaper", "Open Wallpaper")) {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut("o")

        Divider()

        Button(tr("随机切换壁纸", "Random Wallpaper")) {
            applyRandomImage()
        }
        .keyboardShortcut("r")
        .disabled(library.items.allSatisfy { $0.kind != .image })

        if engine.hasActiveVideoWallpaper {
            Button(tr("停止视频壁纸", "Stop Video Wallpaper")) {
                engine.stopAllVideoWallpapers()
            }
        }

        Divider()

        SettingsLink {
            Text(tr("设置…", "Settings…"))
        }
        .keyboardShortcut(",")

        Button(tr("退出", "Quit")) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func applyRandomImage() {
        let images = library.items.filter { $0.kind == .image }
        guard let pick = images.randomElement() else { return }
        engine.apply(pick, displayName: nil)
    }
}
