//
//  bingerApp.swift
//  binger
//

import SwiftUI

@main
struct bingerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = WallpaperCoordinator()
    @State private var loginItem = LoginItemManager()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra("Binger", systemImage: "photo.on.rectangle.angled") {
            MenuBarContent(
                coordinator: coordinator,
                loginItem: loginItem,
                openWindow: { openWindow(id: "main") }
            )
        }

        Window("Binger", id: "main") {
            ContentView()
                .environment(coordinator)
                .environment(loginItem)
        }
        .windowResizability(.contentMinSize)
    }
}
