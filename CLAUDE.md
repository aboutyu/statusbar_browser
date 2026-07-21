# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

바브라우저 (Bar Browser) is a macOS menu bar mini web browser built with SwiftUI + WebKit. It lives entirely
in the menu bar (no Dock icon, `LSUIElement = YES`) and shows a `WKWebView` in a popover, restoring the last
visited URL on launch. Product name: MenubarBrowser (target), bundle id `com.yutaehun.MenubarBrowser`.

## Build / run / lint

This is a standard Xcode project — there is no CLI test suite, package manager, or lint config in the repo.

- Open `MenubarBrowser.xcodeproj` in Xcode and run the `MenubarBrowser` scheme (macOS app).
- Build from the command line: `xcodebuild -project MenubarBrowser.xcodeproj -scheme MenubarBrowser -configuration Debug build`
- There are no test targets currently defined in the project.
- Deployment target: macOS 14.6 (target build settings); project-level setting shows 15.7 — the target-level
  value wins for the app.

## Architecture

The app has two Xcode build configurations (Debug/Release) with nearly identical settings in
`MenubarBrowser.xcodeproj/project.pbxproj`; `Info.plist` is auto-generated from `INFOPLIST_KEY_*` build
settings (`GENERATE_INFOPLIST_FILE = YES`) rather than hand-edited — the checked-in `Info.plist` file is
just the base (mostly empty) template. When adding Info.plist entries, add them as `INFOPLIST_KEY_*` build
settings in **both** the Debug and Release configurations, not by editing `Info.plist` directly.

Key runtime pieces, all in `MenubarBrowser/`:

- **MenubarBrowserApp.swift** — `@main` entry point. Declares three scenes: the `MenuBarExtra` (the actual
  app UI, styled `.window`), an "About" `Window("about_window")`, and a "Settings" `Window("settings_window")`.
  Also sets up a SwiftData `ModelContainer` for `Item` (currently unused by app logic — scaffold leftover).
  Forces `NSApp.setActivationPolicy(.accessory)` on popover appear / about-window disappear to keep the app
  out of the Dock except when a secondary window is focused.
- **PopoverView.swift** — the menu bar popover content: back button, URL text field, gear `Menu` (About /
  Quit — a "환경설정"/Settings menu item exists but is commented out), and the `WebView`. Uses
  `NotificationCenter` (not bindings/state) to communicate with the single shared `WKWebView`: `.goBack` and
  `.loadURL` notifications are posted here and observed by both this view and `WebView`.
- **WebView.swift** — `NSViewRepresentable` wrapping `WKWebView`. `WebViewHolder.shared` holds a singleton
  reference to the live `WKWebView` instance so other views (menu actions, notification handlers) can drive
  it without prop drilling. Sets a custom mobile Safari user-agent so sites render their mobile layout in the
  small popover. Persists/restores the last-loaded URL via `UserDefaults` key `"lastURL"` in the
  `WKNavigationDelegate` callback.
- **SettingsPopMenu.swift** — settings window UI (shortcut toggle, launch-at-login toggle). Currently UI-only:
  the `@State` toggles are not wired to `UserDefaults`, a real global shortcut, or `SMAppService` — and the
  menu entry that opens this window is commented out in `PopoverView.swift`. Treat as work-in-progress when
  asked to make settings functional.
- **AboutAppMenu.swift** — About window; reads `CFBundleShortVersionString`/`CFBundleVersion` from
  `Bundle.main.infoDictionary` so version text stays in sync with the build settings automatically.
- **Item.swift** — SwiftData `@Model` scaffold from the default Xcode template; not currently used elsewhere.

## Notes for App Store submission work

Recent history on this branch involves App Store review/build-number bumps (see `MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION` in the target build settings) and export-compliance (`ITSAppUsesNonExemptEncryption`)
handling via `INFOPLIST_KEY_*` build settings rather than `Info.plist` directly — follow that same pattern
(edit both Debug and Release configs in `project.pbxproj`) for any future compliance/metadata changes.
