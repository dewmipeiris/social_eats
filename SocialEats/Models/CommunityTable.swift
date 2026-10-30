//  CommunityTable.swift

import Foundation
import CoreLocation

struct CommunityTable: Identifiable, Equatable, Hashable, Codable {
    var id: String
    var title: String
    var about: String
    var venueName: String
    var venueAddress: String
    var category: TableCategory

    var hostId: String
    var hostName: String
    var hostRating: Double
    var hostTablesHosted: Int

    var startTime: Date
    var latitude: Double
    var longitude: Double

    var capacity: Int
    var attendeeIds: [String]
    var attendeeNames: [String]

    var dietaryTags: [DietaryTag]
    var pricePerPerson: Double
    var perk: String?
    var tableNumber: Int
    var createdAt: Date


    var seatsFilled: Int { attendeeIds.count }
    var seatsLeft: Int { max(capacity - seatsFilled, 0) }
    var isFull: Bool { seatsFilled >= capacity }

    var seatSummary: String { "\(seatsFilled)/\(capacity) Seats Filled" }

    func isAttending(_ userId: String?) -> Bool {
        guard let userId else { return false }
        return attendeeIds.contains(userId)
    }

    func isHost(_ userId: String?) -> Bool {
        hostId == userId
    }

    func seatNumber(for userId: String) -> Int? {
        guard let index = attendeeIds.firstIndex(of: userId) else { return nil }
        return index + 1
    }

    func joinBlockReason(for userId: String, now: Date = Date()) -> TableJoinError? {
        if attendeeIds.contains(userId) { return .alreadyJoined }
        if isFull { return .tableFull }
        if now > startTime.addingTimeInterval(30 * 60) { return .tableExpired }
        return nil
    }

    func adding(userId: String, name: String) throws -> CommunityTable {
        if let reason = joinBlockReason(for: userId) { throw reason }
        var copy = self
        copy.attendeeIds.append(userId)
        copy.attendeeNames.append(name)
        return copy
    }

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

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var location: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
    
    func distance(from userLocation: CLLocation?) -> CLLocationDistance? {
        guard let userLocation else { return nil }
        return userLocation.distance(from: location)
    }
}

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
