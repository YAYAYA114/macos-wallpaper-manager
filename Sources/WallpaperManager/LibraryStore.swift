import Foundation
import AppKit

/// 本地壁纸库:负责条目的持久化、导入、收藏与删除。
@MainActor
final class LibraryStore: ObservableObject {
    static let shared = LibraryStore()

    @Published private(set) var items: [WallpaperItem] = []

    private let fileManager = FileManager.default

    /// ~/Library/Application Support/WallpaperManager/
    let appSupportDirectory: URL
    /// 在线下载的壁纸保存在这里
    let downloadsDirectory: URL
    private let libraryFile: URL

    private init() {
        // 受限/沙盒环境下 Application Support 目录可能取不到,回退到临时目录避免启动崩溃
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let base = appSupport
            .appendingPathComponent("WallpaperManager", isDirectory: true)
        appSupportDirectory = base
        downloadsDirectory = base.appendingPathComponent("Wallpapers", isDirectory: true)
        libraryFile = base.appendingPathComponent("library.json")

        try? fileManager.createDirectory(at: downloadsDirectory, withIntermediateDirectories: true)
        load()
        pruneMissingFiles()
        cleanupOrphanFiles()
    }

    /// 把库目录里没有任何条目引用的残留文件移到废纸篓
    private func cleanupOrphanFiles() {
        let referenced = Set(items.map(\.path))
        let files = (try? fileManager.contentsOfDirectory(at: downloadsDirectory,
                                                          includingPropertiesForKeys: nil,
                                                          options: [.skipsHiddenFiles])) ?? []
        for file in files where !referenced.contains(file.path) {
            try? fileManager.trashItem(at: file, resultingItemURL: nil)
        }
    }

    // MARK: - 持久化

    private func load() {
        guard let data = try? Data(contentsOf: libraryFile) else { return }
        if let decoded = try? JSONDecoder().decode([WallpaperItem].self, from: data) {
            items = decoded
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: libraryFile, options: .atomic)
    }

    /// 移除磁盘上已不存在的条目
    private func pruneMissingFiles() {
        let before = items.count
        items.removeAll { !fileManager.fileExists(atPath: $0.path) }
        if items.count != before { save() }
    }

    // MARK: - 归档命名

    /// 生成形如 20260611-001-a3f2.jpg 的目标路径。
    /// 末尾的随机串保证文件名永不复用 —— 否则移除后被回收的序号会让新文件命中
    /// macOS 桌面图片缓存 / 缩略图缓存里旧文件的内容(出现"设 A 显示 B")。
    private func nextDatedURL(ext: String) -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd"
        let prefix = formatter.string(from: Date())

        var maxSeq = 0
        let existing = (try? fileManager.contentsOfDirectory(atPath: downloadsDirectory.path)) ?? []
        for name in existing where name.hasPrefix(prefix + "-") {
            let seqPart = name.dropFirst(prefix.count + 1).prefix(while: \.isNumber)
            maxSeq = max(maxSeq, Int(seqPart) ?? 0)
        }

        var seq = maxSeq + 1
        var url: URL
        repeat {
            let token = String(UUID().uuidString.prefix(4)).lowercased()
            url = downloadsDirectory.appendingPathComponent(
                String(format: "%@-%03d-%@.%@", prefix, seq, token, ext))
            seq += 1
        } while fileManager.fileExists(atPath: url.path)
        return url
    }

    /// 把文件收进壁纸库目录(按日期编号重命名)并登记。
    /// `copyOriginal` 为 true 拷贝(保留原文件),false 移动(用于临时下载文件)。
    @discardableResult
    func ingestFile(from sourceURL: URL, ext: String,
                    sourceID: String? = nil, originPath: String? = nil,
                    copyOriginal: Bool) throws -> WallpaperItem {
        let normalizedExt = ext.lowercased()
        guard let kind = MediaFileType.kind(of: URL(fileURLWithPath: "x.\(normalizedExt)")) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let destination = nextDatedURL(ext: normalizedExt)
        if copyOriginal {
            try fileManager.copyItem(at: sourceURL, to: destination)
        } else {
            try fileManager.moveItem(at: sourceURL, to: destination)
        }
        let item = WallpaperItem(path: destination.path, kind: kind,
                                 sourceID: sourceID, originPath: originPath)
        items.append(item)
        sortItems()
        save()
        return item
    }

    // MARK: - 导入

    /// 导入文件或文件夹(文件夹会递归扫描图片/视频)。
    /// 文件会被拷贝到壁纸库目录并按日期编号重命名,原文件可以安全删除。
    func importURLs(_ urls: [URL]) -> Int {
        var added = 0
        var seenOrigins = Set(items.compactMap(\.originPath))
        let libraryPaths = Set(items.map(\.path))

        for url in urls {
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }

            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            let candidates: [URL]
            if isDirectory.boolValue {
                let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: nil,
                                                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
                candidates = (enumerator?.compactMap { $0 as? URL }) ?? []
            } else {
                candidates = [url]
            }

            for candidate in candidates {
                guard MediaFileType.kind(of: candidate) != nil else { continue }
                let path = candidate.path
                // 跳过重复导入,以及壁纸库目录里已登记的文件
                guard !seenOrigins.contains(path), !libraryPaths.contains(path) else { continue }
                guard (try? ingestFile(from: candidate, ext: candidate.pathExtension,
                                       originPath: path, copyOriginal: true)) != nil else { continue }
                seenOrigins.insert(path)
                added += 1
            }
        }
        return added
    }

    private func sortItems() {
        items.sort { $0.addedAt > $1.addedAt }
    }

    // MARK: - 修改

    func toggleFavorite(_ item: WallpaperItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index].isFavorite.toggle()
        save()
    }

    /// 修改条目(显示方式、音量等)并持久化
    func updateItem(id: UUID, _ mutate: (inout WallpaperItem) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[index])
        save()
    }

    func item(id: UUID) -> WallpaperItem? {
        items.first { $0.id == id }
    }

    /// 从库中移除条目。库目录里归档的文件会一并移到废纸篓(避免残留孤儿文件);
    /// 旧版直接引用库外路径的条目只解除登记,不动用户的原始文件。
    func remove(_ item: WallpaperItem) {
        items.removeAll { $0.id == item.id }
        save()
        if item.path.hasPrefix(downloadsDirectory.path) {
            try? fileManager.trashItem(at: item.url, resultingItemURL: nil)
        }
    }

    /// 按在线来源标识查找已下载的条目
    func downloadedItem(sourceID: String) -> WallpaperItem? {
        items.first { $0.sourceID == sourceID }
    }

    /// 按在线来源查找已下载的条目(兼容旧版按文件名前缀保存的条目)
    func downloadedItem(wallhavenID: String) -> WallpaperItem? {
        items.first { $0.sourceID == "wallhaven:\(wallhavenID)" || $0.fileName.hasPrefix("wallhaven-\(wallhavenID).") }
    }

    func downloadedItem(pixivID: Int) -> WallpaperItem? {
        items.first { $0.sourceID == "pixiv:\(pixivID)" || $0.fileName.hasPrefix("pixiv-\(pixivID).") }
    }
}
