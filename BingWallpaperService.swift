//
//  BingWallpaperService.swift
//  binger
//

import Foundation

struct BingImage: Sendable, Hashable, Identifiable, Codable {
    var id: String { startDate }
    let imageURL: URL
    let title: String
    let copyright: String
    let startDate: String

    var displayDate: String {
        guard startDate.count == 8 else { return startDate }
        let year = startDate.prefix(4)
        let month = startDate.dropFirst(4).prefix(2)
        let day = startDate.dropFirst(6).prefix(2)
        return "\(year)-\(month)-\(day)"
    }
}

enum BingWallpaperError: Error, LocalizedError {
    case invalidResponse
    case noImageAvailable

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Bing returned an unexpected response."
        case .noImageAvailable: "Bing has no wallpaper available right now."
        }
    }
}

struct BingWallpaperService {
    private static let host = "https://www.bing.com"

    func fetchToday() async throws -> BingImage {
        let images = try await fetch(idx: 0, count: 1)
        guard let first = images.first else { throw BingWallpaperError.noImageAvailable }
        return first
    }

    func fetchRecent(count: Int = 30) async throws -> [BingImage] {
        let target = max(1, min(count, 60))
        let pageSize = 8
        var collected: [String: BingImage] = [:]
        var firstError: Error?

        var idx = 0
        while collected.count < target {
            do {
                let page = try await fetch(idx: idx, count: pageSize)
                if page.isEmpty { break }
                var addedAny = false
                for image in page where collected[image.startDate] == nil {
                    collected[image.startDate] = image
                    addedAny = true
                }
                // Bing returns the same window once idx exceeds its archive limit;
                // bail out as soon as a page contributes nothing new.
                if !addedAny { break }
                if page.count < pageSize { break }
                idx += pageSize
            } catch {
                if collected.isEmpty {
                    firstError = error
                }
                break
            }
        }

        if collected.isEmpty, let firstError {
            throw firstError
        }

        return collected.values
            .sorted { $0.startDate > $1.startDate }
            .prefix(target)
            .map { $0 }
    }

    private func fetch(idx: Int, count: Int) async throws -> [BingImage] {
        var components = URLComponents(string: "\(Self.host)/HPImageArchive.aspx")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "js"),
            URLQueryItem(name: "idx", value: String(idx)),
            URLQueryItem(name: "n", value: String(count)),
            URLQueryItem(name: "mkt", value: "en-US")
        ]
        guard let url = components.url else { throw BingWallpaperError.invalidResponse }

        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw BingWallpaperError.invalidResponse
        }

        let decoded = try JSONDecoder().decode(ArchiveResponse.self, from: data)
        return decoded.images.compactMap { entry in
            let absolute = upgradeToUHD(path: entry.url)
            guard let url = URL(string: Self.host + absolute) else { return nil }
            return BingImage(
                imageURL: url,
                title: entry.title,
                copyright: entry.copyright,
                startDate: entry.startdate
            )
        }
    }

    private func upgradeToUHD(path: String) -> String {
        if let range = path.range(of: "_1920x1080") {
            return path.replacingCharacters(in: range, with: "_UHD")
        }
        return path
    }

    private struct ArchiveResponse: Decodable {
        let images: [Image]
        struct Image: Decodable {
            let url: String
            let title: String
            let copyright: String
            let startdate: String
        }
    }
}
