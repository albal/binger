//
//  bingerTests.swift
//  bingerTests
//
//  Created by Al West on 22/06/2026.
//

import Testing
import Foundation
@testable import binger

// MARK: - Helpers

private func makeImage(
    startDate: String,
    title: String = "Title",
    copyright: String = "Copyright",
    urlString: String = "https://www.bing.com/image.jpg"
) -> BingImage {
    BingImage(
        imageURL: URL(string: urlString)!,
        title: title,
        copyright: copyright,
        startDate: startDate
    )
}

/// A DataFetching stub that returns queued responses and records requested URLs.
private final class MockFetcher: DataFetching, @unchecked Sendable {
    struct Response {
        let data: Data
        let statusCode: Int
    }

    private let responses: [Response]
    private let error: Error?
    private(set) var requestedURLs: [URL] = []
    private var index = 0

    init(responses: [Response]) {
        self.responses = responses
        self.error = nil
    }

    init(error: Error) {
        self.responses = []
        self.error = error
    }

    func data(from url: URL) async throws -> (Data, URLResponse) {
        requestedURLs.append(url)
        if let error { throw error }
        let response = responses[min(index, responses.count - 1)]
        index += 1
        let http = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (response.data, http)
    }
}

private func archiveJSON(_ entries: [(url: String, title: String, copyright: String, date: String)]) -> Data {
    let images = entries.map { entry in
        """
        {"url":"\(entry.url)","title":"\(entry.title)","copyright":"\(entry.copyright)","startdate":"\(entry.date)"}
        """
    }.joined(separator: ",")
    return Data("{\"images\":[\(images)]}".utf8)
}

private func page(count: Int, startingDay: Int) -> MockFetcher.Response {
    let entries = (0..<count).map { offset -> (String, String, String, String) in
        let day = startingDay - offset
        let date = String(format: "202601%02d", day)
        return ("/th?id=OHR.test_1920x1080.jpg", "Title \(date)", "Copyright", date)
    }
    return .init(data: archiveJSON(entries), statusCode: 200)
}

private struct DummyError: Error {}

// MARK: - BingImage

struct BingImageTests {
    @Test func displayDateFormatsEightDigitString() {
        #expect(makeImage(startDate: "20260701").displayDate == "2026-07-01")
    }

    @Test func displayDatePassesThroughUnexpectedLength() {
        #expect(makeImage(startDate: "2026").displayDate == "2026")
        #expect(makeImage(startDate: "").displayDate == "")
    }

    @Test func identifiableIdMatchesStartDate() {
        #expect(makeImage(startDate: "20260615").id == "20260615")
    }

    @Test func codableRoundTrip() throws {
        let original = makeImage(startDate: "20260101")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BingImage.self, from: data)
        #expect(decoded == original)
    }
}

// MARK: - BingWallpaperService parsing / URL building

struct BingServiceStaticTests {
    @Test func upgradeToUHDRewritesResolution() {
        let input = "/th?id=OHR.foo_1920x1080.jpg"
        #expect(BingWallpaperService.upgradeToUHD(path: input) == "/th?id=OHR.foo_UHD.jpg")
    }

    @Test func upgradeToUHDLeavesOtherPathsUnchanged() {
        let input = "/th?id=OHR.foo_UHD.jpg"
        #expect(BingWallpaperService.upgradeToUHD(path: input) == input)
    }

    @Test func archiveURLContainsExpectedQuery() throws {
        let url = try #require(BingWallpaperService.archiveURL(idx: 8, count: 8))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try #require(components.queryItems)
        #expect(items.contains(URLQueryItem(name: "idx", value: "8")))
        #expect(items.contains(URLQueryItem(name: "n", value: "8")))
        #expect(items.contains(URLQueryItem(name: "format", value: "js")))
        #expect(items.contains(URLQueryItem(name: "mkt", value: "en-US")))
        #expect(url.absoluteString.hasPrefix("https://www.bing.com/HPImageArchive.aspx"))
    }

    @Test func parseBuildsUHDAbsoluteURL() throws {
        let data = archiveJSON([("/th?id=OHR.foo_1920x1080.jpg", "T", "C", "20260701")])
        let images = try BingWallpaperService.parse(data)
        #expect(images.count == 1)
        #expect(images[0].startDate == "20260701")
        #expect(images[0].imageURL.absoluteString == "https://www.bing.com/th?id=OHR.foo_UHD.jpg")
        #expect(images[0].title == "T")
        #expect(images[0].copyright == "C")
    }

    @Test func parseThrowsOnInvalidJSON() {
        #expect(throws: (any Error).self) {
            _ = try BingWallpaperService.parse(Data("not json".utf8))
        }
    }
}

// MARK: - BingWallpaperService async behaviour

struct BingServiceFetchTests {
    @Test func fetchTodayReturnsFirstImage() async throws {
        let fetcher = MockFetcher(responses: [
            .init(data: archiveJSON([("/th?id=OHR.a_1920x1080.jpg", "T", "C", "20260701")]), statusCode: 200)
        ])
        let service = BingWallpaperService(fetcher: fetcher)
        let image = try await service.fetchToday()
        #expect(image.startDate == "20260701")
    }

    @Test func fetchTodayThrowsWhenEmpty() async {
        let fetcher = MockFetcher(responses: [.init(data: archiveJSON([]), statusCode: 200)])
        let service = BingWallpaperService(fetcher: fetcher)
        await #expect(throws: BingWallpaperError.self) {
            _ = try await service.fetchToday()
        }
    }

    @Test func fetchThrowsInvalidResponseOnNon200() async {
        let fetcher = MockFetcher(responses: [.init(data: Data(), statusCode: 500)])
        let service = BingWallpaperService(fetcher: fetcher)
        await #expect(throws: BingWallpaperError.self) {
            _ = try await service.fetchToday()
        }
    }

    @Test func fetchRecentPaginatesAndDedupes() async throws {
        // Two full pages of 8 with distinct days, then a repeat page that adds nothing.
        let fetcher = MockFetcher(responses: [
            page(count: 8, startingDay: 20),
            page(count: 8, startingDay: 12),
            page(count: 8, startingDay: 12) // duplicate window -> loop should stop
        ])
        let service = BingWallpaperService(fetcher: fetcher)
        let images = try await service.fetchRecent(count: 30)
        #expect(images.count == 16)
        // Sorted newest first.
        #expect(images.first?.startDate == "20260120")
        #expect(images.last?.startDate == "20260105")
    }

    @Test func fetchRecentStopsOnPartialPage() async throws {
        let fetcher = MockFetcher(responses: [page(count: 3, startingDay: 5)])
        let service = BingWallpaperService(fetcher: fetcher)
        let images = try await service.fetchRecent(count: 30)
        #expect(images.count == 3)
    }

    @Test func fetchRecentRespectsTargetCount() async throws {
        let fetcher = MockFetcher(responses: [
            page(count: 8, startingDay: 20),
            page(count: 8, startingDay: 12)
        ])
        let service = BingWallpaperService(fetcher: fetcher)
        let images = try await service.fetchRecent(count: 5)
        #expect(images.count == 5)
    }

    @Test func fetchRecentThrowsWhenFirstPageFails() async {
        let fetcher = MockFetcher(error: DummyError())
        let service = BingWallpaperService(fetcher: fetcher)
        await #expect(throws: (any Error).self) {
            _ = try await service.fetchRecent(count: 30)
        }
    }

    @Test func fetchRecentClampsCountToAtLeastOne() async throws {
        let fetcher = MockFetcher(responses: [page(count: 8, startingDay: 20)])
        let service = BingWallpaperService(fetcher: fetcher)
        let images = try await service.fetchRecent(count: 0)
        #expect(images.count == 1)
    }
}

// MARK: - WallpaperLogic

struct WallpaperLogicTests {
    @Test func mergeUnionsAndDedupesNewestFirst() {
        let existing = [makeImage(startDate: "20260101"), makeImage(startDate: "20260103")]
        let fetched = [makeImage(startDate: "20260103"), makeImage(startDate: "20260105")]
        let merged = WallpaperLogic.mergeHistory(existing: existing, fetched: fetched, limit: 10)
        #expect(merged.map(\.startDate) == ["20260105", "20260103", "20260101"])
    }

    @Test func mergePrefersFetchedOnConflict() {
        let existing = [makeImage(startDate: "20260101", title: "Old")]
        let fetched = [makeImage(startDate: "20260101", title: "New")]
        let merged = WallpaperLogic.mergeHistory(existing: existing, fetched: fetched, limit: 10)
        #expect(merged.count == 1)
        #expect(merged[0].title == "New")
    }

    @Test func mergeAppliesLimit() {
        let existing = (1...5).map { makeImage(startDate: String(format: "202601%02d", $0)) }
        let merged = WallpaperLogic.mergeHistory(existing: existing, fetched: [], limit: 3)
        #expect(merged.count == 3)
        #expect(merged.first?.startDate == "20260105")
    }

    @Test func mergeHandlesZeroLimit() {
        let existing = [makeImage(startDate: "20260101")]
        #expect(WallpaperLogic.mergeHistory(existing: existing, fetched: [], limit: 0).isEmpty)
    }

    @Test func clampedSelectionKeepsValidIndex() {
        #expect(WallpaperLogic.clampedSelection(2, count: 5) == 2)
    }

    @Test func clampedSelectionPullsBackWhenOutOfRange() {
        #expect(WallpaperLogic.clampedSelection(5, count: 3) == 2)
    }

    @Test func clampedSelectionHandlesEmpty() {
        #expect(WallpaperLogic.clampedSelection(3, count: 0) == 0)
    }

    @Test func nextScheduledDateIsWithinNextHourPlusMinute() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        // 2026-07-01 10:15:00 UTC
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 10, minute: 15, second: 0
        )))
        let result = WallpaperLogic.nextScheduledDate(from: now, randomMinute: 20, calendar: calendar)
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 11, minute: 20, second: 0
        )))
        #expect(result == expected)
    }

    @Test func nextScheduledDateWithZeroMinuteLandsOnTopOfHour() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 1, hour: 23, minute: 59, second: 0
        )))
        let result = WallpaperLogic.nextScheduledDate(from: now, randomMinute: 0, calendar: calendar)
        let expected = try #require(calendar.date(from: DateComponents(
            year: 2026, month: 7, day: 2, hour: 0, minute: 0, second: 0
        )))
        #expect(result == expected)
    }
}

// MARK: - HistoryCache

struct HistoryCacheTests {
    private func tempDirectory() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("binger-tests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    @Test func saveThenLoadRoundTrips() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let cache = HistoryCache(directory: dir)
        let images = [makeImage(startDate: "20260101"), makeImage(startDate: "20260102")]
        cache.save(images)
        #expect(cache.load() == images)
    }

    @Test func loadReturnsEmptyWhenNoFile() {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(HistoryCache(directory: dir).load().isEmpty)
    }

    @Test func loadReturnsEmptyOnCorruptData() throws {
        let dir = tempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("history.json"))
        #expect(HistoryCache(directory: dir).load().isEmpty)
    }

    @Test func nilDirectoryIsSafe() {
        let cache = HistoryCache(directory: nil)
        cache.save([makeImage(startDate: "20260101")])
        #expect(cache.load().isEmpty)
    }
}

// MARK: - WallpaperManager destination

struct WallpaperManagerTests {
    @Test func destinationUsesStartDateAndBingerFolder() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("wm-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: base) }
        let url = try WallpaperManager.wallpaperDestination(
            for: makeImage(startDate: "20260701"),
            baseDirectory: base
        )
        #expect(url.lastPathComponent == "bing-20260701.jpg")
        #expect(url.deletingLastPathComponent().lastPathComponent == "Binger")
        // Folder is created as a side effect.
        var isDir: ObjCBool = false
        #expect(FileManager.default.fileExists(
            atPath: url.deletingLastPathComponent().path,
            isDirectory: &isDir
        ))
        #expect(isDir.boolValue)
    }
}

// MARK: - Error descriptions

struct ErrorMessageTests {
    @Test func bingErrorsHaveDescriptions() {
        #expect(BingWallpaperError.invalidResponse.errorDescription != nil)
        #expect(BingWallpaperError.noImageAvailable.errorDescription != nil)
    }

    @Test func wallpaperErrorsHaveDescriptions() {
        #expect(WallpaperError.downloadFailed.errorDescription != nil)
        #expect(WallpaperError.noScreens.errorDescription != nil)
    }
}
