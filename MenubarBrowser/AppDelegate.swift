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
internal import WebKit

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
        // 최초 실행 시 기본 크기: 가로는 기존 기준값의 1.5배, 세로는 2배.
        let baseHeight = screenFrame.height / 2
        let baseWidth = baseHeight / 2
        return NSSize(width: baseWidth * 1.5, height: baseHeight * 2)
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
        // 더 불안정해져서 시도했었다.
        // .popUpMenu 레벨도 마찬가지로 문제였다: macOS는 .popUpMenu 레벨 창을 "진짜 팝업
        // 메뉴"로 취급해서, Space를 전환(트랙패드 스와이프/Mission Control)하는 동안 이 창을
        // canJoinAllSpaces와 무관하게 강제로 닫으려는 듯한 동작을 한다 — 숨겨놓은(alpha 0)
        // 상태에서도 오디오가 끊기고, 전환 애니메이션 중 창이 잠깐 보였다 사라지는 깜빡임까지
        // 발생했다. .statusBar 레벨은 실제 메뉴바/상태바류 UI가 쓰는 레벨로, canJoinAllSpaces와
        // 함께 쓰는 것이 애플 문서상으로도 지원되는 조합이라 이걸로 바꾼다. 바깥 클릭으로
        // 닫는 동작은 window level이 아니라 startOutsideInteractionMonitors()의 전역
        // NSEvent 모니터로 직접 구현되어 있어서, 레벨을 바꿔도 영향받지 않는다.
        level = .statusBar
        collectionBehavior = Self.hiddenCollectionBehavior
        isMovable = false
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
    }

    // 숨김 상태: 모든 Space에 걸쳐 있는 창. 어느 Space에서 열든 그 자리에서 바로 보여줄 수 있다.
    // .stationary: Exposé/Spaces 전환 시 다른 공간으로 "옮겨지는" 창이 아니라 항상 제자리에
    // 고정된 창으로 취급되도록 한다. canJoinAllSpaces + stationary는 애플이 패널류 창에
    // 공식적으로 지원한다고 밝힌 조합이다.
    static let hiddenCollectionBehavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
    // 열린 상태: 연 Space에만 속하는 창. 다른 Space로 스와이프해도 따라오지 않고 원래 Space에
    // 열린 채로 남는다(OneDrive 메뉴바 팝오버와 같은 동작). canJoinAllSpaces를 빼는 순간 창은
    // 현재 활성 Space에 소속된다.
    static let shownCollectionBehavior: NSWindow.CollectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]

    // borderless 창은 기본적으로 key window가 되지 못해 URL 입력창 등이 포커스를 못 받는다.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // 웹페이지가 처리하지 않은 Esc만 여기까지 올라온다(WKWebView는 처리 안 된 키 이벤트를
    // responder chain으로 다시 흘려보냄). 페이지가 Esc를 쓰는 경우(모달 닫기 등)를 막지 않고
    // 남는 Esc로만 팝오버를 닫기 위해 로컬 모니터 대신 여기서 처리한다.
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape), let onEscape {
            onEscape()
        } else {
            super.keyDown(with: event)
        }
    }

    override func cancelOperation(_ sender: Any?) {
        if let onEscape {
            onEscape()
        } else {
            super.cancelOperation(sender)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popoverWindow = PopoverWindow()
    private var outsideClickMonitor: Any?
    private var escKeyMonitor: Any?
    // 팝오버를 열기 직전에 활성 상태였던 앱. Esc/단축키/아이콘 클릭으로 닫을 때 포커스를
    // 이 앱에 돌려줘야, 숨겨진(alpha 0) 팝오버 창이 계속 key window로 남아 키 입력을
    // 가로채는 일이 없다.
    private var previousActiveApp: NSRunningApplication?

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
        // ⌘Tab 등 키보드로 다른 앱에 넘어가면 바깥 클릭 모니터가 발동하지 않으므로,
        // 앱이 비활성화되는 시점에도 팝오버를 닫는다(단, Space 전환으로 인한 비활성화는 제외).
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleAppResignActive),
            name: NSApplication.didResignActiveNotification, object: nil
        )
        // 모니터 연결/해제, 해상도 변경 시 숨겨둔 창이 다른 화면 위에 걸리지 않게 다시 치운다.
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleOcclusionChange),
            name: NSWindow.didChangeOcclusionStateNotification, object: popoverWindow
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

        let hostingController = NSHostingController(
            rootView: PopoverView()
                .background(Color(NSColor.windowBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        )
        // 창 크기(min/max 포함)는 전부 AppDelegate가 clampedSize로 관리한다. SwiftUI가 별도
        // 기준으로 창 크기 제약을 덧씌우지 않게 한다.
        hostingController.sizingOptions = []
        popoverWindow.contentViewController = hostingController
        popoverWindow.setContentSize(clampedSize(baseSize))
        popoverWindow.onEscape = { [weak self] in
            self?.hidePopoverWindow(restoreFocus: true)
        }

        // orderOut()은 occlusion state를 "안 보임"으로 바꿔서 WKWebView가 재생 중이던
        // 미디어를 스스로 멈춰버린다(occlusion 변화 = WebKit이 페이지를 백그라운드로 인식).
        // 그래서 창을 아예 닫지 않고 항상 화면에 떠 있는 상태로 유지하되, alpha 0 +
        // ignoresMouseEvents로 "안 보이고 클릭도 안 되는" 상태만 흉내낸다.
        popoverWindow.alphaValue = 0
        popoverWindow.ignoresMouseEvents = true
        parkHiddenPopoverWindow()
        popoverWindow.orderFrontRegardless()
    }

    // Space 전환(세 손가락 스와이프/Mission Control) 애니메이션은 창의 alphaValue를 무시하고
    // 그려서, alpha 0으로 숨겨둔 팝오버가 전환할 때마다 잠깐 나타났다 사라진다(레벨과 무관).
    // 그래서 숨김 상태에서는 창을 화면 바깥으로 치워두되, occlusion이 "안 보임"으로 바뀌어
    // 미디어가 멈추지 않도록 모서리 1pt만 화면에 걸쳐둔다. 크기는 그대로라 웹페이지 레이아웃도
    // 바뀌지 않는다. 다음에 열 때 positionPopoverWindow가 원래 자리로 되돌린다.
    private func parkHiddenPopoverWindow() {
        guard let screen = statusItem?.button?.window?.screen ?? NSScreen.main else { return }
        let size = popoverWindow.frame.size
        let screenFrame = screen.frame
        let sliver: CGFloat = 1
        let candidates = [
            NSPoint(x: screenFrame.minX - size.width + sliver, y: screenFrame.minY - size.height + sliver), // 왼쪽 아래
            NSPoint(x: screenFrame.maxX - sliver, y: screenFrame.minY - size.height + sliver),              // 오른쪽 아래
            NSPoint(x: screenFrame.minX - size.width + sliver, y: screenFrame.maxY - sliver),               // 왼쪽 위
            NSPoint(x: screenFrame.maxX - sliver, y: screenFrame.maxY - sliver)                             // 오른쪽 위
        ]
        // 바깥으로 밀어낸 부분이 옆에 붙은 다른 모니터 위에 놓이면 거기서 다시 깜빡이므로 피한다.
        let origin = candidates.first { origin in
            let rect = NSRect(origin: origin, size: size)
            return NSScreen.screens.allSatisfy { $0 == screen || !$0.frame.intersects(rect) }
        } ?? candidates[0]
        popoverWindow.setFrameOrigin(origin)
    }

    @objc private func handleScreenParametersChanged() {
        if !isPopoverVisible {
            parkHiddenPopoverWindow()
        }
    }

    private var isPopoverVisible: Bool { popoverWindow.alphaValue > 0 }

    @objc private func togglePopover(_ sender: Any?) {
        if isPopoverVisible && popoverWindow.isOnActiveSpace {
            hidePopoverWindow(restoreFocus: true)
        } else {
            // 다른 Space에 열어둔 채로 여기서 아이콘/단축키를 누른 경우엔 닫는 대신 이 Space로 옮겨 연다.
            hidePopoverWindow()
            showPopoverWindow()
        }
    }

    private func showPopoverWindow() {
        guard let button = statusItem?.button else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        previousActiveApp = frontmost == NSRunningApplication.current ? nil : frontmost

        positionPopoverWindow(relativeTo: button)
        // 이 시점의 활성 Space에 창을 묶는다.
        popoverWindow.collectionBehavior = PopoverWindow.shownCollectionBehavior
        NSApp.activate(ignoringOtherApps: true)
        popoverWindow.ignoresMouseEvents = false
        popoverWindow.alphaValue = 1
        popoverWindow.makeKeyAndOrderFront(nil)
        startOutsideInteractionMonitors()
    }

    // restoreFocus: 우리 앱이 여전히 활성 상태로 남는 닫기(Esc/단축키/아이콘 클릭)에서는 true.
    // 바깥 클릭이나 앱 비활성화로 닫힐 때는 이미 다른 앱이 포커스를 가져가고 있으므로 false —
    // 여기서 이전 앱을 활성화하면 사용자가 방금 클릭한 앱과 포커스를 다투게 된다.
    private func hidePopoverWindow(restoreFocus: Bool = false) {
        guard isPopoverVisible else { return }
        popoverWindow.alphaValue = 0
        popoverWindow.ignoresMouseEvents = true
        stopOutsideInteractionMonitors()
        popoverWindow.makeFirstResponder(nil)
        parkHiddenPopoverWindow()
        popoverWindow.collectionBehavior = PopoverWindow.hiddenCollectionBehavior

        guard restoreFocus, NSApp.isActive else { return }
        // orderOut()/NSApp.hide()는 창을 화면에서 내려 미디어 재생을 멈추므로 쓰지 않고,
        // key 상태만 다른 곳으로 넘긴다.
        if let auxWindow = [settingsWindow, aboutWindow].compactMap({ $0 }).first(where: { $0.isVisible }) {
            auxWindow.makeKeyAndOrderFront(nil)
        } else if let previousActiveApp, !previousActiveApp.isTerminated {
            previousActiveApp.activate()
        } else {
            NSApp.deactivate()
        }
        previousActiveApp = nil
    }

    // Space 스와이프로도 앱이 비활성화되는데, 이때는 팝오버를 원래 Space에 열어둔 채로 둬야 한다.
    // 비활성화 알림이 Space 전환 완료보다 먼저 올 수 있어서 잠시 기다린 뒤, 팝오버가 여전히 지금
    // 보고 있는 Space에 있을 때(=같은 Space에서 ⌘Tab 등으로 다른 앱으로 간 경우)만 닫는다.
    // 다른 Space에서 아무 곳이나 클릭하면 전역 클릭 모니터가 닫아준다.
    @objc private func handleAppResignActive() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !NSApp.isActive, self.popoverWindow.isOnActiveSpace else { return }
            self.hidePopoverWindow()
        }
    }

    // 메뉴바 아이콘 기준으로 팝오버가 놓일 화면 좌표(가로 중앙 정렬, 화면 밖으로 안 나가게 clamp).
    private static let menuBarGap: CGFloat = 5

    private func popoverFrame(size: NSSize, relativeTo button: NSStatusBarButton) -> NSRect? {
        guard let buttonWindow = button.window else { return nil }
        let buttonFrameOnScreen = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screenFrame = buttonWindow.screen?.visibleFrame ?? currentScreenFrame()

        let x = max(min(buttonFrameOnScreen.midX - size.width / 2, screenFrame.maxX - size.width), screenFrame.minX)
        // 메뉴바(=visibleFrame 위쪽 경계)와 버튼 아래쪽 중 더 낮은 곳에서 menuBarGap만큼 띄워,
        // 팝오버 상단이 메뉴바를 덮지 않게 한다.
        let top = min(buttonFrameOnScreen.minY, screenFrame.maxY) - Self.menuBarGap
        let height = min(size.height, top - screenFrame.minY)
        return NSRect(x: x, y: top - height, width: size.width, height: height)
    }

    private func positionPopoverWindow(relativeTo button: NSStatusBarButton) {
        // 다른(더 작은) 모니터에서 열리거나 해상도가 바뀌었을 수 있으니 현재 화면 기준으로 다시 clamp한다.
        guard let frame = popoverFrame(size: clampedSize(popoverWindow.frame.size), relativeTo: button) else { return }
        popoverWindow.setFrame(frame, display: false)
    }

    // 바깥 클릭/Esc로 팝오버를 닫는 동작(기존 NSPopover.behavior = .transient를 대체)
    private func startOutsideInteractionMonitors() {
        stopOutsideInteractionMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePopoverWindow()
        }
        // 웹페이지에 포커스가 있을 때의 Esc는 페이지에 먼저 넘기고(처리되지 않으면
        // PopoverWindow.keyDown에서 닫힘), URL 입력창 등 그 외의 경우에만 여기서 바로 닫는다.
        escKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self,
                  event.keyCode == UInt16(kVK_Escape),
                  event.window === self.popoverWindow else { return event }
            if self.isWebViewFocused {
                return event
            }
            self.hidePopoverWindow(restoreFocus: true)
            return nil
        }
    }

    private var isWebViewFocused: Bool {
        var view = popoverWindow.firstResponder as? NSView
        while let current = view {
            if current is WKWebView { return true }
            view = current.superview
        }
        return false
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
        if !isPopoverVisible {
            // 설정 창에서 누르는 경우 팝오버는 숨겨진 상태 — 크기만 바꾸고 계속 화면 밖에 둔다.
            // (위치는 다음에 열 때 positionPopoverWindow가 아이콘 기준으로 맞춘다)
            popoverWindow.setContentSize(defaultSize)
            parkHiddenPopoverWindow()
        } else if let button = statusItem?.button, let frame = popoverFrame(size: defaultSize, relativeTo: button) {
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

    // min은 화면 기준 비율, max는 화면(메뉴바 아래 visibleFrame) 크기 — 창이 화면 밖으로
    // 나가서 아래쪽 리사이즈 핸들에 손이 닿지 않게 되는 일을 막는다.
    private func clampedSize(_ proposed: NSSize) -> NSSize {
        let screenFrame = currentScreenFrame()
        let minSize = PopoverSizing.minSize(forScreen: screenFrame)
        let maxSize = NSSize(
            width: max(screenFrame.width, minSize.width),
            height: max(screenFrame.height - Self.menuBarGap, minSize.height)
        )
        return NSSize(
            width: min(max(proposed.width, minSize.width), maxSize.width),
            height: min(max(proposed.height, minSize.height), maxSize.height)
        )
    }

    // MARK: - About / Settings windows

    @objc private func handleOpenAbout() {
        hidePopoverWindow()
        if aboutWindow == nil {
            aboutWindow = makeUtilityWindow(title: "바브라우저에 관하여", rootView: AboutAppMenu())
        }
        present(aboutWindow)
    }

    @objc private func handleOpenSettings() {
        hidePopoverWindow()
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

    // Space 스와이프 등으로 창이 잠깐 가려졌다가 다시 보이게 될 때 호출된다. 그 사이 WebKit이
    // 재생 중이던 미디어를 스스로 멈췄을 수 있어 .resumeMediaIfNeeded를 post해 WebView가
    // 재생 의도가 있던 <video>/<audio>를 다시 play()하도록 한다.
    @objc private func handleOcclusionChange() {
        guard isPopoverVisible, popoverWindow.occlusionState.contains(.visible) else { return }
        NotificationCenter.default.post(name: .resumeMediaIfNeeded, object: nil)
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

        if hotKeyHandler == nil {
            installHotKeyHandler()
        }

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        let status = RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            modifiers,
            AppDelegate.hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            // 다른 앱이 같은 조합을 이미 쓰는 경우 등. 핸들러만 남겨두지 않도록 정리한다.
            NSLog("[BarBrowser] 전역 단축키 등록 실패: \(status)")
            unregisterGlobalHotKey()
        }
    }

    private func installHotKeyHandler() {
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
