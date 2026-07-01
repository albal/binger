//
//  MenuBarContent.swift
//  binger
//

import SwiftUI
import AppKit

struct MenuBarContent: View {
    let coordinator: WallpaperCoordinator
    let loginItem: LoginItemManager
    let openWindow: () -> Void

    var body: some View {
        Button("Open Binger…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow()
        }

        Divider()

        if let date = coordinator.lastAppliedDate {
            Text("Applied: \(formattedDate(date))")
        } else {
            Text("No wallpaper applied yet")
        }

        if let next = coordinator.nextCheck {
            Text("Next check: \(next.formatted(date: .omitted, time: .shortened))")
        }

        Button("Check for New Wallpaper") {
            Task { await coordinator.checkForNewAndApply() }
        }

        Button("Reapply Today's Wallpaper") {
            Task {
                await coordinator.refresh()
                if let today = coordinator.history.first {
                    await coordinator.apply(today)
                }
            }
        }

        Divider()

        Toggle("Launch at Login", isOn: Binding(
            get: { loginItem.isEnabled },
            set: { loginItem.setEnabled($0) }
        ))

        Divider()

        Button("Quit Binger") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func formattedDate(_ startDate: String) -> String {
        guard startDate.count == 8 else { return startDate }
        let year = startDate.prefix(4)
        let month = startDate.dropFirst(4).prefix(2)
        let day = startDate.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }
}
