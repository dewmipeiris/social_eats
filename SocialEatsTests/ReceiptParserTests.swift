//
//  ReceiptParserTests.swift
//  SocialEatsTests
//
//  Tests the logic behind the Vision receipt scanner (Advanced Feature 1).
//  We feed in text lines exactly like Vision returns them.
//

import Testing
import Foundation
import CoreGraphics
@testable import SocialEats

@Suite("Receipt parsing")
struct ReceiptParserTests {

    /// A typical Colombo restaurant receipt as OCR text lines
    let sampleLines = [
        "LUIGI'S BRICK OVEN",
        "Dharmapala Mawatha, Colombo 07",
        "Tel: 011 234 5678",
        "Date: 24/10/2026   Time: 19:15",
        "Margherita Pizza      1,850.00",
        "Iced Lemon Tea          450.00",
        "Subtotal              2,300.00",
        "Service Charge 10%      230.00",
        "TOTAL            LKR  2,530.00",
        "Thank you!"
    ]

    @Test("Finds restaurant name, total, currency and time")
    func parsesFullReceipt() throws {
        let result = ReceiptParser.parse(lines: sampleLines)

        #expect(result.restaurantName?.lowercased() == "luigi's brick oven")
        #expect(result.total == 2530.00)               // TOTAL wins over Subtotal
        #expect(result.currencyCode == "LKR")

        let time = try #require(result.timestamp)
        let parts = Calendar.current.dateComponents([.day, .month, .year, .hour, .minute], from: time)
        #expect(parts.day == 24 && parts.month == 10 && parts.year == 2026)
        #expect(parts.hour == 19 && parts.minute == 15)
        #expect(result.completeness == 1.0)
    }

    @Test("Subtotal line is never treated as the final total")
    func ignoresSubtotal() {
        let total = ReceiptParser.findTotal(in: ["Subtotal 900.00", "Grand Total 1,020.50"])
        #expect(total == 1020.50)
    }

    @Test("Amount formats", arguments: [
        ("12.50", 12.50),
        ("Margherita Pizza 1,850.00", 1850.00),
        ("TOTAL LKR 2,530.00", 2530.00),
        ("Green Tea x2 350.00", 350.00)
    ])
    func amountFormats(line: String, expected: Double) {
        #expect(ReceiptParser.amounts(in: line).last == expected)
    }

    @Test("Numbers that are not money are ignored")
    func notMoney() {
        #expect(ReceiptParser.amounts(in: "Tel: 011 234 5678").isEmpty)
        #expect(ReceiptParser.amounts(in: "Service Charge 10%").isEmpty)
    }

    @Test("12-hour times are converted correctly")
    func pmTime() throws {
        let date = try #require(ReceiptParser.findTimestamp(in: ["Paid at 7:05 PM"], now: Date()))
        #expect(Calendar.current.component(.hour, from: date) == 19)
    }

    @Test("Falls back to the largest amount when there is no TOTAL keyword")
    func fallbackLargestAmount() {
        #expect(ReceiptParser.findTotal(in: ["Coffee 400.00", "Cake 650.00", "1,050.00"]) == 1050.00)
    }

    // MARK: - Validation against the reservation

    @Test("Receipt from the right venue at the right time is verified")
    func verified() {
        let meetup = makeDate(hour: 19, minute: 0)
        let result = ReceiptScanResult(restaurantName: "Luigis Brick Oven", total: 2530,
                                       currencyCode: "LKR", timestamp: makeDate(hour: 20, minute: 30), rawLines: [])
        let validation = ReceiptParser.validate(result, venueName: "Luigi's Brick Oven", meetupStart: meetup)
        #expect(validation.isVerified)
    }

    @Test("Receipt from a different restaurant is rejected")
    func wrongVenue() {
        let result = ReceiptScanResult(restaurantName: "Pizza Hut", total: 2530, currencyCode: "LKR",
                                       timestamp: nil, rawLines: ["Pizza Hut"])
        let validation = ReceiptParser.validate(result, venueName: "Matsuya Kitchen", meetupStart: Date())
        #expect(validation == .venueMismatch(found: "Pizza Hut"))
    }

    @Test("Missing total is rejected")
    func missingTotal() {
        let result = ReceiptScanResult(restaurantName: "Matsuya Kitchen", total: nil, currencyCode: "LKR",
                                       timestamp: nil, rawLines: [])
        #expect(ReceiptParser.validate(result, venueName: "Matsuya Kitchen", meetupStart: Date()) == .missingTotal)
    }

    @Test("A receipt from many hours before the meetup is rejected")
    func outsideWindow() {
        let result = ReceiptScanResult(restaurantName: "Matsuya Kitchen", total: 1000, currencyCode: "LKR",
                                       timestamp: makeDate(hour: 8, minute: 0), rawLines: [])
        let validation = ReceiptParser.validate(result, venueName: "Matsuya Kitchen",
                                                meetupStart: makeDate(hour: 19, minute: 0))
        #expect(validation == .outsideTimeWindow)
    }

    private func makeDate(hour: Int, minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: Date())!
    }
}

@Suite("Fuzzy venue-name matching")
struct StringSimilarityTests {

    @Test func identicalIgnoringCaseAndPunctuation() {
        #expect(StringSimilarity.score("LUIGI'S TRATTORIA", "Luigis Trattoria") > 0.9)
    }

    @Test func containedName() {
        #expect(StringSimilarity.score("Matsuya Kitchen Colombo 07", "Matsuya Kitchen") >= 0.75)
    }

    @Test func differentNames() {
        #expect(StringSimilarity.score("Pizza Hut", "Matsuya Kitchen") < 0.4)
    }

    @Test func sharedWords() {
        // 2 of 3 words in common
        #expect(abs(StringSimilarity.score("Bella Napoli Trattoria", "Bella Napoli Pizzeria") - 2.0 / 3.0) < 0.001)
    }
}

@Suite("Joining Vision text pieces into receipt lines")
struct VisionLineMergeTests {

    /// Builds a fragment at x / y (Vision coordinates: 0 = bottom, 1 = top)
    func piece(_ text: String, x: CGFloat, y: CGFloat, height: CGFloat = 0.03) -> TextFragment {
        TextFragment(text: text, box: CGRect(x: x, y: y, width: 0.2, height: height))
    }

    @Test("Pieces on the same row are joined left to right, rows top to bottom")
    func mergesRows() {
        let lines = VisionTextRecognizer.mergeIntoLines([
            piece("3,575.00", x: 0.7, y: 0.40),          // right side of the TOTAL row (listed first!)
            piece("BELLA NAPOLI", x: 0.3, y: 0.90),
            piece("TOTAL LKR", x: 0.05, y: 0.405),       // tiny vertical wobble, same row
            piece("Thank you", x: 0.3, y: 0.20)
        ])
        #expect(lines == ["BELLA NAPOLI", "TOTAL LKR 3,575.00", "Thank you"])
    }

    @Test("Merged lines give the parser the right total")
    func mergedTotal() {
        let lines = VisionTextRecognizer.mergeIntoLines([
            piece("Subtotal", x: 0.05, y: 0.50), piece("3,250.00", x: 0.7, y: 0.50),
            piece("Service Charge 10%", x: 0.05, y: 0.45), piece("325.00", x: 0.7, y: 0.45),
            piece("TOTAL LKR", x: 0.05, y: 0.40), piece("3,575.00", x: 0.7, y: 0.40)
        ])
        #expect(ReceiptParser.findTotal(in: lines) == 3575.00)
    }
}

