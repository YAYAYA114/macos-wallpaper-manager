import SwiftUI
import AppKit

struct LibraryGridView: View {
    let section: SidebarSection
    @Binding var displaySelection: String?

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var l10n = L10n.shared
    private let engine = WallpaperEngine.shared

    @State private var selectedID: UUID?

    private var filteredItems: [WallpaperItem] {
        switch section {
        case .images: return library.items.filter { $0.kind == .image }
        case .videos: return library.items.filter { $0.kind == .video }
        case .favorites: return library.items.filter(\.isFavorite)
        default: return library.items
        }
    }

    // 纯贝塞尔缓动(快出缓停):单调减速逼近终点,曲线本身不会回弹
    private static let panelAnimation = Animation.timingCurve(0.22, 1.0, 0.36, 1.0, duration: 0.3)

    /// 列数按窗口总宽计算(面板是覆盖层、不改变窗口宽),所以面板开合时列数恒定。
    /// 用 adaptive 网格时面板滑入会让宽度跨过阈值、3 列"啪"地塌成 2 列——
    /// 缩略图先被挤窄再猛地跳大,这才是观感上的"挤压然后反弹"。
    /// 改为固定列数的 flexible 列后,面板滑入时缩略图只会平滑地一起变窄,无跳变。
    private func columns(totalWidth: CGFloat) -> [GridItem] {
        let count = max(1, Int((totalWidth + 14) / (250 + 14)))
        return Array(repeating: GridItem(.flexible(), spacing: 14), count: count)
    }

    var body: some View {
        // 详情面板做成覆盖式(从右滑入、悬浮在网格之上),而不是系统 inspector 的内联式:
        // 内联式会从窗口抢宽度,导致侧边栏/工具栏/网格在动画的每一帧重排(卡顿 + 内容割裂)。
        ZStack(alignment: .trailing) {
            GeometryReader { geo in
                Group {
                    if filteredItems.isEmpty {
                        emptyState
                    } else {
                        ScrollView {
                            LazyVGrid(columns: columns(totalWidth: geo.size.width), spacing: 14) {
                                ForEach(filteredItems) { item in
                                    WallpaperCell(
                                        item: item,
                                        displaySelection: $displaySelection,
                                        isSelected: selectedID == item.id,
                                        onSelect: { select(item) }
                                    )
                                }
                            }
                            .padding(14)
                        }
                        // 面板展开时整个 ScrollView(连同它的滚动条)同步内缩:
                        // 滚动条落在壁纸与面板的交界处,而不是横跨到窗口最右缘盖住面板信息
                        .padding(.trailing, isPanelOpen ? Self.panelWidth : 0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }

            if let selectedID, library.item(id: selectedID) != nil {
                WallpaperInspectorView(
                    itemID: selectedID,
                    displaySelection: $displaySelection,
                    onClose: { withAnimation(Self.panelAnimation) { self.selectedID = nil } }
                )
                .frame(width: Self.panelWidth)
                .frame(maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .clipped()
                .transition(.move(edge: .trailing))
                .zIndex(1)
            }
        }
    }

    private static let panelWidth = WallpaperInspectorView.preferredWidth

    private var isPanelOpen: Bool {
        guard let id = selectedID else { return false }
        return library.item(id: id) != nil
    }

    private func select(_ item: WallpaperItem) {
        if selectedID == item.id {
            // 再次点击同一张收起面板(不影响已设置的壁纸)
            withAnimation(Self.panelAnimation) { selectedID = nil }
        } else {
            // 选中即设为壁纸
            withAnimation(Self.panelAnimation) { selectedID = item.id }
            engine.apply(item, displayName: displaySelection)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(emptyTitle, systemImage: section.icon)
        } description: {
            Text(emptyDescription)
        }
    }

    private var emptyTitle: String {
        switch section {
        case .favorites: return tr("还没有收藏", "No Favorites Yet")
        case .videos: return tr("还没有视频壁纸", "No Video Wallpapers Yet")
        case .images: return tr("还没有图片壁纸", "No Image Wallpapers Yet")
        default: return tr("壁纸库是空的", "Your Library Is Empty")
        }
    }

    private var emptyDescription: String {
        switch section {
        case .favorites:
            return tr("在壁纸上右键选择「收藏」,就会出现在这里。",
                      "Right-click a wallpaper and choose \"Favorite\" to see it here.")
        default:
            return tr("点击右上角「+」导入图片、视频或整个文件夹,也可以去「在线壁纸」逛逛。",
                      "Click \"+\" in the toolbar to import images, videos, or folders — or browse the Discover sources.")
        }
    }
}

struct WallpaperCell: View {
    let item: WallpaperItem
    @Binding var displaySelection: String?
    var isSelected: Bool = false
    var onSelect: () -> Void = {}

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var l10n = L10n.shared
    private let engine = WallpaperEngine.shared

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LocalThumbnailView(url: item.url)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.1),
                                      lineWidth: isSelected ? 2.5 : 1)
                }

            HStack(spacing: 4) {
                if item.kind == .video {
                    badge(systemImage: "video.fill")
                }
                if item.isFavorite {
                    badge(systemImage: "heart.fill")
                }
            }
            .padding(6)
        }
        // .clipped() 不裁剪命中区域,需要显式限定点击范围
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .contextMenu { contextMenuItems }
    }

    private func badge(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .font(.caption2)
            .foregroundStyle(.white)
            .padding(5)
            .background(.black.opacity(0.55), in: Circle())
    }

    @ViewBuilder
    private var contextMenuItems: some View {
        Button(tr("设为壁纸", "Set as Wallpaper")) {
            engine.apply(item, displayName: displaySelection)
        }
        Button(item.isFavorite ? tr("取消收藏", "Unfavorite") : tr("收藏", "Favorite")) {
            library.toggleFavorite(item)
        }
        Divider()
        Button(tr("在访达中显示", "Show in Finder")) {
            NSWorkspace.shared.activateFileViewerSelecting([item.url])
        }
        Divider()
        Button(tr("从库中移除", "Remove from Library"), role: .destructive) {
            library.remove(item)
        }
    }
}
