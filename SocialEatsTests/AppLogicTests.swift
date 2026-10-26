//
//  AppLogicTests.swift
//  SocialEatsTests
//
//  Shake detection (Core Motion maths), karma levels, QR pass tokens,
//  seat capacity rules and table filtering.
//

import Testing
import Foundation
import CoreLocation
@testable import SocialEats

// MARK: - Shake to Match

@Suite("Shake detector (Core Motion)")
struct ShakeDetectorTests {

    @Test("Force is √(x² + y² + z²)")
    func magnitude() {
        #expect(ShakeDetector.magnitude(x: 3, y: 4, z: 0) == 5)
    }

    @Test("Phone lying still (1g) is not a shake")
    func stillPhone() {
        var detector = ShakeDetector()
        #expect(detector.process(x: 0, y: 0, z: -1, timestamp: 0) == false)
    }

    @Test("A hard shake above 2.5g is detected")
    func hardShake() {
        var detector = ShakeDetector()
        #expect(detector.process(x: 2.0, y: 1.8, z: 1.0, timestamp: 0))
    }

    @Test("Second shake inside the cooldown is ignored, after cooldown it counts")
    func cooldown() {
        var detector = ShakeDetector(threshold: 2.5, cooldown: 1.5)
        #expect(detector.process(x: 3, y: 0, z: 0, timestamp: 10.0))
        #expect(detector.process(x: 3, y: 0, z: 0, timestamp: 10.5) == false)
        #expect(detector.process(x: 3, y: 0, z: 0, timestamp: 11.6))
    }
}

// MARK: - Karma

@Suite("Karma levels and tiers")
struct KarmaCalculatorTests {

    @Test("1,040 karma is Level 4 heading to 1,200 (matches the prototype)")
    func prototypeExample() {
        #expect(KarmaCalculator.level(for: 1040) == 4)
        #expect(KarmaCalculator.nextLevelTarget(for: 1040) == 1200)
        #expect(abs(KarmaCalculator.levelProgress(for: 1040) - 140.0 / 300.0) < 0.0001)
    }

    @Test("Tier boundaries", arguments: [
        (0, KarmaCalculator.Tier.bronzeTaster),
        (499, KarmaCalculator.Tier.bronzeTaster),
        (500, KarmaCalculator.Tier.silverGourmet),
        (1450, KarmaCalculator.Tier.silverGourmet),
        (1500, KarmaCalculator.Tier.goldEpicurean),
        (5000, KarmaCalculator.Tier.platinumConcierge)
    ])
    func tiers(karma: Int, expected: KarmaCalculator.Tier) {
        #expect(KarmaCalculator.tier(for: karma) == expected)
    }

    @Test("Top tier has no next tier and full progress")
    func topTier() {
        #expect(KarmaCalculator.nextTier(after: 4000) == nil)
        #expect(KarmaCalculator.tierProgress(for: 4000) == 1)
    }

    @Test("Hosts earn a bonus for verified meals")
    func hostBonus() {
        #expect(KarmaCalculator.pointsForVerifiedMeal(isHost: false) == 200)
        #expect(KarmaCalculator.pointsForVerifiedMeal(isHost: true) == 250)
    }

    @Test("Negative karma never breaks the level maths")
    func negativeKarma() {
        #expect(KarmaCalculator.level(for: -50) == 1)
    }
}

// MARK: - QR tokens

@Suite("Offline pass QR token")
struct QRTokenTests {

    @Test("A genuine token can be verified and read back")
    func roundTrip() throws {
        let token = QRToken.make(tableId: "t-taco", userId: "u-1", seat: 3)
        let parts = try #require(QRToken.verify(token))
        #expect(parts.tableId == "t-taco")
        #expect(parts.userId == "u-1")
        #expect(parts.seat == 3)
    }

    @Test("Changing the seat number breaks the signature")
    func tamperedToken() {
        let token = QRToken.make(tableId: "t-taco", userId: "u-1", seat: 3)
        let forged = token.replacingOccurrences(of: "|3|", with: "|1|")
        #expect(QRToken.verify(forged) == nil)
    }

    @Test("Random text is not a valid token")
    func garbage() {
        #expect(QRToken.verify("hello world") == nil)
    }

    @Test("The QR link (for the iPhone Camera app) gives the same token back")
    func linkRoundTrip() {
        let token = QRToken.make(tableId: "t-taco", userId: "u-1", seat: 3)
        let link = QRToken.checkInLink(for: token)
        #expect(link.hasPrefix("socialeats://checkin"))
        #expect(QRToken.token(fromScanned: link) == token)
    }
}

// MARK: - Check-in (host scans a guest's pass)

@Suite("Pass check-in")
struct CheckInTests {

    let table = SampleData.tables()[0]    // host + 2 guests

    @Test("A real guest's pass checks in with their name and seat")
    func validGuest() throws {
        let guestId = try #require(table.attendeeIds.last)
        let seat = table.attendeeIds.count
        let link = QRToken.checkInLink(for: QRToken.make(tableId: table.id, userId: guestId, seat: seat))

        let result = CheckIn.check(scannedText: link, tables: [table])
        guard case .valid(let name, let seatNumber, _, _, _) = result else {
            Issue.record("Expected a valid check-in, got \(result)")
            return
        }
        #expect(name == table.attendeeNames.last)
        #expect(seatNumber == seat)
    }

    @Test("A pass for someone who isn't at the table shows 'seat cancelled'")
    func cancelledSeat() {
        let link = QRToken.checkInLink(for: QRToken.make(tableId: table.id, userId: "left-already", seat: 4))
        #expect(CheckIn.check(scannedText: link, tables: [table]) == .seatCancelled(tableTitle: table.title))
    }

    @Test("A random QR code is rejected")
    func randomCode() {
        #expect(CheckIn.check(scannedText: "https://example.com", tables: [table]) == .invalid)
    }
}

// MARK: - Seat capacity (Feature 9)

@Suite("Community table seat logic")
struct CommunityTableTests {

    let table = SampleData.tables()[0]    // 4 seats, 3 taken (host + 2 guests)

    @Test("Seat counts")
    func seatCounts() {
        #expect(table.capacity == 4)
        #expect(table.seatsFilled == 3)
        #expect(table.seatsLeft == 1)
        #expect(!table.isFull)
        #expect(table.seatSummary == "3/4 Seats Filled")
    }

    @Test("Joining takes the next seat number")
    func joinAssignsSeat() throws {
        let joined = try table.adding(userId: "me", name: "Me")
        #expect(joined.isFull)
        #expect(joined.seatNumber(for: "me") == 4)
        #expect(joined.seatNumber(for: table.hostId) == 1)     // host is always Seat #1
    }

    @Test("Cannot join a full table")
    func fullTable() throws {
        let full = try table.adding(userId: "me", name: "Me")
        #expect(throws: TableJoinError.tableFull) {
            try full.adding(userId: "someone-else", name: "X")
        }
    }

    @Test("Cannot join the same table twice")
    func duplicateJoin() {
        #expect(throws: TableJoinError.alreadyJoined) {
            try table.adding(userId: table.hostId, name: "Host")
        }
    }

    @Test("Cannot join a meetup that started over 30 minutes ago")
    func expired() {
        var old = table
        old.startTime = Date().addingTimeInterval(-60 * 60)
        #expect(old.joinBlockReason(for: "me") == .tableExpired)
    }

    @Test("Leaving frees the seat, but the host can't leave")
    func leaving() throws {
        let guestId = table.attendeeIds[1]
        let after = try table.removing(userId: guestId)
        #expect(after.seatsFilled == 2)
        #expect(after.attendeeNames.count == 2)
        #expect(throws: TableJoinError.hostCannotLeave) {
            try table.removing(userId: table.hostId)
        }
    }

    @Test("Reservation copies the right seat and a valid QR token")
    func reservationFromTable() throws {
        let joined = try table.adding(userId: "me", name: "Me")
        let reservation = Reservation.make(from: joined, userId: "me")
        #expect(reservation.seatNumber == 4)
        #expect(reservation.tableNumber == table.tableNumber)
        #expect(QRToken.verify(reservation.qrToken)?.seat == 4)
    }
}

// MARK: - Filtering

@Suite("Table filtering & matching")
struct TableFilterTests {

    let center = SampleData.defaultCenter
    var userLocation: CLLocation { CLLocation(latitude: center.latitude, longitude: center.longitude) }
    var tables: [CommunityTable] { SampleData.tables(around: center) }

    @Test("Category filter keeps only that category")
    func category() {
        var options = TableFilterOptions()
        options.category = .sushi
        let result = TableFilter.apply(options, to: tables, userLocation: userLocation)
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.category == .sushi })
    }

    @Test("Dietary filter requires the tag, but allergies are not used as filters")
    func dietary() {
        var options = TableFilterOptions()
        options.dietaryTags = [.vegan, .nutAllergy]
        let result = TableFilter.apply(options, to: tables, userLocation: userLocation)
        #expect(!result.isEmpty)
        #expect(result.allSatisfy { $0.dietaryTags.contains(.vegan) })
    }

    @Test("Radius filter removes far tables")
    func radius() {
        var options = TableFilterOptions()
        options.radiusKm = 0.5
        let result = TableFilter.apply(options, to: tables, userLocation: userLocation)
        #expect(result.allSatisfy { ($0.distance(from: userLocation) ?? 0) <= 500 })
        #expect(result.count < tables.count)
    }

    @Test("Results are sorted nearest first")
    func sorted() {
        let result = TableFilter.apply(TableFilterOptions(), to: tables, userLocation: userLocation)
        let distances = result.compactMap { $0.distance(from: userLocation) }
        #expect(distances == distances.sorted())
    }

    @Test("Search text matches title, venue or category")
    func search() {
        var options = TableFilterOptions()
        options.searchText = "matsuya"
        let result = TableFilter.apply(options, to: tables, userLocation: userLocation)
        #expect(result.map(\.venueName) == ["Matsuya Kitchen"])
    }

    @Test("Finished meetups are hidden")
    func hidesOld() {
        var old = tables[0]
        old.startTime = Date().addingTimeInterval(-5 * 60 * 60)
        let result = TableFilter.apply(TableFilterOptions(), to: [old], userLocation: nil)
        #expect(result.isEmpty)
    }

    @Test("Shake match never picks a full table or one I'm already at")
    func randomMatch() {
        let all = tables
        let myTableId = all[0].id
        for _ in 0..<20 {
            let match = TableFilter.randomMatch(from: all, userId: all[0].hostId, favouriteCategories: [],
                                                userLocation: userLocation, radiusKm: 5)
            #expect(match != nil)
            #expect(match?.id != myTableId)
            #expect(match?.isFull == false)
        }
    }

    @Test("Shake match prefers favourite cuisines")
    func favourites() {
        let match = TableFilter.randomMatch(from: tables, userId: "me", favouriteCategories: [.ramen],
                                            userLocation: userLocation, radiusKm: 5)
        #expect(match?.category == .ramen)
    }

    @Test("Distance text formats")
    func distanceText() {
        #expect(DistanceText.short(404) == "400m")
        #expect(DistanceText.short(1100) == "1.1km")
        #expect(DistanceText.walkMinutes(350) == "4 min walk")
        #expect(DistanceText.away(nil) == "Nearby")
    }
}

// MARK: - Nearby alerts (Feature 5)

@Suite("New-table-nearby alert rules")
struct NearbyAlertEngineTests {

    let center = SampleData.defaultCenter
    var here: CLLocation { CLLocation(latitude: center.latitude, longitude: center.longitude) }
    let lastCheck = Date().addingTimeInterval(-10 * 60)

    /// A copy of a sample table that was "just created"
    func freshTable(_ index: Int, hostId: String = "someone") -> CommunityTable {
        var table = SampleData.tables(around: center)[index]
        table.createdAt = Date()
        table.hostId = hostId
        return table
    }

    @Test("A brand-new table inside the radius triggers an alert")
    func newTableInRadius() {
        let table = freshTable(5)           // ~280 m away
        let result = NearbyAlertEngine.tablesToAlert([table], createdAfter: lastCheck, alreadyAlerted: [],
                                                     currentUserId: "me", userLocation: here, radiusKm: 1)
        #expect(result.map(\.id) == [table.id])
    }

    @Test("Tables outside the radius, old tables and already-alerted tables are skipped")
    func skipped() {
        let far = freshTable(3)             // ~1.4 km away
        var old = freshTable(5)
        old.createdAt = Date().addingTimeInterval(-3 * 3600)
        let alerted = freshTable(0)

        let result = NearbyAlertEngine.tablesToAlert([far, old, alerted], createdAfter: lastCheck,
                                                     alreadyAlerted: [alerted.id], currentUserId: "me",
                                                     userLocation: here, radiusKm: 1)
        #expect(result.isEmpty)
    }

    @Test("My own tables and full tables never alert")
    func ownAndFull() {
        let mine = freshTable(5, hostId: "me")
        var full = freshTable(0)
        full.capacity = full.seatsFilled
        let result = NearbyAlertEngine.tablesToAlert([mine, full], createdAfter: lastCheck, alreadyAlerted: [],
                                                     currentUserId: "me", userLocation: here, radiusKm: 5)
        #expect(result.isEmpty)
    }

    @Test("Without a location we can't tell the distance, so no alert")
    func noLocation() {
        let result = NearbyAlertEngine.tablesToAlert([freshTable(5)], createdAfter: lastCheck, alreadyAlerted: [],
                                                     currentUserId: "me", userLocation: nil, radiusKm: 5)
        #expect(result.isEmpty)
    }

    @Test("History remembers alerted tables")
    func history() {
        let history = NearbyAlertHistory(defaults: UserDefaults(suiteName: "history-\(UUID().uuidString)")!)
        history.record(alerted: ["a", "b"])
        #expect(history.alertedIds == ["a", "b"])
        #expect(abs(history.lastCheck.timeIntervalSinceNow) < 5)
    }

    @Test("Shake to Match respects dietary filters")
    func shakeDietary() {
        let tables = SampleData.tables(around: center)
        for _ in 0..<10 {
            let match = TableFilter.randomMatch(from: tables, userId: "me", favouriteCategories: [],
                                                userLocation: here, radiusKm: 5, dietaryTags: [.vegan])
            #expect(match?.dietaryTags.contains(.vegan) == true)
        }
    }
}

// MARK: - Community Hub mutual interests (Feature 7)

@Suite("Tablemate mutual interests")
struct MutualInterestTests {

    @Test("Shared cuisines, vibes and diets are listed; allergies are private")
    @MainActor
    func mutual() {
        var me = SampleData.demoUser                  // pizza + ramen, cozy + tech, halal
        me.dietaryTags = [.halal, .nutAllergy]
        var them = SampleData.sampleMembers[1]        // Marcus: ramen + pizza, cozy + tech
        them.dietaryTags = [.halal, .nutAllergy]

        let shared = ChatViewModel.mutualInterests(me: me, them: them)
        #expect(shared.contains("Neapolitan Pizza"))
        #expect(shared.contains("Ramen & Noodles"))
        #expect(shared.contains("Chill & Cozy"))
        #expect(shared.contains("Halal"))
        #expect(!shared.contains("Nut Allergy"))
    }

    @Test("No profile for me means no mutual interests")
    @MainActor
    func noMe() {
        #expect(ChatViewModel.mutualInterests(me: nil, them: SampleData.sampleMembers[0]).isEmpty)
    }
}

