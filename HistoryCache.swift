//
//  HistoryCache.swift
//  binger
//

import Foundation

/// Persists the wallpaper history to a JSON file. The directory is injectable so tests
/// can point it at a temporary location instead of Application Support.
struct HistoryCache {
    private let fileURL: URL?

    init(directory: URL? = HistoryCache.defaultDirectory) {
        self.fileURL = directory?.appendingPathComponent("history.json")
    }

    static var defaultDirectory: URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let folder = support.appendingPathComponent("Binger", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func load() -> [BingImage] {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([BingImage].self, from: data)) ?? []
    }

    func save(_ images: [BingImage]) {
        guard let fileURL, let data = try? JSONEncoder().encode(images) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
