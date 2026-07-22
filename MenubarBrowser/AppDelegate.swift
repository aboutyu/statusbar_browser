//
//  AppDelegate.swift
//  MenubarBrowser
//
//  메뉴바 아이콘(NSStatusItem)과 팝오버를 직접 관리한다.
//  SwiftUI의 MenuBarExtra에는 팝오버를 코드로 열고 닫는 공개 API가 없어서,
//  전역 단축키(⌃⌥⌘B)로 팝오버를 토글하려면 NSStatusItem + NSPopover 조합이 필요하다.
//

import AppKit
import SwiftUI
import Carbon.HIToolbox

extension Notification.Name {
    static let closePopover = Notification.Name("closePopover")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()

    private var hotKeyRef: EventHotKeyRef?
    private var hotKeyHandler: EventHandlerRef?
    private var shortcutEnabled = true

    private static let hotKeyID = EventHotKeyID(signature: fourCharCode("BarB"), id: 1)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        UserDefaults.standard.register(defaults: ["shortcutEnabled": true])
        shortcutEnabled = UserDefaults.standard.bool(forKey: "shortcutEnabled")

        setupStatusItem()
        setupPopover()

        if shortcutEnabled {
            registerGlobalHotKey()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(handleClosePopover),
            name: .closePopover, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleDefaultsChanged),
            name: UserDefaults.didChangeNotification, object: nil
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

    private func setupPopover() {
        popover.contentSize = NSSize(width: 450, height: 600)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PopoverView())
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    @objc private func handleClosePopover() {
        if popover.isShown {
            popover.performClose(nil)
        }
    }

    // MARK: - Settings sync

    @objc private func handleDefaultsChanged() {
        let newValue = UserDefaults.standard.bool(forKey: "shortcutEnabled")
        guard newValue != shortcutEnabled else { return }
        shortcutEnabled = newValue
        if newValue {
            registerGlobalHotKey()
        } else {
            unregisterGlobalHotKey()
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

private func fourCharCode(_ string: String) -> FourCharCode {
    var result: FourCharCode = 0
    for scalar in string.unicodeScalars.prefix(4) {
        result = (result << 8) + FourCharCode(scalar.value)
    }
    return result
}
