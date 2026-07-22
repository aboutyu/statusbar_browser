# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

바브라우저 (Bar Browser) is a macOS menu bar mini web browser built with SwiftUI + WebKit. It lives entirely in the menu bar (no Dock icon, `LSUIElement = YES`) and shows a `WKWebView` in a popover, restoring the last visited URL on launch.
Product name: MenubarBrowser (target), bundle id `com.yutaehun.MenubarBrowser`.

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

- **AppDelegate.swift** — owns the menu bar presence directly via `NSStatusItem` + `NSPopover` (not SwiftUI's
  `MenuBarExtra`), because `MenuBarExtra` has no public API to open/close its dropdown programmatically. This
  is what lets the global keyboard shortcut (⌃⌥⌘B, Carbon `RegisterEventHotKey`) toggle the popover. Also
  observes `UserDefaults.didChangeNotification` to re-register/unregister the hotkey when the "단축키" toggle
  in Settings flips (backed by `@AppStorage("shortcutEnabled")`), and listens for `.closePopover` (posted by
  `PopoverView` before opening the About/Settings windows) to close the popover via the public `NSPopover`
  API rather than reaching into `NSApp.keyWindow`.
- **MenubarBrowserApp.swift** — `@main` entry point. Wires `AppDelegate` in via
  `@NSApplicationDelegateAdaptor`. Declares only the "About" `Window("about_window")` and "Settings"
  `Window("settings_window")` scenes — the menu bar icon/popover is NOT a scene here, it's created in
  `AppDelegate.applicationDidFinishLaunching`. Also sets up a SwiftData `ModelContainer` for `Item` (currently
  unused by app logic — scaffold leftover). Forces `NSApp.setActivationPolicy(.accessory)` on
  about/settings-window disappear to keep the app out of the Dock except when a secondary window is focused.
  Note: `.defaultLaunchBehavior(.suppressed)` (macOS 15+) is NOT available at this project's 14.6 deployment
  target — don't add it without an `#available` guard; verified empirically that these `Window` scenes don't
  auto-open at launch on macOS 14 without it.
- **PopoverView.swift** — the menu bar popover content: back button, URL text field, gear `Menu` (설정 / 바브
  라우저에 관하여 / 종료), and the `WebView`. Uses `NotificationCenter` (not bindings/state) to communicate
  with both the single shared `WKWebView` and the `AppDelegate`: `.goBack` / `.loadURL` are posted here and
  observed by `WebView`; `.closePopover` is posted here and observed by `AppDelegate` before opening the
  About/Settings windows.
- **WebView.swift** — `NSViewRepresentable` wrapping `WKWebView`. `WebViewHolder.shared` holds a singleton
  reference to the live `WKWebView` instance so other views (menu actions, notification handlers) can drive
  it without prop drilling. Sets a custom mobile Safari user-agent so sites render their mobile layout in the
  small popover. Persists/restores the last-loaded URL via `UserDefaults` key `"lastURL"` in the
  `WKNavigationDelegate` callback.
- **SettingsPopMenu.swift** — settings window UI. "단축키" toggle is `@AppStorage("shortcutEnabled")`, which
  `AppDelegate` observes to register/unregister the global hotkey. "로그인시 실행" toggle drives
  `SMAppService.mainApp.register()/.unregister()`, re-synced from `SMAppService.mainApp.status` on
  `.onAppear` (in case the user removed it via System Settings → Login Items directly) and shows a small red
  error label if registration throws. Known SwiftUI layout gotcha: the shortcut keycap `HStack` (Image +
  Image + Image + Text nested a few levels inside `.cornerRadius`/`.overlay`) needs `.fixedSize()` right after
  the `.overlay`, or the trailing `Text("B")` silently gets clipped to zero width — confirmed by offscreen
  `ImageRenderer` reproduction, not obvious from reading the view code alone.
- **AboutAppMenu.swift** — About window; reads `CFBundleShortVersionString`/`CFBundleVersion` from
  `Bundle.main.infoDictionary` so version text stays in sync with the build settings automatically.
- **Item.swift** — SwiftData `@Model` scaffold from the default Xcode template; not currently used elsewhere.

## Notes for App Store submission work

Recent history on this branch involves App Store review/build-number bumps (see `MARKETING_VERSION` /
`CURRENT_PROJECT_VERSION` in the target build settings) and export-compliance (`ITSAppUsesNonExemptEncryption`)
handling via `INFOPLIST_KEY_*` build settings rather than `Info.plist` directly — follow that same pattern
(edit both Debug and Release configs in `project.pbxproj`) for any future compliance/metadata changes.
