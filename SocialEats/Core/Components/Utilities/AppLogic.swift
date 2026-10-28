//
//  AppLogic.swift
//  SocialEats
//
//  Pure "business logic" helpers with no UI — all unit tested:
//  - ShakeDetector   (Core Motion maths for Shake to Match)
//  - KarmaCalculator (levels, tiers and points)
//  - QRToken         (check-in code inside the offline pass)
//  - TableFilter     (category / dietary / distance filtering)
//  - DistanceText    (400m away, 1.1km away, 4 min walk)
//

import Foundation
import CoreLocation
import CryptoKit

// MARK: - Shake detection

/// Decides when a set of accelerometer readings counts as a "shake".
/// Proposal Advanced Feature 2: total acceleration > 2.5g triggers a match.
struct ShakeDetector {
    /// Force needed, in g (1g = normal gravity while the phone is still)
    var threshold: Double = 2.5
    /// Ignore new shakes for this many seconds after one is detected
    var cooldown: TimeInterval = 1.5

    private var lastShakeTime: TimeInterval = -.infinity

    init(threshold: Double = 2.5, cooldown: TimeInterval = 1.5) {
        self.threshold = threshold
        self.cooldown = cooldown
    }

    /// Total force of a reading: √(x² + y² + z²)
    static func magnitude(x: Double, y: Double, z: Double) -> Double {
        (x * x + y * y + z * z).squareRoot()
    }

    /// Feed in one accelerometer reading. Returns true when a shake happens.
    mutating func process(x: Double, y: Double, z: Double, timestamp: TimeInterval) -> Bool {
        let force = ShakeDetector.magnitude(x: x, y: y, z: z)
        guard force > threshold else { return false }
        guard timestamp - lastShakeTime >= cooldown else { return false }
        lastShakeTime = timestamp
        return true
    }
}

// MARK: - Karma

/// All the reputation ("Foodie Karma") rules in one place.
enum KarmaCalculator {
    static let startingKarma = 100
    static let pointsPerLevel = 300
    static let receiptVerifiedPoints = 200
    static let hostBonusPoints = 50
    static let ratingTablematePoints = 15

    /// Level 1 = 0–299, Level 2 = 300–599 ... (1,040 pts -> Level 4)
    static func level(for karma: Int) -> Int {
        max(karma, 0) / pointsPerLevel + 1
    }

    /// Points needed to reach the next level (1,040 -> 1,200)
    static func nextLevelTarget(for karma: Int) -> Int {
        level(for: karma) * pointsPerLevel
    }

    /// 0...1 progress through the current level (for the orange bar)
    static func levelProgress(for karma: Int) -> Double {
        let start = (level(for: karma) - 1) * pointsPerLevel
        return Double(max(karma, 0) - start) / Double(pointsPerLevel)
    }

    /// Named tiers shown on the profile ("Silver Gourmet")
    enum Tier: String, CaseIterable {
        case bronzeTaster = "Bronze Taster"
        case silverGourmet = "Silver Gourmet"
        case goldEpicurean = "Gold Epicurean"
        case platinumConcierge = "Platinum Concierge"

        var minimumKarma: Int {
            switch self {
            case .bronzeTaster: return 0
            case .silverGourmet: return 500
            case .goldEpicurean: return 1500
            case .platinumConcierge: return 3000
            }
        }
    }

    static func tier(for karma: Int) -> Tier {
        Tier.allCases.last(where: { karma >= $0.minimumKarma }) ?? .bronzeTaster
    }

    /// The tier after the current one (nil at the top tier)
    static func nextTier(after karma: Int) -> Tier? {
        Tier.allCases.first(where: { karma < $0.minimumKarma })
    }

    /// 0...1 progress towards the next tier
    static func tierProgress(for karma: Int) -> Double {
        let current = tier(for: karma)
        guard let next = nextTier(after: karma) else { return 1 }
        let span = Double(next.minimumKarma - current.minimumKarma)
        return Double(karma - current.minimumKarma) / span
    }

    /// Points earned for a verified receipt (hosts get a bonus).
    static func pointsForVerifiedMeal(isHost: Bool) -> Int {
        receiptVerifiedPoints + (isHost ? hostBonusPoints : 0)
    }
}

// MARK: - QR check-in token

/// The text stored inside the pass QR code.
/// Format:  SE|tableId|userId|seat|signature
/// The signature stops people from making fake passes by hand.
enum QRToken {
    private static let secret = "socialeats-checkin-v1"

    static func make(tableId: String, userId: String, seat: Int) -> String {
        let payload = "SE|\(tableId)|\(userId)|\(seat)"
        return payload + "|" + signature(for: payload)
    }

    /// Returns the parts if the token is genuine, otherwise nil.
    static func verify(_ token: String) -> (tableId: String, userId: String, seat: Int)? {
        let parts = token.split(separator: "|").map(String.init)
        guard parts.count == 5, parts[0] == "SE", let seat = Int(parts[3]) else { return nil }
        let payload = parts[0...3].joined(separator: "|")
        guard signature(for: payload) == parts[4] else { return nil }
        return (parts[1], parts[2], seat)
    }

    /// What goes INSIDE the QR picture: a link like
    /// socialeats://checkin?t=SE|table|user|seat|signature
    /// Because it's a link, the iPhone's normal Camera app can scan it and open SocialEats.
    static func checkInLink(for token: String) -> String {
        var link = URLComponents()
        link.scheme = "socialeats"
        link.host = "checkin"
        link.queryItems = [URLQueryItem(name: "t", value: token)]
        return link.string ?? token
    }

    /// Gets the token back out of whatever was scanned (the link, or a plain token).
    static func token(fromScanned text: String) -> String? {
        if let link = URLComponents(string: text), link.scheme == "socialeats", link.host == "checkin" {
            return link.queryItems?.first(where: { $0.name == "t" })?.value
        }
        return text.hasPrefix("SE|") ? text : nil
    }

    /// First 12 hex characters of SHA-256(payload + secret)
    private static func signature(for payload: String) -> String {
        let digest = SHA256.hash(data: Data((payload + secret).utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(12).description
    }
}

// MARK: - Check-in (scanning a guest's pass QR)

/// What the host sees after scanning a pass.
enum CheckInResult: Equatable {
    /// Genuine pass, and the guest really has this seat
    case valid(guestName: String, seat: Int, tableTitle: String, venueName: String, startTime: Date)
    /// Genuine pass, but this table isn't loaded on this phone (e.g. offline)
    case validButTableUnknown(seat: Int)
    /// Genuine pass, but the guest is no longer at the table (seat cancelled)
    case seatCancelled(tableTitle: String)
    /// Fake, damaged or not a SocialEats code
    case invalid
}

enum CheckIn {
    /// Checks a scanned QR: 1) is the signature genuine? 2) does the guest still have the seat?
    static func check(scannedText: String, tables: [CommunityTable]) -> CheckInResult {
        guard let token = QRToken.token(fromScanned: scannedText),
              let pass = QRToken.verify(token) else { return .invalid }

        guard let table = tables.first(where: { $0.id == pass.tableId }) else {
            return .validButTableUnknown(seat: pass.seat)
        }
        guard let index = table.attendeeIds.firstIndex(of: pass.userId) else {
            return .seatCancelled(tableTitle: table.title)
        }
        let name = index < table.attendeeNames.count ? table.attendeeNames[index] : "Guest"
        return .valid(guestName: name, seat: pass.seat, tableTitle: table.title,
                      venueName: table.venueName, startTime: table.startTime)
    }
}

// MARK: - Filtering

/// Options the user can filter tables by.
struct TableFilterOptions: Equatable {
    var category: TableCategory? = nil      // nil = "All"
    var dietaryTags: [DietaryTag] = []      // table must support ALL of these
    var radiusKm: Double? = nil             // nil = any distance
    var searchText: String = ""
    var hideFull: Bool = false
}

enum TableFilter {

    /// Filters and sorts tables (nearest first, then soonest).
    static func apply(_ options: TableFilterOptions,
                      to tables: [CommunityTable],
                      userLocation: CLLocation?,
                      now: Date = Date()) -> [CommunityTable] {
        let query = options.searchText.trimmingCharacters(in: .whitespaces).lowercased()

        let filtered = tables.filter { table in
            // Hide meetups that finished long ago
            if table.startTime.addingTimeInterval(2 * 60 * 60) < now { return false }
            if options.hideFull && table.isFull { return false }
            if let category = options.category, table.category != category { return false }

            // Dietary: allergy tags are ignored here (they are warnings, not filters)
            let required = options.dietaryTags.filter { !$0.isAllergy }
            if !required.allSatisfy({ table.dietaryTags.contains($0) }) { return false }

            if let radius = options.radiusKm,
               let distance = table.distance(from: userLocation),
               distance > radius * 1000 { return false }

            if !query.isEmpty {
                let haystack = [table.title, table.venueName, table.category.title, table.about]
                    .joined(separator: " ").lowercased()
                if !haystack.contains(query) { return false }
            }
            return true
        }

        return filtered.sorted { a, b in
            let da = a.distance(from: userLocation) ?? .greatestFiniteMagnitude
            let db = b.distance(from: userLocation) ?? .greatestFiniteMagnitude
            if da != db { return da < db }
            return a.startTime < b.startTime
        }
    }

    /// Picks a random open table for Shake to Match.
    /// Tables that match the user's favourite cuisines get picked first.
    static func randomMatch(from tables: [CommunityTable],
                            userId: String?,
                            favouriteCategories: [TableCategory],
                            userLocation: CLLocation?,
                            radiusKm: Double,
                            dietaryTags: [DietaryTag] = [],
                            excluding excludedId: String? = nil) -> CommunityTable? {
        var options = TableFilterOptions()
        options.radiusKm = radiusKm
        options.dietaryTags = dietaryTags      // Settings dietary chips are global filters
        options.hideFull = true
        let candidates = apply(options, to: tables, userLocation: userLocation)
            .filter { !$0.isAttending(userId) && $0.id != excludedId }

        let favourites = candidates.filter { favouriteCategories.contains($0.category) }
        return (favourites.isEmpty ? candidates : favourites).randomElement()
    }
}

// MARK: - Distance text

enum DistanceText {
    /// Average walking speed: about 80 metres per minute
    static let walkingMetresPerMinute = 80.0

    /// 400 -> "400m", 1100 -> "1.1km"
    static func short(_ metres: CLLocationDistance?) -> String {
        guard let metres else { return "Nearby" }
        if metres < 1000 { return "\(Int((metres / 10).rounded() * 10))m" }
        return String(format: "%.1fkm", metres / 1000)
    }

    /// "400m away"
    static func away(_ metres: CLLocationDistance?) -> String {
        guard metres != nil else { return "Nearby" }
        return short(metres) + " away"
    }

    /// 350 -> "4 min walk"
    static func walkMinutes(_ metres: CLLocationDistance?) -> String {
        guard let metres else { return "" }
        let minutes = max(1, Int((metres / walkingMetresPerMinute).rounded()))
        return "\(minutes) min walk"
    }
}
