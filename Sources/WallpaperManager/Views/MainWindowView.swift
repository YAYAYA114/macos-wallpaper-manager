import SwiftUI
import AppKit

enum SidebarSection: Hashable {
    case all
    case images
    case videos
    case favorites
    case wallhaven
    case pixiv
    case yandere
    case konachan

    var title: String {
        switch self {
        case .all: return tr("全部壁纸", "All Wallpapers")
        case .images: return tr("图片", "Images")
        case .videos: return tr("视频", "Videos")
        case .favorites: return tr("收藏", "Favorites")
        case .wallhaven: return "Wallhaven"
        case .pixiv: return "Pixiv"
        case .yandere: return "Yande.re"
        case .konachan: return "Konachan"
        }
    }

    var icon: String {
        switch self {
        case .all: return "photo.on.rectangle"
        case .images: return "photo"
        case .videos: return "video"
        case .favorites: return "heart"
        case .wallhaven: return "globe"
        case .pixiv: return "paintbrush"
        case .yandere: return "y.circle"
        case .konachan: return "k.circle"
        }
    }

    /// 在线图源使用官方 logo(单色模板),其余用 SF Symbols
    var customLogo: NSImage? {
        switch self {
        case .wallhaven: return SourceLogos.wallhaven
        case .pixiv: return SourceLogos.pixiv
        case .yandere: return SourceLogos.yandere
        case .konachan: return SourceLogos.konachan
        default: return nil
        }
    }
}

struct SidebarLabel: View {
    let section: SidebarSection
    @ObservedObject private var l10n = L10n.shared

    var body: some View {
        Label {
            Text(section.title)
        } icon: {
            if let logo = section.customLogo {
                Image(nsImage: logo)
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 16)
            } else {
                Image(systemName: section.icon)
            }
        }
    }
}

/// 显示器选择:nil 代表所有显示器
struct DisplayPicker: View {
    @Binding var selection: String?
    @ObservedObject private var l10n = L10n.shared
    @State private var screenNames: [String] = NSScreen.screens.map(\.localizedName)

    var body: some View {
        Picker(selection: $selection) {
            Text(tr("所有显示器", "All Displays")).tag(String?.none)
            ForEach(screenNames, id: \.self) { name in
                Text(name).tag(String?.some(name))
            }
        } label: {
            Label(tr("目标显示器", "Target Display"), systemImage: "display")
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didChangeScreenParametersNotification)) { _ in
            screenNames = NSScreen.screens.map(\.localizedName)
            if let current = selection, !screenNames.contains(current) {
                selection = nil
            }
        }
    }
}

struct MainWindowView: View {
    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var engine = WallpaperEngine.shared
    @ObservedObject private var l10n = L10n.shared

    @State private var selectedSection: SidebarSection = .all
    @State private var displaySelection: String? = nil
    @State private var showImporter = false
    @State private var importMessage: String?

    /// 常驻的图源浏览面板:非选中时透明且不响应交互
    @ViewBuilder
    private func browserPane(_ pane: some View, shownFor section: SidebarSection) -> some View {
        let isShown = selectedSection == section
        pane
            .opacity(isShown ? 1 : 0)
            .allowsHitTesting(isShown)
            .accessibilityHidden(!isShown)
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedSection) {
                Section(tr("本地壁纸库", "Library")) {
                    ForEach([SidebarSection.all, .images, .videos, .favorites], id: \.self) { section in
                        SidebarLabel(section: section).tag(section)
                    }
                }
                Section(tr("发现", "Discover")) {
                    ForEach([SidebarSection.wallhaven, .pixiv, .yandere, .konachan], id: \.self) { section in
                        SidebarLabel(section: section).tag(section)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            // 在线图源视图常驻不销毁,切换侧边栏只改可见性:
            // 各图源的筛选条件、已加载内容和滚动位置都得以保留。
            // isActive 控制惰性加载,没访问过的源不会提前联网。
            ZStack {
                browserPane(OnlineBrowserView(displaySelection: $displaySelection,
                                              isActive: selectedSection == .wallhaven),
                            shownFor: .wallhaven)
                browserPane(PixivBrowserView(displaySelection: $displaySelection,
                                             isActive: selectedSection == .pixiv),
                            shownFor: .pixiv)
                browserPane(MoebooruBrowserView(source: .yandere, displaySelection: $displaySelection,
                                                isActive: selectedSection == .yandere),
                            shownFor: .yandere)
                browserPane(MoebooruBrowserView(source: .konachan, displaySelection: $displaySelection,
                                                isActive: selectedSection == .konachan),
                            shownFor: .konachan)

                if ![SidebarSection.wallhaven, .pixiv, .yandere, .konachan].contains(selectedSection) {
                    LibraryGridView(section: selectedSection, displaySelection: $displaySelection)
                        .background(.background)
                }
            }
            .navigationTitle(selectedSection.title)
        }
        .toolbar {
            ToolbarItem {
                DisplayPicker(selection: $displaySelection)
            }
            ToolbarItem {
                Button {
                    showImporter = true
                } label: {
                    Label(tr("导入", "Import"), systemImage: "plus")
                }
                .help(tr("导入图片、视频或整个文件夹", "Import images, videos, or folders"))
            }
            if engine.hasActiveVideoWallpaper {
                ToolbarItem {
                    Button {
                        engine.stopAllVideoWallpapers()
                    } label: {
                        Label(tr("停止视频壁纸", "Stop Video Wallpaper"), systemImage: "stop.circle")
                    }
                    .help(tr("停止所有视频壁纸播放", "Stop all video wallpapers"))
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: [.image, .movie, .folder],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                let added = library.importURLs(urls)
                importMessage = added > 0
                    ? tr("已导入 \(added) 个壁纸", "Imported \(added) wallpaper(s)")
                    : tr("没有找到新的图片或视频文件", "No new images or videos found")
            }
        }
        .alert(tr("导入完成", "Import Finished"), isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button(tr("好", "OK")) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .alert(tr("出错了", "Something Went Wrong"), isPresented: Binding(
            get: { engine.lastError != nil },
            set: { if !$0 { engine.lastError = nil } }
        )) {
            Button(tr("好", "OK")) { engine.lastError = nil }
        } message: {
            Text(engine.lastError ?? "")
        }
        .frame(minWidth: 880, minHeight: 560)
    }
}
