import SwiftUI

struct OnlineBrowserView: View {
    @Binding var displaySelection: String?
    var isActive: Bool = true

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var l10n = L10n.shared
    private let engine = WallpaperEngine.shared

    @State private var query = ""
    @State private var sorting: WallhavenAPI.Sorting = .toplist
    @State private var topRange: WallhavenAPI.TopRange = .month
    @State private var resolution: ResolutionFilter = .any
    @AppStorage("wallhavenR18Enabled") private var r18Enabled = false
    @AppStorage(WallhavenAPI.apiKeyKey) private var apiKey = ""
    @State private var showKeySettings = false
    @State private var wallpapers: [WallhavenAPI.Wallpaper] = []
    @State private var currentPage = 0
    @State private var lastPage = 1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadingIDs: Set<String> = []
    @State private var searchTask: Task<Void, Never>?
    // 中文等被自动译成英文搜索时,给出提示让用户知道实际搜的是什么
    @State private var translatedHint: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            if let errorMessage, !wallpapers.isEmpty {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
            content
        }
        .task(id: isActive) {
            // 首次切到本页时才加载(视图常驻,不能在创建时就联网)
            if isActive && wallpapers.isEmpty && !isLoading { await search(reset: true) }
        }
    }

    private var searchBar: some View {
        VStack(spacing: 8) {
            // 第一行:搜索框 + 放大镜按钮(左),NSFW 与 API Key(右)
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    TextField(tr("搜索壁纸,可输中文,如 风景、城市、动漫…",
                                 "Search wallpapers, e.g. nature, city, anime…"), text: $query)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 360)
                        .onSubmit {
                            searchTask?.cancel()
                            Task { await search(reset: true) }
                        }
                        .onChange(of: query) { scheduleSearch() }

                    Button {
                        searchTask?.cancel()
                        Task { await search(reset: true) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(tr("搜索", "Search"))

                    if let translatedHint {
                        Text("→ \(translatedHint)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .help(tr("已自动翻译为英文搜索", "Auto-translated to English for searching"))
                            .transition(.opacity)
                    }
                }

                Spacer()

                Toggle("R-18", isOn: $r18Enabled)
                    .onChange(of: r18Enabled) {
                        Task { await search(reset: true) }
                    }
                    .help(tr("浏览 NSFW 内容需要 wallhaven API Key(钥匙按钮)",
                             "Browsing NSFW content requires a wallhaven API key (key button)"))

                Button {
                    showKeySettings = true
                } label: {
                    Image(systemName: apiKey.isEmpty ? "key.slash" : "key.fill")
                }
                .help(tr("设置 wallhaven API Key(浏览 NSFW 内容需要)",
                         "Set your wallhaven API key (required for NSFW content)"))
                .popover(isPresented: $showKeySettings, arrowEdge: .bottom) {
                    keySettings
                }
            }

            // 第二行:排序 / 时间范围 / 分辨率,留足空间不再拥挤
            HStack(spacing: 14) {
                Picker(tr("排序", "Sort"), selection: $sorting) {
                    ForEach(WallhavenAPI.Sorting.allCases) { sorting in
                        Text(sorting.label).tag(sorting)
                    }
                }
                .fixedSize()
                .onChange(of: sorting) {
                    Task { await search(reset: true) }
                }

                // 时间范围:仅热门榜单可选(日 / 周 / 月…)
                if sorting.supportsTopRange {
                    Picker(tr("时间", "Range"), selection: $topRange) {
                        ForEach(WallhavenAPI.TopRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .fixedSize()
                    .onChange(of: topRange) {
                        Task { await search(reset: true) }
                    }
                }

                Picker(tr("分辨率", "Resolution"), selection: $resolution) {
                    ForEach(ResolutionFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .fixedSize()
                .onChange(of: resolution) {
                    Task { await search(reset: true) }
                }

                Spacer()
            }
        }
        .padding(10)
    }

    private var keySettings: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("wallhaven API Key")
                .font(.headline)
            Text(tr("""
            浏览 NSFW 内容需要 API Key,获取方法:
            1. 注册并登录 wallhaven.cc(设置中开启 NSFW 显示);
            2. 打开 wallhaven.cc/settings/account,复制 API Key 粘贴到下面。
            Key 只保存在本机,仅用于请求 wallhaven。
            """, """
            Browsing NSFW content requires an API key:
            1. Sign up and sign in at wallhaven.cc (enable NSFW in settings);
            2. Open wallhaven.cc/settings/account and copy your API key below.
            The key is stored locally and only sent to wallhaven.
            """))
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            TextField("API Key", text: $apiKey)
                .textFieldStyle(.roundedBorder)
                .frame(width: 360)

            HStack {
                Spacer()
                Button(tr("完成", "Done")) {
                    showKeySettings = false
                    if r18Enabled { Task { await search(reset: true) } }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, wallpapers.isEmpty {
            ContentUnavailableView {
                Label(tr("加载失败", "Failed to Load"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(tr("重试", "Retry")) { Task { await search(reset: true) } }
            }
        } else if wallpapers.isEmpty && isLoading {
            VStack {
                Spacer()
                ProgressView(tr("正在加载在线壁纸…", "Loading wallpapers…"))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if wallpapers.isEmpty {
            // 加载成功但无结果——与网络错误区分开
            ContentUnavailableView {
                Label(tr("无匹配结果", "No Matches"), systemImage: "magnifyingglass")
            } description: {
                Text(tr("没有匹配的壁纸,换个关键词或放宽筛选条件试试。",
                        "No wallpapers matched. Try a different keyword or relax the filters."))
            } actions: {
                if !query.isEmpty {
                    Button(tr("清除关键词", "Clear Query")) {
                        query = ""
                        searchTask?.cancel()
                        Task { await search(reset: true) }
                    }
                }
            }
        } else {
            ScrollView {
                let downloaded = downloadedWallhavenIDs
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(wallpapers) { wallpaper in
                        OnlineWallpaperCell(
                            wallpaper: wallpaper,
                            isDownloading: downloadingIDs.contains(wallpaper.id),
                            isDownloaded: downloaded.contains(wallpaper.id),
                            onDownload: { Task { await download(wallpaper, apply: false) } },
                            onDownloadAndApply: { Task { await download(wallpaper, apply: true) } }
                        )
                        // 最后一格出现在视口里时才翻页(放在 LazyVGrid 内才有懒加载触发)
                        .onAppear { loadMoreIfNeeded(wallpaper) }
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

    /// 已下载的 wallhaven 图片 ID 集合,整页渲染前算一次,卡片查询 O(1)
    private var downloadedWallhavenIDs: Set<String> {
        var ids = Set<String>()
        for item in library.items {
            if let sid = item.sourceID, sid.hasPrefix("wallhaven:") {
                ids.insert(String(sid.dropFirst("wallhaven:".count)))
            } else if item.fileName.hasPrefix("wallhaven-") {
                // 旧版按文件名前缀保存:wallhaven-<id>.ext
                let rest = item.fileName.dropFirst("wallhaven-".count)
                if let dot = rest.firstIndex(of: ".") { ids.insert(String(rest[..<dot])) }
            }
        }
        return ids
    }

    /// 接近列表末尾(还剩约一行半)时就预取下一页,滚动到底不再卡顿等待
    private func loadMoreIfNeeded(_ wallpaper: WallhavenAPI.Wallpaper) {
        guard currentPage < lastPage, !isLoading else { return }
        guard let index = wallpapers.firstIndex(where: { $0.id == wallpaper.id }),
              index >= wallpapers.count - 6 else { return }
        Task { await search(reset: false) }
    }

    /// 防抖搜索:停止输入约 0.4s 后自动搜索
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await search(reset: true)
        }
    }

    private func search(reset: Bool) async {
        if isLoading { return }
        // NSFW 必须带 Key,否则接口静默返回空列表,提前给出明确引导
        if r18Enabled && apiKey.isEmpty {
            wallpapers = []
            errorMessage = tr("浏览 NSFW 内容需要 wallhaven API Key:点击顶栏的钥匙按钮填入(注册 wallhaven.cc 后在账号设置里免费获取)。",
                              "Browsing NSFW content requires a wallhaven API key: click the key button in the toolbar (free with a wallhaven.cc account).")
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // 非英文搜索词自动译成英文,提升命中率(结果带缓存,翻页不重复请求)
            let resolved = await TranslationService.shared.resolve(query)
            withAnimation { translatedHint = resolved.didTranslate ? resolved.resolved : nil }
            let page = reset ? 1 : currentPage + 1
            let result = try await WallhavenAPI.search(query: resolved.resolved, sorting: sorting,
                                                       topRange: topRange, page: page,
                                                       atLeast: resolution.wallhavenAtLeast,
                                                       nsfw: r18Enabled)
            if reset {
                wallpapers = result.wallpapers
            } else {
                // 随机排序等场景翻页可能返回重复条目;重复 ID 会破坏列表渲染,必须去重
                let known = Set(wallpapers.map(\.id))
                wallpapers.append(contentsOf: result.wallpapers.filter { !known.contains($0.id) })
            }
            currentPage = result.currentPage
            lastPage = result.lastPage
        } catch {
            errorMessage = tr("无法连接到 wallhaven.cc,请检查网络。", "Could not reach wallhaven.cc. Please check your network. ")
                + "(\(error.localizedDescription))"
        }
    }

    private func download(_ wallpaper: WallhavenAPI.Wallpaper, apply: Bool) async {
        // 防止连点导致重复下载
        guard !downloadingIDs.contains(wallpaper.id) else { return }
        // 已下载过就直接用库里的文件
        if let existing = library.downloadedItem(wallhavenID: wallpaper.id) {
            if apply { engine.setImageWallpaper(url: existing.url, displayName: displaySelection) }
            return
        }

        downloadingIDs.insert(wallpaper.id)
        defer { downloadingIDs.remove(wallpaper.id) }

        do {
            let (tempURL, ext) = try await WallhavenAPI.downloadToTemp(wallpaper)
            let item = try library.ingestFile(from: tempURL, ext: ext,
                                              sourceID: "wallhaven:\(wallpaper.id)", copyOriginal: false)
            if apply {
                engine.setImageWallpaper(url: item.url, displayName: displaySelection)
            }
        } catch {
            errorMessage = tr("下载失败:", "Download failed: ") + error.localizedDescription
        }
    }
}

struct OnlineWallpaperCell: View {
    let wallpaper: WallhavenAPI.Wallpaper
    let isDownloading: Bool
    let isDownloaded: Bool
    let onDownload: () -> Void
    let onDownloadAndApply: () -> Void

    @ObservedObject private var l10n = L10n.shared
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                // 与 Moebooru 统一:RemoteImageView 会把样张下采样到缩略图尺寸并缓存,
                // 滚动 / 回滚时命中缓存,避免 AsyncImage 反复解码大图带来的卡顿和内存膨胀。
                RemoteImageView(url: URL(string: wallpaper.thumbs.large)!)
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
            // .clipped() 不裁剪命中区域,溢出的图片会扩大悬停范围,需要显式限定
            .contentShape(Rectangle())

            HStack {
                Text(wallpaper.resolution)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
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
