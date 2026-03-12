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
        MenuBarExtra {
            PopoverView()
                .onAppear() {
                    DispatchQueue.main.async {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
        } label: {
            Image("bar_icon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.window)
        
        // 바브라우저에 관하여
        Window("바브라우저에 관하여", id: "about_window") {
            AboutAppMenu()
                .frame(minWidth: 300, minHeight: 280)
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .defaultSize(width: 300, height: 150)
        
        // 환경설정
        Window("환경설정", id: "settings_window") {
            SettingsPopMenu()
                .frame(minWidth: 300, minHeight: 150)
        }
        .windowResizability(.contentSize)
        .windowStyle(.automatic)
        .defaultSize(width: 300, height: 150)
    }
}
