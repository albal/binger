//
//  WallpaperLogic.swift
//  binger
//
//  Pure, side-effect-free logic extracted from WallpaperCoordinator so it can be unit tested.
//

import Foundation

enum WallpaperLogic {
    /// Unions existing and freshly fetched images, deduped by `startDate`, newest first, capped at `limit`.
    static func mergeHistory(existing: [BingImage], fetched: [BingImage], limit: Int) -> [BingImage] {
        var byDate: [String: BingImage] = [:]
        for image in existing { byDate[image.startDate] = image }
        for image in fetched { byDate[image.startDate] = image }
        return byDate.values
            .sorted { $0.startDate > $1.startDate }
            .prefix(max(0, limit))
            .map { $0 }
    }

    /// Keeps a selection index valid after the history size changes.
    static func clampedSelection(_ index: Int, count: Int) -> Int {
        guard index >= count else { return index }
        return max(0, count - 1)
    }

    /// The next top-of-hour after `now`, offset by a random minute within that hour.
    static func nextScheduledDate(from now: Date, randomMinute: Int, calendar: Calendar = .current) -> Date {
        let topOfNextHour = calendar.nextDate(
            after: now,
            matching: DateComponents(minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? now.addingTimeInterval(3600)
        return topOfNextHour.addingTimeInterval(TimeInterval(randomMinute * 60))
    }
}
