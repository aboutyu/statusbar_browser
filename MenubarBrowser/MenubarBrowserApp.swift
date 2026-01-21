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
    }
}
