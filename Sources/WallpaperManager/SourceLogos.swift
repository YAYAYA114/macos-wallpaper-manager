import AppKit

/// 在线图源的官方 logo(单色模板图,自动跟随浅色/深色模式着色)。
enum SourceLogos {
    static let wallhaven = loadTemplate(named: "wallhaven-logo", ext: "png")
    static let pixiv = loadTemplate(named: "pixiv-logo", ext: "svg")
    static let yandere = loadTemplate(named: "yandere-logo", ext: "svg")
    static let konachan = loadTemplate(named: "konachan-logo", ext: "svg")

    private static func loadTemplate(named name: String, ext: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: ext),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }
}
