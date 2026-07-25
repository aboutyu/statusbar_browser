//
//  AppDelegate.swift
//  MenubarBrowser
//
//  메뉴바 아이콘(NSStatusItem)과 팝오버를 직접 관리한다.
//  SwiftUI의 MenuBarExtra에는 팝오버를 코드로 열고 닫는 공개 API가 없어서,
//  전역 단축키(⌃⌥⌘B)로 팝오버를 토글하려면 NSStatusItem + NSWindow 조합이 필요하다.
//
//  팝오버는 NSPopover가 아니라 직접 관리하는 borderless NSWindow(PopoverWindow)로 구현한다.
//  NSPopover는 .transient로 닫힐 때 내부 창을 실제로 없애버려서, 그 안의 WKWebView가 순간
//  "어떤 창에도 속하지 않은" 상태가 되고 유튜브 같은 사이트는 이를 페이지가 사라진 것으로
//  인식해 재생 중이던 오디오/영상을 스스로 멈춘다. 직접 만든 창은 닫을 때 close()가 아니라
//  orderOut()으로 화면에서만 숨기고 창 자체(및 그 안의 WKWebView)는 계속 살아있게 해서,
//  팝오버를 닫아도(=메뉴바 아이콘 밖 클릭) 재생 중이던 미디어가 끊기지 않는다.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let resizePopoverBy = Notification.Name("resizePopoverBy")
    static let resizePopoverDragEnded = Notification.Name("resizePopoverDragEnded")
    static let resetPopoverSize = Notification.Name("resetPopoverSize")
    static let openAboutWindow = Notification.Name("openAboutWindow")
    static let openSettingsWindow = Notification.Name("openSettingsWindow")
}

// 설정 화면의 "화면모드"(다크/라이트/시스템 설정) 값. UserDefaults 키 "appearanceMode"에
// 문자열로 저장되며, SettingsPopMenu의 세그먼트 Picker와 태그 문자열을 공유한다.
enum AppearanceMode: String, Equatable {
    case dark, light, system

    var nsAppearance: NSAppearance? {
        switch self {
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        case .system: return nil // nil이면 시스템 설정을 그대로 따라간다
        }
    }
}

// 화면(visibleFrame) 크기를 기준으로 한 팝오버 min/시작 크기. max 제약은 없음.
// 세로가 기준값이고, 가로는 항상 세로에서 파생된다.
enum PopoverSizing {
    static func minSize(forScreen screenFrame: NSRect) -> NSSize {
        let height = screenFrame.height / 3
        return NSSize(width: height, height: height) // 가로 = 세로
    }

    static func initialSize(forScreen screenFrame: NSRect) -> NSSize {
        let height = screenFrame.height / 2
        let width = height / 2
        return NSSize(width: width, height: height)
    }
}

// 메뉴바 팝오버를 흉내내는 borderless 창. 닫을 때도 orderOut()만 쓰고 절대 close()하지
// 않아서, 이 창의 contentViewController(=WKWebView를 품은 SwiftUI 트리)가 창에서
// 떨어져 나가는 일이 없다 — 이게 재생 중 오디오가 끊기지 않게 하는 핵심이다.
private final class PopoverWindow: NSWindow {
    convenience init() {
        self.init(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 600),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // .normal 레벨 + canJoinAllSpaces 조합은 애플 문서상 보조 패널류에만 쓰라고 되어
        // 있는 조합이라(일반 창에 쓰면 스페이스별로 동작이 들쭉날쭉해질 수 있음) 실제로도
        // 미션 컨트롤 화면마다 다르게 동작하고 팝오버를 닫기만 해도 재생이 멈추는 등 오히려
        // 더 불안정해져서 되돌린다. .popUpMenu가 "바깥 클릭으로 닫기" 시나리오에서는
        // 확실히 동작했던 원래 설정.
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    // borderless 창은 기본적으로 key window가 되지 못해 URL 입력창 등이 포커스를 못 받는다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popoverWindow = PopoverWindow()
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?

    // About/설정 창은 SwiftUI Window scene(자동 복원/자동 오픈 위험이 있음) 대신
    // 팝오버와 동일하게 AppKit에서 직접 열고 닫는다 — 메뉴 클릭 시에만 생성/표시된다.
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shortcutEnabled = true
    private var appearanceMode: AppearanceMode = .system

    private static let hotKeyID = EventHotKeyID(signature: fourCharCode("BarB"), id: 1)
    private static let appearanceModeKey = "appearanceMode"

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: [
            "shortcutEnabled": true,
            Self.appearanceModeKey: AppearanceMode.system.rawValue
        ])
        shortcutEnabled = UserDefaults.standard.bool(forKey: "shortcutEnabled")
        appearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? "") ?? .system
        NSApp.appearance = appearanceMode.nsAppearance

        setupStatusItem()
        setupPopoverWindow()

        if shortcutEnabled {
            registerGlobalHotKey()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDefaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResizePopover(_:)),
            name: .resizePopoverBy, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResizeDragEnded),
            name: .resizePopoverDragEnded, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleResetPopoverSize),
            name: .resetPopoverSize, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenAbout),
            name: .openAboutWindow, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOpenSettings),
            name: .openSettingsWindow, object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        unregisterGlobalHotKey()
    }

    // MARK: - Status item / popover

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(named: "bar_icon")
            image?.isTemplate = true
            button.image = image
            button.action = #selector(togglePopover(_:))
            button.target = self
        }
        statusItem = item
    }

    private func currentScreenFrame() -> NSRect {
        statusItem?.button?.window?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    private func setupPopoverWindow() {
        let screenFrame = currentScreenFrame()

        let baseSize: NSSize
        if let savedWidth = UserDefaults.standard.object(forKey: Self.lastWidthKey) as? Double,
           let savedHeight = UserDefaults.standard.object(forKey: Self.lastHeightKey) as? Double {
            // 🔁 마지막으로 맞춘 사이즈 복원
            baseSize = NSSize(width: savedWidth, height: savedHeight)
        } else {
            // 시작 가로(세로의 1/2)가 min 가로(세로의 1/3)보다 작을 수 있어 clamp로 보정한다.
            baseSize = PopoverSizing.initialSize(forScreen: screenFrame)
        }

        popoverWindow.setContentSize(clampedSize(baseSize))
        popoverWindow.contentViewController = NSHostingController(
            rootView: PopoverView()
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )

        // orderOut()은 occlusion state를 "안 보임"으로 바꿔서 WKWebView가 재생 중이던
        // 미디어를 스스로 멈춰버린다(occlusion 변화 = WebKit이 페이지를 백그라운드로 인식).
        // 그래서 창을 아예 닫지 않고 항상 화면에 떠 있는 상태로 유지하되, alpha 0 +
        // ignoresMouseEvents로 "안 보이고 클릭도 안 되는" 상태만 흉내낸다.
        popoverWindow.alphaValue = 0
        popoverWindow.ignoresMouseEvents = true
        popoverWindow.orderFrontRegardless()
    }

    private var isPopoverVisible: Bool { popoverWindow.alphaValue > 0 }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if isPopoverVisible {
            hidePopoverWindow()
        } else {
            positionPopoverWindow(relativeTo: button)
            NSApp.activate(ignoringOtherApps: true)
            popoverWindow.ignoresMouseEvents = false
            popoverWindow.alphaValue = 1
            popoverWindow.makeKeyAndOrderFront(nil)
            startOutsideInteractionMonitors()
        }
    }

    private func hidePopoverWindow() {
        popoverWindow.alphaValue = 0
        popoverWindow.ignoresMouseEvents = true
        stopOutsideInteractionMonitors()
    }

    // 메뉴바 아이콘 기준으로 팝오버가 놓일 화면 좌표(가로 중앙 정렬, 화면 밖으로 안 나가게 clamp).
    private func popoverFrame(size: NSSize, relativeTo button: NSStatusBarButton) -> NSRect? {
        guard let buttonWindow = button.window else { return nil }
        let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? currentScreenFrame()

        let x = min(max(buttonFrameOnScreen.midX - size.width / 2, screenFrame.minX), screenFrame.maxX - size.width)
        let y = buttonFrameOnScreen.minY - size.height
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func positionPopoverWindow(relativeTo button: NSStatusBarButton) {
        guard let frame = popoverFrame(size: popoverWindow.frame.size, relativeTo: button) else { return }
        popoverWindow.setFrameOrigin(frame.origin)
    }

    // 바깥 클릭/Esc로 팝오버를 닫는 동작(기존 NSPopover.behavior = .transient를 대체)
    private func startOutsideInteractionMonitors() {
        stopOutsideInteractionMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopoverWindow()
        }
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event } // esc
            self?.hidePopoverWindow()
            return nil
        }
    }

    private func stopOutsideInteractionMonitors() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
        if let escKeyMonitor {
            NSEvent.removeMonitor(escKeyMonitor)
            self.escKeyMonitor = nil
        }
    }

    // MARK: - Resize (drag handle in PopoverView)

    private static let lastWidthKey = "lastPopoverWidth"
    private static let lastHeightKey = "lastPopoverHeight"

    @objc private func handleResizePopover(_ notification: Notification) {
        guard let delta = notification.object as? CGSize else { return }
        // 드래그 중엔 그림자 재계산 + UserDefaults 저장 비용을 없애야 마우스 속도를 따라간다.
        // (둘 다 매 프레임 하기엔 무거워서, 그림자는 드래그 동안만 끄고 저장은 드래그가 끝난
        // 뒤 handleResizeDragEnded에서 한 번만 한다)
        popoverWindow.hasShadow = false
        let current = popoverWindow.frame.size
        let proposed = NSSize(width: current.width + delta.width, height: current.height + delta.height)
        setPopoverWindowSize(clampedSize(proposed), animate: false, display: false)
    }

    @objc private func handleResizeDragEnded() {
        popoverWindow.hasShadow = true
        popoverWindow.displayIfNeeded()
        persistPopoverSize(popoverWindow.frame.size)
    }

    @objc private func handleResetPopoverSize() {
        let defaultSize = clampedSize(PopoverSizing.initialSize(forScreen: currentScreenFrame()))

        // 크기뿐 아니라 메뉴바 아이콘 기준 위치도 다시 맞춰야 "초기화"답게 보인다.
        // (가로 리사이즈 핸들이 왼쪽을 고정하고 자라기 때문에, 여러 번 늘렸다 줄이면
        // 아이콘 중앙에서 한쪽으로 치우친 채로 크기만 바뀌어 어색해 보일 수 있었음)
        if let button = statusItem?.button, let frame = popoverFrame(size: defaultSize, relativeTo: button) {
            popoverWindow.setFrame(frame, display: true, animate: true)
        } else {
            setPopoverWindowSize(defaultSize, animate: true)
        }

        persistPopoverSize(defaultSize)
    }

    // 위쪽(메뉴바 아이콘 쪽) 가장자리는 고정하고 아래/오른쪽으로만 자라도록 origin을 보정한다.
    private func setPopoverWindowSize(_ size: NSSize, animate: Bool, display: Bool = true) {
        var frame = popoverWindow.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        popoverWindow.setFrame(frame, display: display, animate: animate)
    }

    private func persistPopoverSize(_ size: NSSize) {
        // 💾 다음 실행 때 복원할 수 있도록 저장
        UserDefaults.standard.set(Double(size.width), forKey: Self.lastWidthKey)
        UserDefaults.standard.set(Double(size.height), forKey: Self.lastHeightKey)
    }

    private func clampedSize(_ proposed: NSSize) -> NSSize {
        let minSize = PopoverSizing.minSize(forScreen: currentScreenFrame())
        return NSSize(width: max(proposed.width, minSize.width), height: max(proposed.height, minSize.height))
    }

    // MARK: - About / Settings windows

    @objc private func handleOpenAbout() {
        closePopoverIfShown()
        if aboutWindow == nil {
            aboutWindow = makeUtilityWindow(title: "바브라우저에 관하여", rootView: AboutAppMenu())
        }
        present(aboutWindow)
    }

    @objc private func handleOpenSettings() {
        closePopoverIfShown()
        if settingsWindow == nil {
            settingsWindow = makeUtilityWindow(title: "환경설정", rootView: SettingsPopMenu())
        }
        present(settingsWindow)
    }

    private func makeUtilityWindow(title: String, rootView: some View) -> NSWindow {
        let hostingController = NSHostingController(rootView: rootView)
        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        return window
    }

    private func present(_ window: NSWindow?) {
        guard let window else { return }
        NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func closePopoverIfShown() {
        if isPopoverVisible {
            hidePopoverWindow()
        }
    }

    // MARK: - Settings sync

    @objc private func handleDefaultsChanged() {
        let newShortcutEnabled = UserDefaults.standard.bool(forKey: "shortcutEnabled")
        if newShortcutEnabled != shortcutEnabled {
            shortcutEnabled = newShortcutEnabled
            if newShortcutEnabled {
                registerGlobalHotKey()
            } else {
                unregisterGlobalHotKey()
            }
        }

        let newAppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: Self.appearanceModeKey) ?? "") ?? .system
        if newAppearanceMode != appearanceMode {
            appearanceMode = newAppearanceMode
            NSApp.appearance = appearanceMode.nsAppearance
        }
    }

    // MARK: - Global hotkey (⌃⌥⌘B)

    private func registerGlobalHotKey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: OSType(kEventHotKeyPressed)
        )

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let userData, let eventRef else { return OSStatus(eventNotHandledErr) }

                var pressedID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &pressedID
                )
                guard status == noErr, pressedID.id == AppDelegate.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }

                let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    delegate.togglePopover(nil)
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &hotKeyHandler
        )

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            modifiers,
            AppDelegate.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterGlobalHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRef = nil

        if let hotKeyHandler {
            RemoveEventHandler(hotKeyHandler)
        }
        hotKeyHandler = nil
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else { return }
        if closedWindow === aboutWindow { aboutWindow = nil }
        if closedWindow === settingsWindow { settingsWindow = nil }

        if aboutWindow == nil && settingsWindow == nil {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value)
    }
    return result
}
