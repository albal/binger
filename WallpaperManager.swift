//
//  WallpaperManager.swift
//  binger
//

import AppKit
import Foundation

enum WallpaperError: Error, LocalizedError {
    case downloadFailed
    case noScreens

    var errorDescription: String? {
        switch self {
        case .downloadFailed: "Couldn't download the wallpaper image."
        case .noScreens: "No screens were found to set the wallpaper on."
        }
    }
}

struct WallpaperManager {
    func apply(_ image: BingImage) async throws -> URL {
        let localURL = try await download(image)
        try await setOnAllScreens(localURL)
        return localURL
    }

    private func download(_ image: BingImage) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: image.imageURL)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WallpaperError.downloadFailed
        }

        let destination = try Self.wallpaperDestination(for: image)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Computes the on-disk destination for a wallpaper. `baseDirectory` is injectable for testing.
    static func wallpaperDestination(
        for image: BingImage,
        baseDirectory: URL? = nil
    ) throws -> URL {
        let fm = FileManager.default
        let support: URL
        if let baseDirectory {
            support = baseDirectory
        } else {
            support = try fm.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
        }
        let folder = support.appendingPathComponent("Binger", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("bing-\(image.startDate).jpg")
    }

    @MainActor
    private func setOnAllScreens(_ url: URL) throws {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { throw WallpaperError.noScreens }

        let options: [NSWorkspace.DesktopImageOptionKey: Any] = [
            .imageScaling: NSImageScaling.scaleProportionallyUpOrDown.rawValue,
            .allowClipping: true
        ]

        for screen in screens {
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: options)
        }
    }
}
