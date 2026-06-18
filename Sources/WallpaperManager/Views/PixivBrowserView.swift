import SwiftUI

struct PixivBrowserView: View {
    @Binding var displaySelection: String?
    var isActive: Bool = true

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var l10n = L10n.shared
    private let engine = WallpaperEngine.shared

    @State private var mode: PixivAPI.RankingMode = .daily
    @State private var resolution: ResolutionFilter = .any
    @AppStorage("pixivR18Enabled") private var r18Enabled = false
    @AppStorage(PixivAPI.sessionCookieKey) private var sessionCookie = ""
    @State private var showCookieSettings = false
    @State private var illusts: [PixivAPI.Illust] = []
    @State private var currentPage = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadingIDs: Set<Int> = []

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            Divider()
            if let errorMessage, !illusts.isEmpty {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
            content
        }
        .task(id: isActive) {
            // R-18 开关是持久化的,启动时让榜单选择与之对齐
            if r18Enabled && !mode.isR18 { mode = .dailyR18 }
            // 首次切到本页时才加载(视图常驻,不能在创建时就联网)
            if isActive && illusts.isEmpty && !isLoading { await load(reset: true) }
        }
    }

    // Pixiv 排行榜接口不支持分辨率参数,在客户端按宽高过滤
    private var filteredIllusts: [PixivAPI.Illust] {
        illusts.filter { resolution.matches(width: $0.width, height: $0.height) }
    }

    private var controlBar: some View {
        HStack {
            Picker(tr("排行榜", "Ranking"), selection: $mode) {
                ForEach(r18Enabled ? PixivAPI.RankingMode.r18 : PixivAPI.RankingMode.allAges) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .frame(maxWidth: 180)
            .onChange(of: mode) {
                Task { await load(reset: true) }
            }

            Picker(tr("分辨率", "Resolution"), selection: $resolution) {
                ForEach(ResolutionFilter.allCases) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .frame(maxWidth: 200)
            .onChange(of: resolution) {
                // 提高筛选标准后可见数量骤减时,自动补页
                if filteredIllusts.count < 12 && hasMore {
                    Task { await load(reset: false) }
                }
            }

            Toggle("R-18", isOn: $r18Enabled)
                .onChange(of: r18Enabled) {
                    // 两套榜单互不相通,切换时回到各自的"今日"榜
                    mode = r18Enabled ? .dailyR18 : .daily
                }
                .help(tr("需要在钥匙按钮里填入 pixiv 登录 Cookie,且账号已开启 R-18 显示",
                         "Requires a pixiv login cookie (key button) and R-18 enabled on your pixiv account"))

            Button {
                showCookieSettings = true
            } label: {
                Label(tr("登录设置", "Sign-in Settings"), systemImage: sessionCookie.isEmpty ? "key.slash" : "key.fill")
            }
            .help(tr("设置 pixiv 登录 Cookie(浏览 R-18 内容需要)",
                     "Set your pixiv login cookie (required for R-18 content)"))
            .popover(isPresented: $showCookieSettings, arrowEdge: .bottom) {
                cookieSettings
            }

            Button {
                Task { await load(reset: true) }
            } label: {
                Label(tr("刷新", "Refresh"), systemImage: "arrow.clockwise")
            }

            Spacer()
        }
        .padding(10)
    }

    private var cookieSettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tr("pixiv 登录 Cookie", "pixiv Login Cookie"))
                .font(.headline)
            Text(tr("""
            浏览 R-18 排行榜需要登录态,获取方法:
            1. 用浏览器登录 pixiv.net(账号需在 pixiv「设置 → 浏览限制」中开启 R-18);
            2. 打开开发者工具(⌥⌘I)→「存储/Application」→ Cookie;
            3. 复制名为 PHPSESSID 的值,粘贴到下面。
            Cookie 只保存在本机,仅用于请求 pixiv。
            """, """
            Browsing R-18 rankings requires being signed in:
            1. Sign in to pixiv.net in your browser (enable R-18 under pixiv Settings → Viewing restrictions);
            2. Open Developer Tools (⌥⌘I) → Storage/Application → Cookies;
            3. Copy the value named PHPSESSID and paste it below.
            The cookie is stored locally and only sent to pixiv.
            """))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            TextField("PHPSESSID", text: $sessionCookie)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack {
                Spacer()
                Button(tr("完成", "Done")) {
                    showCookieSettings = false
                    if r18Enabled { Task { await load(reset: true) } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, illusts.isEmpty {
            ContentUnavailableView {
                Label(tr("加载失败", "Failed to Load"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(tr("重试", "Retry")) { Task { await load(reset: true) } }
            }
        } else if illusts.isEmpty && isLoading {
            VStack {
                Spacer()
                ProgressView(tr("正在加载 Pixiv 排行榜…", "Loading pixiv rankings…"))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(filteredIllusts) { illust in
                        PixivCell(
                            illust: illust,
                            isDownloading: downloadingIDs.contains(illust.id),
                            isDownloaded: library.downloadedItem(pixivID: illust.illustID) != nil,
                            onDownload: { Task { await download(illust, apply: false) } },
                            onDownloadAndApply: { Task { await download(illust, apply: true) } }
                        )
                        // 最后一格出现在视口里时才翻页(放在 LazyVGrid 内才有懒加载触发)
                        .onAppear { loadMoreIfNeeded(illust) }
                    }
                }
                .padding(14)

                // 仅在确实在翻页时显示加载指示
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    /// 滚到最后一格时加载下一页(榜单按分辨率客户端过滤,以可见列表的末项为准)
    private func loadMoreIfNeeded(_ illust: PixivAPI.Illust) {
        guard hasMore, !isLoading, illust.id == filteredIllusts.last?.id else { return }
        Task { await load(reset: false) }
    }

    private func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // pixiv 接口不支持按分辨率筛选,只能在客户端过滤;
            // 单页命中太少时自动连续翻页补足,避免"加载更多只多出两三张"
            var fetched: [PixivAPI.Illust] = []
            var more = true
            var page = reset ? 1 : currentPage + 1
            var pagesFetched = 0
            repeat {
                let result = try await PixivAPI.ranking(mode: mode, page: page)
                fetched.append(contentsOf: result.illusts)
                more = result.hasMore
                currentPage = page
                page += 1
                pagesFetched += 1
                let matching = fetched.filter { resolution.matches(width: $0.width, height: $0.height) }.count
                if matching >= 12 || !more || pagesFetched >= 4 { break }
            } while true

            if reset {
                illusts = fetched
            } else {
                // 排行榜实时变动,翻页可能出现重复作品;重复 ID 会破坏列表渲染,必须去重
                let known = Set(illusts.map(\.id))
                illusts.append(contentsOf: fetched.filter { !known.contains($0.id) })
            }
            hasMore = more
        } catch let error as PixivAPI.PixivError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = tr("无法连接到 pixiv.net,请检查网络。", "Could not reach pixiv.net. Please check your network. ")
                + "(\(error.localizedDescription))"
        }
    }

    private func download(_ illust: PixivAPI.Illust, apply: Bool) async {
        // 防止连点导致重复下载
        guard !downloadingIDs.contains(illust.id) else { return }
        // 已下载过就直接用库里的文件
        if let existing = library.downloadedItem(pixivID: illust.illustID) {
            if apply { engine.setImageWallpaper(url: existing.url, displayName: displaySelection) }
            return
        }

        downloadingIDs.insert(illust.id)
        defer { downloadingIDs.remove(illust.id) }

        do {
            let (tempURL, ext) = try await PixivAPI.downloadToTemp(illust)
            let item = try library.ingestFile(from: tempURL, ext: ext,
                                              sourceID: "pixiv:\(illust.illustID)", copyOriginal: false)
            if apply {
                engine.setImageWallpaper(url: item.url, displayName: displaySelection)
            }
        } catch {
            errorMessage = tr("下载失败:", "Download failed: ") + error.localizedDescription
        }
    }
}

struct PixivCell: View {
    let illust: PixivAPI.Illust
    let isDownloading: Bool
    let isDownloaded: Bool
    let onDownload: () -> Void
    let onDownloadAndApply: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                RemoteImageView(
                    url: URL(string: illust.url)!,
                    headers: PixivAPI.imageHeaders
                )
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 10))

                if isHovering && !isDownloading {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.35))
                    VStack(spacing: 8) {
                        Button(tr("设为壁纸", "Set as Wallpaper"), action: onDownloadAndApply)
                            .buttonStyle(.borderedProminent)
                        Button(isDownloaded ? tr("已在壁纸库", "In Library") : tr("下载到壁纸库", "Download to Library"),
                               action: onDownload)
                            .disabled(isDownloaded)
                    }
                }

                if isDownloading {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(0.45))
                    ProgressView(tr("下载中…", "Downloading…"))
                        .controlSize(.small)
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            // .clipped() 不裁剪命中区域,竖图溢出会把悬停范围扩到相邻空白,需要显式限定
            .contentShape(Rectangle())

            Text(illust.title)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack {
                Text(illust.userName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Text(illust.resolution)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                if isDownloaded {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .help(tr("已下载到壁纸库", "Downloaded to library"))
                }
            }
        }
        .onHover { isHovering = $0 }
    }
}
