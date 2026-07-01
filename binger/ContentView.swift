//
//  ContentView.swift
//  binger
//

import SwiftUI
import AppKit

struct ContentView: View {
    @Environment(WallpaperCoordinator.self) private var coordinator
    @Environment(LoginItemManager.self) private var loginItem

    @State private var previewImage: NSImage?
    @State private var loadingPreviewFor: String?

    var body: some View {
        VStack(spacing: 16) {
            preview
                .frame(maxWidth: .infinity, minHeight: 280, maxHeight: 360)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            navigation
                .padding(.vertical, 4)
            metadata
            actions
                .padding(.vertical, 4)
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 600)
        .task {
            if coordinator.history.isEmpty {
                await coordinator.refresh()
            }
            await loadPreviewIfNeeded()
        }
        .onChange(of: coordinator.selectedIndex) { _, _ in
            Task { await loadPreviewIfNeeded() }
        }
        .onChange(of: coordinator.history) { _, _ in
            Task { await loadPreviewIfNeeded() }
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)

            if let previewImage {
                Image(nsImage: previewImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else if coordinator.status == .loading {
                ProgressView("Loading wallpapers…")
            } else {
                Text("No wallpaper loaded")
                    .foregroundStyle(.secondary)
            }

            if coordinator.status == .applying {
                Color.black.opacity(0.35)
                ProgressView("Applying…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }
        }
    }

    private var navigation: some View {
        HStack {
            Button {
                coordinator.goOlder()
            } label: {
                Label("Older", systemImage: "chevron.left")
            }
            .disabled(!coordinator.canGoOlder)

            Spacer()

            Picker("Date", selection: Binding(
                get: { coordinator.selectedIndex },
                set: { coordinator.selectedIndex = $0 }
            )) {
                ForEach(Array(coordinator.history.enumerated()), id: \.offset) { index, image in
                    Text(image.displayDate).tag(index)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(minWidth: 130)
            .disabled(coordinator.history.isEmpty)

            Button("Today") {
                coordinator.goToToday()
            }
            .disabled(coordinator.isOnToday)

            Spacer()

            Button {
                coordinator.goNewer()
            } label: {
                Label("Newer", systemImage: "chevron.right")
            }
            .labelStyle(.titleAndIcon)
            .disabled(!coordinator.canGoNewer)
        }
    }

    @ViewBuilder
    private var metadata: some View {
        if let image = coordinator.selectedImage {
            VStack(alignment: .leading, spacing: 4) {
                Text(image.title)
                    .font(.headline)
                Text(image.copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        if let error = coordinator.errorMessage {
            Text(error)
                .font(.callout)
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack {
            Button("Refresh") {
                Task { await coordinator.refresh() }
            }
            .disabled(coordinator.status == .loading || coordinator.status == .applying)

            Toggle("Launch at Login", isOn: Binding(
                get: { loginItem.isEnabled },
                set: { loginItem.setEnabled($0) }
            ))
            .toggleStyle(.switch)

            Spacer()

            Button("Set as Wallpaper") {
                Task { await coordinator.applySelected() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(coordinator.selectedImage == nil || coordinator.status == .applying)
        }
    }

    @ViewBuilder
    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let last = coordinator.lastCheck {
                Text("Last checked: \(last.formatted(date: .omitted, time: .shortened))")
            }
            if let next = coordinator.nextCheck {
                Text("Next auto-check: \(next.formatted(date: .omitted, time: .shortened))")
            }
            Text("macOS uses the desktop wallpaper as the lock screen background by default. If yours is set separately in System Settings, update it there.")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func loadPreviewIfNeeded() async {
        guard let image = coordinator.selectedImage else {
            previewImage = nil
            loadingPreviewFor = nil
            return
        }
        if loadingPreviewFor == image.startDate { return }
        loadingPreviewFor = image.startDate
        previewImage = nil
        do {
            let (data, _) = try await URLSession.shared.data(from: image.imageURL)
            if loadingPreviewFor == image.startDate {
                previewImage = NSImage(data: data)
            }
        } catch {
            // Preview failures are non-fatal; coordinator surfaces real errors.
        }
    }
}

#Preview {
    ContentView()
        .environment(WallpaperCoordinator())
        .environment(LoginItemManager())
}
