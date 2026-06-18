# Wallpaper

A native macOS wallpaper manager built with **Swift + SwiftUI** and **zero third-party dependencies**.
Manage local image/video wallpapers, browse several online sources (Wallhaven · Pixiv · Yande.re · Konachan), with multi-display support and a menu-bar presence.

[简体中文](README.md) | English

![platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue)
![swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)
![ui](https://img.shields.io/badge/UI-SwiftUI-1575F9)
![deps](https://img.shields.io/badge/dependencies-0-success)
![license](https://img.shields.io/badge/license-MIT-green)

<p align="center">
  <img src="Assets/AppIcon-color.png" alt="App icon" width="150" align="middle">
  &nbsp;&nbsp;&nbsp;
  <img src="docs/screenshot.png" alt="App screenshot" width="600" align="middle">
</p>

## Features

- **Local library**: Import images, videos, or whole folders (recursive scan), browse as a thumbnail grid, favorite, set as wallpaper / reveal in Finder / remove. Imported files are **copied** into the library folder and renamed with a dated scheme (e.g. `20260611-001-a3f2.jpg`), so the originals are safe to delete; online downloads are archived the same way.
- **Video wallpaper**: Loops mp4 / mov / m4v as a live wallpaper (placed below the desktop icons), automatically restored after relaunch. Muted by default; sound and volume are per-wallpaper toggles in the detail panel (applied live).
- **Detail panel**: Click a wallpaper in the library to slide out a large preview, resolution / size / duration, a link back to its source page, and per-wallpaper display mode (fill / fit / stretch / center) and video sound. Changes to the active wallpaper apply instantly.
- **Online sources**:
  - **Wallhaven** (wallhaven.cc): keyword search; sort by Toplist (with a **Daily / Weekly / Monthly** time range), **Most Favorited**, Most Viewed, Latest, or Random; paged loading. NSFW content requires your free wallhaven API key (entered in the toolbar).
  - **Pixiv rankings** (pixiv.net): browse Daily / Weekly / Monthly / Rookie rankings without signing in (all-ages); enable R-18 to browse R-18 rankings, which requires the `PHPSESSID` cookie of an account with R-18 viewing enabled (stored locally only). Hotlink-protected originals are downloaded automatically.
  - **Yande.re / Konachan** (no login): high-resolution anime wallpaper boards, tag search, score / latest sorting, and an R-18 rating toggle (all-ages by default).
  - **Auto-translated search**: type your query in any language (e.g. Chinese) and it is auto-translated to English tags before searching (these sources are tag-based and mostly English), improving hit rate; the resolved term is shown.
  - Every result can be downloaded to the library or set as wallpaper in one click, with a minimum-resolution filter.
- **Multi-display**: target "All Displays" or a single screen from the toolbar; adapts automatically when displays are plugged or unplugged.
- **Menu bar**: stays resident after the main window is closed, with quick actions like random shuffle and stop video wallpaper.
- **Settings** (⌘, or the menu-bar "Settings…"): switch **language** (中文 / English) and **appearance** (Light / Dark / Follow System) in-app, both applied instantly; the menu-bar icon can be hidden.

> ⚠️ The Pixiv / Yande.re / Konachan / Wallhaven sources expose an R-18 (NSFW) toggle. This app is only a **client** for those sites and ships no adult content of its own; enabling it is your choice and subject to your local laws and each site's terms.

## Build & Run

Requires **macOS 14+** and Xcode (or the Xcode Command Line Tools).

```bash
# Run for development
swift run

# Build a double-clickable .app (output: build/Wallpaper.app)
./build_app.sh

# Build a DMG installer (output: build/Wallpaper-1.0.dmg)
./make_dmg.sh
```

Install: open the DMG and drag Wallpaper into Applications; add it under System Settings → General → Login Items to launch at startup.

## Project Structure

```
Sources/WallpaperManager/
├── WallpaperManagerApp.swift   # App entry: main window + Settings + MenuBarExtra
├── Models.swift                # Wallpaper item data model
├── LibraryStore.swift          # Library: JSON persistence, import, favorites, delete, archiving
├── WallpaperEngine.swift       # Engine: image wallpaper (NSWorkspace) + video window (AVPlayerLooper)
├── ThumbnailLoader.swift       # QuickLook thumbnails (image/video, cached)
├── RemoteImageView.swift       # Remote image view with custom headers (downsampled + cached)
├── WallhavenAPI.swift          # wallhaven.cc search & download
├── PixivAPI.swift              # pixiv.net rankings & original download (Referer hotlink handling)
├── MoebooruAPI.swift           # yande.re / konachan client (tag search, rankings, autocomplete)
├── TranslationService.swift    # Auto-translate search terms (e.g. Chinese → English tags)
├── ResolutionFilter.swift      # Minimum-resolution filter
├── SourceLogos.swift           # Monochrome source logos (template images, theme-tinted)
├── Appearance.swift            # Light / Dark / Follow System appearance
├── Localization.swift          # In-app 中文 / English switch
├── Resources/                  # Source logos
└── Views/
    ├── MainWindowView.swift        # Main window: sidebar + toolbar
    ├── LibraryGridView.swift       # Local wallpaper grid
    ├── WallpaperInspectorView.swift# Right-side detail / settings panel
    ├── OnlineBrowserView.swift     # Wallhaven browse/download
    ├── PixivBrowserView.swift      # Pixiv rankings browse/download
    ├── MoebooruBrowserView.swift   # Yande.re / Konachan browse/download
    ├── SettingsView.swift          # Settings (language / appearance / menu bar)
    ├── MenuBarView.swift           # Menu-bar menu
    └── ErrorBanner.swift           # Top error banner
```

## How It Works

- **Video wallpaper**: a borderless window whose level is set to `CGWindowLevelForKey(.desktopWindow)` sits just below the desktop icons, hosting an `AVPlayerLayer` + `AVPlayerLooper` for seamless looping. This is the same approach apps like Plash use, requiring no special permissions.
- **Image wallpaper**: `NSWorkspace.setDesktopImageURL(_:for:options:)`, set per screen.
- **Data storage**: the library index and online downloads live in `~/Library/Application Support/WallpaperManager/`. API keys, the Pixiv cookie, etc. are stored only in local `UserDefaults` and are **never committed**.

## Known Limitations

- Image wallpaper only applies to the **current Space** — a macOS API limitation (the system Settings wallpaper pane behaves the same).
- The video wallpaper is hosted by this app's window, so it **disappears when the app quits** (and is restored on next launch).
- Ad-hoc signing is for local use only; distributing to others requires an Apple Developer certificate plus notarization.
- Auto-translated search uses a free public translation endpoint; on the rare failure it falls back to searching the original term.

## License

[MIT](LICENSE) © 2026 Forya-1220
