import SwiftUI

struct SettingsView: View {
    @ObservedObject private var l10n = L10n.shared
    @AppStorage("showInMenuBar") private var showInMenuBar = true
    @AppStorage(AppAppearance.storageKey) private var appearance: AppAppearance = .system

    var body: some View {
        Form {
            Section(tr("通用", "General")) {
                Picker(tr("语言", "Language"), selection: $l10n.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.label).tag(language)
                    }
                }

                Picker(tr("外观", "Appearance"), selection: $appearance) {
                    ForEach(AppAppearance.allCases) { appearance in
                        Text(appearance.label).tag(appearance)
                    }
                }
                .onChange(of: appearance) {
                    // 选择变化时立即套用到整个 App
                    appearance.apply()
                }

                Toggle(tr("在菜单栏显示", "Show in menu bar"), isOn: $showInMenuBar)

                Text(tr("关闭菜单栏图标后,可通过程序坞图标重新打开主窗口。",
                        "With the menu bar icon hidden, reopen the main window from the Dock icon."))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(tr("显示方式与视频声音已改为按壁纸设置:在壁纸库中选中一张壁纸,在右侧详情面板中调整。",
                        "Display mode and video sound are now per-wallpaper: select a wallpaper in the library and adjust them in the detail panel."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .navigationTitle(tr("设置", "Settings"))
    }
}
