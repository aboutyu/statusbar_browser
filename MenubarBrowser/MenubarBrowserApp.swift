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
        // 메뉴바 아이콘/팝오버뿐 아니라 About/설정 창도 전부 AppDelegate가 AppKit(NSStatusItem/
        // NSPopover/NSWindow)으로 직접 관리한다. SwiftUI Window scene은 macOS 14에서 launch
        // 시점에 자동으로 표시될 수 있어(제어 불가) 의도적으로 쓰지 않는다.
        // Settings 씬은 앱이 항상 최소 1개의 Scene을 가져야 하는 SwiftUI 요구사항을 채우기 위한
        // 빈 자리표시자일 뿐이며, Settings scene은 launch 시 자동으로 열리지 않는다.
        Settings {
            EmptyView()
        }
    }
}
