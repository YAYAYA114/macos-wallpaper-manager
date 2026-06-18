import AppKit
import AVFoundation

/// 负责把图片/视频真正应用为桌面壁纸,支持多显示器与每张壁纸独立的显示设置。
@MainActor
final class WallpaperEngine: ObservableObject {
    static let shared = WallpaperEngine()

    /// 每个显示器当前的视频壁纸窗口
    private var videoWindows: [CGDirectDisplayID: VideoWallpaperWindow] = [:]
    /// 每个显示器当前的图片壁纸路径(用于设置变更时的即时重应用,不持久化)
    private var imageAssignments: [CGDirectDisplayID: String] = [:]

    /// 持久化的视频壁纸分配(displayID 字符串 -> 视频路径),用于下次启动恢复
    @Published private(set) var videoAssignments: [String: String] {
        didSet { UserDefaults.standard.set(videoAssignments, forKey: "videoAssignments") }
    }

    @Published var lastError: String?

    private init() {
        videoAssignments = (UserDefaults.standard.dictionary(forKey: "videoAssignments") as? [String: String]) ?? [:]
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleScreenChange()
            }
        }
    }

    var hasActiveVideoWallpaper: Bool { !videoWindows.isEmpty }

    // MARK: - 显示器

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value ?? 0
    }

    /// `displayName` 为 nil 表示所有显示器
    private func targetScreens(displayName: String?) -> [NSScreen] {
        guard let displayName else { return NSScreen.screens }
        return NSScreen.screens.filter { $0.localizedName == displayName }
    }

    // MARK: - 显示方式映射

    static func imageOptions(for mode: WallpaperDisplayMode) -> [NSWorkspace.DesktopImageOptionKey: Any] {
        switch mode {
        case .fill:
            return [.imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                    .allowClipping: true]
        case .fit:
            return [.imageScaling: NSNumber(value: NSImageScaling.scaleProportionallyUpOrDown.rawValue),
                    .allowClipping: false,
                    .fillColor: NSColor.black]
        case .stretch:
            return [.imageScaling: NSNumber(value: NSImageScaling.scaleAxesIndependently.rawValue)]
        case .center:
            return [.imageScaling: NSNumber(value: NSImageScaling.scaleNone.rawValue),
                    .allowClipping: false,
                    .fillColor: NSColor.black]
        }
    }

    static func videoGravity(for mode: WallpaperDisplayMode) -> AVLayerVideoGravity {
        switch mode {
        case .fill: return .resizeAspectFill
        case .fit, .center: return .resizeAspect
        case .stretch: return .resize
        }
    }

    // MARK: - 图片壁纸

    func setImageWallpaper(url: URL, displayName: String?, mode: WallpaperDisplayMode = .fill) {
        lastError = nil
        for screen in targetScreens(displayName: displayName) {
            // 该屏如有视频壁纸先停掉,否则图片会被视频窗口盖住
            stopVideoWallpaper(on: screen)
            do {
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: Self.imageOptions(for: mode))
                imageAssignments[Self.displayID(of: screen)] = url.path
            } catch {
                lastError = tr("设置壁纸失败:", "Failed to set wallpaper: ") + error.localizedDescription
            }
        }
    }

    // MARK: - 视频壁纸

    func setVideoWallpaper(url: URL, displayName: String?,
                           mode: WallpaperDisplayMode = .fill,
                           soundEnabled: Bool = false, volume: Double = 0.5) {
        lastError = nil
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = tr("视频文件不存在:", "Video file not found: ") + url.path
            return
        }
        for screen in targetScreens(displayName: displayName) {
            let displayID = Self.displayID(of: screen)
            videoWindows[displayID]?.close()
            let window = VideoWallpaperWindow(screen: screen, videoURL: url,
                                              gravity: Self.videoGravity(for: mode),
                                              muted: !soundEnabled, volume: Float(volume))
            videoWindows[displayID] = window
            videoAssignments[String(displayID)] = url.path
            imageAssignments[displayID] = nil
        }
        objectWillChange.send()
    }

    /// 便捷入口:按壁纸条目自身保存的设置应用
    func apply(_ item: WallpaperItem, displayName: String?) {
        switch item.kind {
        case .image:
            setImageWallpaper(url: item.url, displayName: displayName, mode: item.effectiveDisplayMode)
        case .video:
            setVideoWallpaper(url: item.url, displayName: displayName,
                              mode: item.effectiveDisplayMode,
                              soundEnabled: item.effectiveSoundEnabled,
                              volume: item.effectiveVolume)
        }
    }

    /// 壁纸条目的设置变更后调用:如果它正在某块屏幕上使用,即时套用新设置
    func refreshIfActive(_ item: WallpaperItem) {
        switch item.kind {
        case .image:
            for screen in NSScreen.screens
            where imageAssignments[Self.displayID(of: screen)] == item.path {
                try? NSWorkspace.shared.setDesktopImageURL(
                    item.url, for: screen, options: Self.imageOptions(for: item.effectiveDisplayMode))
            }
        case .video:
            for (displayID, window) in videoWindows
            where videoAssignments[String(displayID)] == item.path {
                window.setGravity(Self.videoGravity(for: item.effectiveDisplayMode))
                window.setAudio(muted: !item.effectiveSoundEnabled, volume: Float(item.effectiveVolume))
            }
        }
    }

    /// 该壁纸当前是否在任一屏幕上使用
    func isActive(_ item: WallpaperItem) -> Bool {
        imageAssignments.values.contains(item.path) || videoAssignments.values.contains(item.path)
    }

    func stopVideoWallpaper(on screen: NSScreen) {
        let displayID = Self.displayID(of: screen)
        videoWindows[displayID]?.close()
        videoWindows[displayID] = nil
        videoAssignments[String(displayID)] = nil
        objectWillChange.send()
    }

    func stopAllVideoWallpapers() {
        for window in videoWindows.values { window.close() }
        videoWindows.removeAll()
        videoAssignments.removeAll()
        objectWillChange.send()
    }

    /// 启动时恢复上次的视频壁纸(沿用各壁纸保存的显示/声音设置)
    func restoreVideoWallpapers() {
        for screen in NSScreen.screens {
            let displayID = String(Self.displayID(of: screen))
            guard let path = videoAssignments[displayID],
                  FileManager.default.fileExists(atPath: path) else { continue }
            let item = LibraryStore.shared.items.first { $0.path == path }
            let mode = item?.effectiveDisplayMode ?? .fill
            let window = VideoWallpaperWindow(screen: screen, videoURL: URL(fileURLWithPath: path),
                                              gravity: Self.videoGravity(for: mode),
                                              muted: !(item?.effectiveSoundEnabled ?? false),
                                              volume: Float(item?.effectiveVolume ?? 0.5))
            videoWindows[Self.displayID(of: screen)] = window
        }
        objectWillChange.send()
    }

    /// 显示器插拔/分辨率变化时,重建视频窗口
    private func handleScreenChange() {
        for window in videoWindows.values { window.close() }
        videoWindows.removeAll()
        restoreVideoWallpapers()
    }
}

/// 位于桌面图标下方的无边框全屏窗口,循环播放视频。
final class VideoWallpaperWindow: NSWindow {
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    init(screen: NSScreen, videoURL: URL,
         gravity: AVLayerVideoGravity = .resizeAspectFill,
         muted: Bool = true, volume: Float = 0.5) {
        super.init(contentRect: screen.frame,
                   styleMask: [.borderless],
                   backing: .buffered,
                   defer: false)

        // 关键:窗口层级设为桌面层,正好位于桌面图标之下、纯色桌面之上
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)))
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isOpaque = true
        backgroundColor = .black
        ignoresMouseEvents = true
        hasShadow = false
        isReleasedWhenClosed = false

        let item = AVPlayerItem(url: videoURL)
        let queuePlayer = AVQueuePlayer()
        queuePlayer.isMuted = muted
        queuePlayer.volume = volume
        looper = AVPlayerLooper(player: queuePlayer, templateItem: item)
        player = queuePlayer

        let containerView = NSView(frame: screen.frame)
        containerView.wantsLayer = true
        let layer = AVPlayerLayer(player: queuePlayer)
        layer.videoGravity = gravity
        layer.frame = containerView.bounds
        layer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
        containerView.layer?.addSublayer(layer)
        playerLayer = layer
        contentView = containerView

        setFrame(screen.frame, display: true)
        orderFront(nil)
        queuePlayer.play()
    }

    func setAudio(muted: Bool, volume: Float) {
        player?.isMuted = muted
        player?.volume = volume
    }

    func setGravity(_ gravity: AVLayerVideoGravity) {
        playerLayer?.videoGravity = gravity
    }

    override func close() {
        player?.pause()
        looper = nil
        player = nil
        playerLayer = nil
        super.close()
    }
}
