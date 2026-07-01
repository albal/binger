//
//  WallpaperCoordinator.swift
//  binger
//

import Foundation
import Observation
import AppKit

@Observable
final class WallpaperCoordinator {
    enum Status {
        case idle, loading, applying
    }

    private(set) var history: [BingImage] = []
    var selectedIndex: Int = 0
    private(set) var status: Status = .idle
    private(set) var errorMessage: String?
    private(set) var lastAppliedDate: String?
    private(set) var lastCheck: Date?
    private(set) var nextCheck: Date?

    private let service = BingWallpaperService()
    private let manager = WallpaperManager()
    private let defaults = UserDefaults.standard
    private var scheduler: Task<Void, Never>?

    private static let displayLimit = 30
    private static let cacheLimit = 90

    private enum DefaultsKey {
        static let lastApplied = "binger.lastAppliedStartDate"
    }

    init() {
        lastAppliedDate = defaults.string(forKey: DefaultsKey.lastApplied)
        history = HistoryCache.load().sorted { $0.startDate > $1.startDate }
        startBackgroundChecks()
    }

    var selectedImage: BingImage? {
        guard history.indices.contains(selectedIndex) else { return nil }
        return history[selectedIndex]
    }

    var canGoOlder: Bool {
        !history.isEmpty && selectedIndex < history.count - 1
    }

    var canGoNewer: Bool {
        selectedIndex > 0
    }

    func goOlder() {
        guard canGoOlder else { return }
        selectedIndex += 1
    }

    func goNewer() {
        guard canGoNewer else { return }
        selectedIndex -= 1
    }

    var isOnToday: Bool {
        !history.isEmpty && selectedIndex == 0
    }

    func goToToday() {
        guard !history.isEmpty else { return }
        selectedIndex = 0
    }

    func refresh() async {
        status = .loading
        errorMessage = nil
        do {
            let recent = try await service.fetchRecent(count: Self.displayLimit)
            mergeIntoHistory(recent)
            status = .idle
            lastCheck = Date()
        } catch {
            errorMessage = error.localizedDescription
            status = .idle
        }
    }

    func applySelected() async {
        guard let image = selectedImage else { return }
        await apply(image)
    }

    func apply(_ image: BingImage) async {
        status = .applying
        errorMessage = nil
        do {
            _ = try await manager.apply(image)
            lastAppliedDate = image.startDate
            defaults.set(image.startDate, forKey: DefaultsKey.lastApplied)
            status = .idle
        } catch {
            errorMessage = error.localizedDescription
            status = .idle
        }
    }

    func checkForNewAndApply() async {
        lastCheck = Date()
        errorMessage = nil
        do {
            let today = try await service.fetchToday()
            let isNew = !history.contains(where: { $0.startDate == today.startDate })
            mergeIntoHistory([today])
            if isNew {
                selectedIndex = 0
            }
            if today.startDate != lastAppliedDate {
                await apply(today)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func mergeIntoHistory(_ fetched: [BingImage]) {
        var byDate: [String: BingImage] = [:]
        for image in history { byDate[image.startDate] = image }
        for image in fetched { byDate[image.startDate] = image }
        let merged = byDate.values.sorted { $0.startDate > $1.startDate }
        history = Array(merged.prefix(Self.displayLimit))
        HistoryCache.save(Array(merged.prefix(Self.cacheLimit)))
        if selectedIndex >= history.count {
            selectedIndex = max(0, history.count - 1)
        }
    }

    func startBackgroundChecks() {
        guard scheduler == nil else { return }
        scheduler = Task { [weak self] in
            await self?.runScheduleLoop()
        }
    }

    func stopBackgroundChecks() {
        scheduler?.cancel()
        scheduler = nil
        nextCheck = nil
    }

    private func runScheduleLoop() async {
        await checkForNewAndApply()
        while !Task.isCancelled {
            let target = nextScheduledDate(from: Date())
            nextCheck = target
            let delay = target.timeIntervalSinceNow
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
            if Task.isCancelled { return }
            await checkForNewAndApply()
        }
    }

    private func nextScheduledDate(from now: Date) -> Date {
        let calendar = Calendar.current
        let topOfNextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)
        let randomMinute = Int.random(in: 0..<60)
        return topOfNextHour.addingTimeInterval(TimeInterval(randomMinute * 60))
    }
}

private enum HistoryCache {
    private static let filename = "history.json"

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let folder = support.appendingPathComponent("Binger", isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(filename)
    }

    static func load() -> [BingImage] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([BingImage].self, from: data)) ?? []
    }

    static func save(_ images: [BingImage]) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(images) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
