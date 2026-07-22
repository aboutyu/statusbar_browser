//
//  MenubarBrowserApp.swift
//  MenubarBrowser
//
//  Created by yutaehun on 1/21/26.
//

import SwiftUI
import SwiftData

@main
struct MenubarBrowserApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        // 메뉴바 아이콘과 팝오버는 AppDelegate가 NSStatusItem/NSPopover로 직접 관리한다.
        // (전역 단축키로 팝오버를 여닫으려면 MenuBarExtra에는 없는 프로그래밍적 제어가 필요하기 때문)

        // 바브라우저에 관하여
        Window("바브라우저에 관하여", id: "about_window") {
            AboutAppMenu()
                .frame(minWidth: 300, minHeight: 280)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .defaultSize(width: 300, height: 150)

        // 환경설정
        Window("환경설정", id: "settings_window") {
            SettingsPopMenu()
                .frame(minWidth: 300, minHeight: 150)
                .onDisappear {
                    NSApp.setActivationPolicy(.accessory)
                }
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .defaultSize(width: 300, height: 150)
    }
}
