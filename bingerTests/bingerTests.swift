//
//  bingerTests.swift
//  bingerTests
//
//  Created by Al West on 22/06/2026.
//

import Testing
import Foundation
@testable import binger

struct bingerTests {

    private func makeImage(startDate: String) -> BingImage {
        BingImage(
            imageURL: URL(string: "https://www.bing.com/image.jpg")!,
            title: "Title",
            copyright: "Copyright",
            startDate: startDate
        )
    }

    @Test func displayDateFormatsEightDigitString() {
        let image = makeImage(startDate: "20260701")
        #expect(image.displayDate == "2026-07-01")
    }

    @Test func displayDatePassesThroughUnexpectedLength() {
        let image = makeImage(startDate: "2026")
        #expect(image.displayDate == "2026")
    }

    @Test func identifiableIdMatchesStartDate() {
        let image = makeImage(startDate: "20260615")
        #expect(image.id == "20260615")
    }

    @Test func imageIsCodableRoundTrip() throws {
        let original = makeImage(startDate: "20260101")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(BingImage.self, from: data)
        #expect(decoded == original)
    }
}
