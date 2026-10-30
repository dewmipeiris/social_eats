//  ReceiptParser.swift

import Foundation

enum ReceiptParser {

    // Lines containing these words are the final bill
    static let totalWords = ["total", "amount due", "balance due"]
    // ...but NOT these (they are part-totals)
    static let notTotalWords = ["subtotal", "sub total", "sub-total"]
    // Lines with these words are never the restaurant name
    static let notNameWords = ["receipt", "invoice", "tax", "tel", "phone", "www", "date", "time",
                               "table", "cashier", "order", "welcome", "bill"]

    static func parse(lines: [String], now: Date = Date()) -> ReceiptScanResult {
        // Remove empty lines and extra spaces
        var cleanLines: [String] = []
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                cleanLines.append(trimmed)
            }
        }

        return ReceiptScanResult(
            restaurantName: findRestaurantName(in: cleanLines),
            total: findTotal(in: cleanLines),
            currencyCode: findCurrency(in: cleanLines),
            timestamp: findTimestamp(in: cleanLines, now: now),
            rawLines: cleanLines
        )
    }

    static func findRestaurantName(in lines: [String]) -> String? {
        for line in lines.prefix(5) {
            let lower = line.lowercased()

            // Skip lines like "Tel: 011..." or "Date: ..."
            var isNoise = false
            for word in notNameWords where lower.contains(word) {
                isNoise = true
            }
            if isNoise { continue }

            // Count the letters in the line
            let letterCount = line.filter { $0.isLetter }.count
            if letterCount >= 3 && Double(letterCount) / Double(line.count) > 0.6 {
                return line.capitalized
            }
        }
        return nil
    }

    static func findTotal(in lines: [String]) -> Double? {
        var bestTotal: Double?

        for line in lines {
            let lower = line.lowercased()
            let hasTotalWord = totalWords.contains { lower.contains($0) }
            let hasNotTotalWord = notTotalWords.contains { lower.contains($0) }

            if hasTotalWord && !hasNotTotalWord, let amount = amounts(in: line).last {
                bestTotal = max(bestTotal ?? 0, amount)
            }
        }

        if let bestTotal {
            return bestTotal
        }

        var allAmounts: [Double] = []
        for line in lines {
            allAmounts += amounts(in: line)
        }
        return allAmounts.max()
    }

    static func amounts(in line: String) -> [Double] {
        var result: [Double] = []
        let words = line.split(separator: " ")

        for word in words {
            // "1,850.00" -> "1850.00"
            let cleaned = word.replacingOccurrences(of: ",", with: "")
            let parts = cleaned.split(separator: ".")

            if parts.count == 2, parts[1].count == 2, let value = Double(cleaned) {
                result.append(value)
            }
        }
        return result
    }

    static func findCurrency(in lines: [String]) -> String {
        let allText = lines.joined(separator: " ").lowercased()
        if allText.contains("usd") || allText.contains("$") { return "USD" }
        if allText.contains("eur") || allText.contains("€") { return "EUR" }
        if allText.contains("gbp") || allText.contains("£") { return "GBP" }
        return "LKR"
    }

    static func findTimestamp(in lines: [String], now: Date) -> Date? {
        let words = lines.joined(separator: " ").split(separator: " ").map { String($0) }
        let calendar = Calendar.current
        var dateParts = calendar.dateComponents([.year, .month, .day], from: now)
        var foundTime = false

        for (index, rawWord) in words.enumerated() {
            let word = rawWord.trimmingCharacters(in: CharacterSet(charactersIn: ",."))

            // Date: 24/10/2026
            let dayMonthYear = word.split(separator: "/")
            if dayMonthYear.count == 3,
               let day = Int(dayMonthYear[0]), let month = Int(dayMonthYear[1]), var year = Int(dayMonthYear[2]),
               (1...31).contains(day), (1...12).contains(month) {
                if year < 100 { year += 2000 }      // "26" -> 2026
                dateParts.day = day
                dateParts.month = month
                dateParts.year = year
            }

            let hourMinute = word.split(separator: ":")
            if !foundTime, hourMinute.count == 2, hourMinute[1].count == 2,
               var hour = Int(hourMinute[0]), let minute = Int(hourMinute[1]),
               (0...23).contains(hour), (0...59).contains(minute) {

                if index + 1 < words.count {
                    let nextWord = words[index + 1].lowercased()
                    if nextWord.hasPrefix("pm") && hour < 12 { hour += 12 }
                    if nextWord.hasPrefix("am") && hour == 12 { hour = 0 }
                }
                dateParts.hour = hour
                dateParts.minute = minute
                foundTime = true
            }
        }

        guard foundTime else { return nil }
        return calendar.date(from: dateParts)
    }

// check the receipt
    
    static let requiredMatchScore = 0.5
    static let allowedHoursAroundMeetup: Double = 4

    static func validate(_ result: ReceiptScanResult, venueName: String, meetupStart: Date) -> ReceiptValidation {
        // 1. There must be a total
        if result.total == nil {
            return .missingTotal
        }

        var linesToCheck = Array(result.rawLines.prefix(6))
        if let name = result.restaurantName {
            linesToCheck.insert(name, at: 0)
        }
        var bestScore = 0.0
        for line in linesToCheck {
            bestScore = max(bestScore, StringSimilarity.score(line, venueName))
        }
        if bestScore < requiredMatchScore {
            return .venueMismatch(found: result.restaurantName)
        }

        if let time = result.timestamp {
            let hoursApart = abs(time.timeIntervalSince(meetupStart)) / 3600
            if hoursApart > allowedHoursAroundMeetup {
                return .outsideTimeWindow
            }
        }

        return .verified(matchScore: bestScore)
    }
}

enum StringSimilarity {

    static func normalize(_ text: String) -> String {
        let lettersAndSpaces = text.lowercased().filter { $0.isLetter || $0.isNumber || $0 == " " }
        return lettersAndSpaces.split(separator: " ").joined(separator: " ")
    }

    static func score(_ first: String, _ second: String) -> Double {
        let a = normalize(first)
        let b = normalize(second)
        if a.isEmpty || b.isEmpty { return 0 }
        if a == b { return 1 }
        if a.contains(b) || b.contains(a) { return 0.9 }

        let wordsA = Set(a.split(separator: " "))
        let wordsB = Set(b.split(separator: " "))
        let shared = wordsA.intersection(wordsB).count
        return Double(shared) / Double(max(wordsA.count, wordsB.count))
    }
}
