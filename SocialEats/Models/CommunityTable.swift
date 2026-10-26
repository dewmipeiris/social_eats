//
//  CommunityTable.swift
//  SocialEats
//
//  An "Open Community Table" — a small group meal at a local venue.
//  Saved in Firestore at  tables/{id}
//

import Foundation
import CoreLocation

struct CommunityTable: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var title: String
    var about: String
    var venueName: String
    var venueAddress: String
    var category: TableCategory

    // Host details
    var hostId: String
    var hostName: String
    var hostRating: Double
    var hostTablesHosted: Int

    // When and where
    var startTime: Date
    var latitude: Double
    var longitude: Double

    // Seats (capacity logic — proposal Feature 9)
    var capacity: Int
    var attendeeIds: [String]
    var attendeeNames: [String]

    // Extra info shown on cards
    var dietaryTags: [DietaryTag]
    var pricePerPerson: Double
    var perk: String?            // e.g. "20% Student Discount"
    var tableNumber: Int         // e.g. Table #402
    var createdAt: Date

    // MARK: - Seat helpers

    var seatsFilled: Int { attendeeIds.count }
    var seatsLeft: Int { max(capacity - seatsFilled, 0) }
    var isFull: Bool { seatsFilled >= capacity }

    /// "3/4 Seats Filled"
    var seatSummary: String { "\(seatsFilled)/\(capacity) Seats Filled" }

    func isAttending(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return attendeeIds.contains(userId)
    }

    func isHost(_ userId: String?) -> Bool {
        hostId == userId
    }

    /// Seat number for a member (host is always Seat #1).
    func seatNumber(for userId: String) -> Int? {
        guard let index = attendeeIds.firstIndex(of: userId) else { return nil }
        return index + 1
    }

    /// Checks whether a user is allowed to take a seat.
    /// Returns `nil` when OK, or the reason they can't join.
    func joinBlockReason(for userId: String, now: Date = Date()) -> TableJoinError? {
        if attendeeIds.contains(userId) { return .alreadyJoined }
        if isFull { return .tableFull }
        // Allow joining until 30 minutes after the start time
        if now > startTime.addingTimeInterval(30 * 60) { return .tableExpired }
        return nil
    }

    /// Returns a copy with the user added (used by the mock service & tests;
    /// the real Firestore version does the same thing in a transaction).
    func adding(userId: String, name: String) throws -> CommunityTable {
        if let reason = joinBlockReason(for: userId) { throw reason }
        var copy = self
        copy.attendeeIds.append(userId)
        copy.attendeeNames.append(name)
        return copy
    }

    /// Returns a copy with the user removed. The host cannot leave their own table.
    func removing(userId: String) throws -> CommunityTable {
        if userId == hostId { throw TableJoinError.hostCannotLeave }
        guard let index = attendeeIds.firstIndex(of: userId) else { return self }
        var copy = self
        copy.attendeeIds.remove(at: index)
        if index < copy.attendeeNames.count {
            copy.attendeeNames.remove(at: index)
        }
        return copy
    }

    // MARK: - Location helpers

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }

    /// Distance in metres from the user (nil if we don't know where they are).
    func distance(from userLocation: CLLocation?) -> CLLocationDistance? {
        guard let userLocation else { return nil }
        return userLocation.distance(from: location)
    }
}

/// Reasons a seat can't be taken. Shown to the user as alerts.
enum TableJoinError: LocalizedError, Equatable {
    case tableFull
    case alreadyJoined
    case tableExpired
    case hostCannotLeave
    case notFound

    var errorDescription: String? {
        switch self {
        case .tableFull: return "Sorry, this table just filled up. Shake to find another one!"
        case .alreadyJoined: return "You already have a seat at this table."
        case .tableExpired: return "This meetup has already started."
        case .hostCannotLeave: return "Hosts can't leave their own table."
        case .notFound: return "This table no longer exists."
        }
    }
}
