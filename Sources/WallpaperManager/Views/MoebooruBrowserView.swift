import SwiftUI

/// yande.re / konachan 通用浏览页
struct MoebooruBrowserView: View {
    let source: MoebooruSource
    @Binding var displaySelection: String?
    var isActive: Bool = true

    @ObservedObject private var library = LibraryStore.shared
    @ObservedObject private var l10n = L10n.shared
    private let engine = WallpaperEngine.shared

    @State private var query = ""
    @State private var mode: MoebooruAPI.BrowseMode = .topRated
    @State private var resolution: ResolutionFilter = .any
    @AppStorage("moebooruR18Enabled") private var r18Enabled = false
    @State private var posts: [MoebooruAPI.Post] = []
    @State private var currentPage = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var downloadingIDs: Set<Int> = []

    // 搜索体验:输入即搜(防抖)+ 标签自动补全
    @FocusState private var queryFocused: Bool
    @State private var searchTask: Task<Void, Never>?
    @State private var suggestTask: Task<Void, Never>?
    @State private var suggestions: [String] = []
    // 中文等被自动译成英文搜索时的提示
    @State private var translatedHint: String?

    private let columns = [GridItem(.adaptive(minimum: 220, maximum: 300), spacing: 14)]

    var body: some View {
        VStack(spacing: 0) {
            controlBar
            if showSuggestions {
                suggestionBar
            }
            Divider()
            if let errorMessage, !posts.isEmpty {
                ErrorBanner(message: errorMessage) { self.errorMessage = nil }
            }
            content
        }
        .task(id: isActive) {
            // 首次切到本页时才加载(视图常驻,不能在创建时就联网)
            if isActive && posts.isEmpty && !isLoading { await load(reset: true) }
        }
    }

    private var showSuggestions: Bool {
        !mode.isPopular && queryFocused && !suggestions.isEmpty
    }

    private var controlBar: some View {
        VStack(spacing: 8) {
            // 第一行:搜索框 + 放大镜(标签模式)/ 榜单提示(榜单模式),右侧 NSFW
            HStack(spacing: 8) {
                if mode.isPopular {
                    Label(tr("热门榜单 · 实时", "Popular ranking · live"), systemImage: "flame")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        TextField(tr("搜索标签,可输中文,如 风景、海、猫…",
                                     "Search tags, e.g. landscape, sea, cat…"), text: $query)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 320)
                            .focused($queryFocused)
                            .onSubmit {
                                suggestions = []
                                Task { await load(reset: true) }
                            }
                            .onChange(of: query) {
                                scheduleSearch()
                                scheduleSuggest()
                            }

                        Button {
                            suggestions = []
                            Task { await load(reset: true) }
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
                }

                Spacer()

                Toggle("R-18", isOn: $r18Enabled)
                    .onChange(of: r18Enabled) {
                        Task { await load(reset: true) }
                    }
            }

            // 第二行:浏览方式 / 分辨率
            HStack(spacing: 14) {
                Picker(tr("浏览", "Browse"), selection: $mode) {
                    ForEach(MoebooruAPI.BrowseMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .fixedSize()
                .onChange(of: mode) {
                    suggestions = []
                    Task { await load(reset: true) }
                }

                Picker(tr("分辨率", "Resolution"), selection: $resolution) {
                    ForEach(ResolutionFilter.allCases) { filter in
                        Text(filter.label).tag(filter)
                    }
                }
                .fixedSize()
                .onChange(of: resolution) {
                    Task { await load(reset: true) }
                }

                Spacer()
            }
        }
        .padding(10)
    }

    private var suggestionBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { tag in
                    Button {
                        applySuggestion(tag)
                    } label: {
                        Text(tag)
                            .font(.caption)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help(tr("补全为该标签", "Complete with this tag"))
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var content: some View {
        if let errorMessage, posts.isEmpty {
            // 网络/加载失败
            ContentUnavailableView {
                Label(tr("加载失败", "Failed to Load"), systemImage: "wifi.exclamationmark")
            } description: {
                Text(errorMessage)
            } actions: {
                Button(tr("重试", "Retry")) { Task { await load(reset: true) } }
            }
        } else if posts.isEmpty && isLoading {
            VStack {
                Spacer()
                ProgressView(tr("正在加载…", "Loading…"))
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else if posts.isEmpty {
            // 加载成功但无结果——与网络错误区分开
            ContentUnavailableView {
                Label(mode.isPopular ? tr("榜单暂无结果", "No Ranking Results")
                                     : tr("无匹配结果", "No Matches"),
                      systemImage: "magnifyingglass")
            } description: {
                Text(mode.isPopular
                     ? tr("当前筛选条件下该榜单没有可用壁纸,试试放宽分辨率。",
                          "No wallpapers in this ranking under the current filters. Try a lower resolution.")
                     : tr("没有匹配的图片,换个标签或放宽筛选条件试试。",
                          "No images matched. Try different tags or relax the filters."))
            } actions: {
                if !query.isEmpty && !mode.isPopular {
                    Button(tr("清除关键词", "Clear Query")) {
                        query = ""
                        suggestions = []
                        Task { await load(reset: true) }
                    }
                }
            }
        } else {
            ScrollView {
                let downloaded = Set(library.items.compactMap(\.sourceID))
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(posts) { post in
                        MoebooruCell(
                            post: post,
                            isDownloading: downloadingIDs.contains(post.id),
                            isDownloaded: downloaded.contains(sourceID(for: post)),
                            onDownload: { Task { await download(post, apply: false) } },
                            onDownloadAndApply: { Task { await download(post, apply: true) } }
                        )
                        // 最后一格出现在视口里时才翻页(放在 LazyVGrid 内才有懒加载触发)
                        .onAppear { loadMoreIfNeeded(post) }
                    }
                }
                .padding(14)

                // 仅在确实在翻页时显示加载指示,避免空转的"假加载"
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            }
        }
    }

    private func sourceID(for post: MoebooruAPI.Post) -> String {
        "\(source.rawValue):\(post.id)"
    }

    /// 接近列表末尾时就预取下一页(榜单模式 hasMore 恒为 false,不会触发)
    private func loadMoreIfNeeded(_ post: MoebooruAPI.Post) {
        guard hasMore, !isLoading else { return }
        guard let index = posts.firstIndex(where: { $0.id == post.id }),
              index >= posts.count - 6 else { return }
        Task { await load(reset: false) }
    }

    /// 防抖搜索:停止输入约 0.4s 后自动搜索,无需回车或点按钮
    private func scheduleSearch() {
        searchTask?.cancel()
        searchTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            if Task.isCancelled { return }
            await load(reset: true)
        }
    }

    /// 防抖拉取标签补全建议(针对正在输入的最后一个标签)
    private func scheduleSuggest() {
        suggestTask?.cancel()
        let token = query.hasSuffix(" ")
            ? ""
            : (query.split(separator: " ").last.map(String.init) ?? "")
        guard token.count >= 2 else { suggestions = []; return }
        suggestTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            if Task.isCancelled { return }
            let result = (try? await MoebooruAPI.suggestTags(source: source, prefix: token)) ?? []
            if Task.isCancelled { return }
            suggestions = result
        }
    }

    /// 用选中的建议替换正在输入的最后一个标签,并立即搜索
    private func applySuggestion(_ tag: String) {
        var tokens = query.split(separator: " ", omittingEmptySubsequences: false).map(String.init)
        if tokens.isEmpty || query.hasSuffix(" ") {
            tokens.append(tag)
        } else {
            tokens[tokens.count - 1] = tag
        }
        query = tokens.joined(separator: " ") + " "
        suggestions = []
        searchTask?.cancel()
        Task { await load(reset: true) }
    }

    /// 榜单接口不支持分级/分辨率参数,在客户端按当前筛选条件过滤。
    /// 这些站的热门榜单几乎没有 safe 图,所以安全模式放宽到「隐藏露骨(e),保留 safe+questionable」,
    /// 否则安全模式下榜单常常为空;普通标签搜索仍维持严格 safe-only。
    private func filterPopular(_ posts: [MoebooruAPI.Post]) -> [MoebooruAPI.Post] {
        posts.filter { post in
            if r18Enabled {
                if post.rating == "s" { return false }   // R-18:显示 q + e
            } else if post.rating == "e" {
                return false                              // 安全模式:仅隐藏露骨,显示 s + q
            }
            if let min = resolution.minSize, post.width < min.width || post.height < min.height {
                return false
            }
            return true
        }
    }

    private func load(reset: Bool) async {
        if isLoading { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            if mode.isPopular {
                // 榜单:一次性返回,无分页;分级与分辨率在客户端过滤
                translatedHint = nil
                let all = try await MoebooruAPI.popular(source: source, mode: mode)
                posts = filterPopular(all)
                currentPage = 1
                hasMore = false
            } else {
                // 非英文标签自动译成英文,提升命中率(带缓存,翻页不重复请求)
                let resolved = await TranslationService.shared.resolve(query)
                withAnimation { translatedHint = resolved.didTranslate ? resolved.resolved : nil }
                let page = reset ? 1 : currentPage + 1
                let result = try await MoebooruAPI.search(source: source, tags: resolved.resolved,
                                                          r18: r18Enabled, sortByScore: mode == .topRated,
                                                          minSize: resolution.minSize, page: page)
                if reset {
                    posts = result
                } else {
                    let known = Set(posts.map(\.id))
                    posts.append(contentsOf: result.filter { !known.contains($0.id) })
                }
                currentPage = page
                hasMore = result.count >= MoebooruAPI.pageSize
            }
        } catch {
            errorMessage = tr("无法连接到 ", "Could not reach ")
                + source.host.replacingOccurrences(of: "https://", with: "")
                + tr(",请检查网络。", ". Please check your network. ")
                + "(\(error.localizedDescription))"
        }
    }

    private func download(_ post: MoebooruAPI.Post, apply: Bool) async {
        // 防止连点导致重复下载
        guard !downloadingIDs.contains(post.id) else { return }
        if let existing = library.downloadedItem(sourceID: sourceID(for: post)) {
            if apply { engine.setImageWallpaper(url: existing.url, displayName: displaySelection) }
            return
        }

        downloadingIDs.insert(post.id)
        defer { downloadingIDs.remove(post.id) }

        do {
            let (tempURL, ext) = try await MoebooruAPI.downloadToTemp(post)
            let item = try library.ingestFile(from: tempURL, ext: ext,
                                              sourceID: sourceID(for: post), copyOriginal: false)
            if apply {
                engine.setImageWallpaper(url: item.url, displayName: displaySelection)
            }
        } catch {
            errorMessage = tr("下载失败:", "Download failed: ") + error.localizedDescription
        }
    }
}

struct MoebooruCell: View {
    let post: MoebooruAPI.Post
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
                    url: URL(string: post.thumbURL)!,
                    headers: ["User-Agent": PixivAPI.userAgent]
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
            // .clipped() 不裁剪命中区域,需要显式限定悬停范围
            .contentShape(Rectangle())

            HStack {
                Text(post.resolution)
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
