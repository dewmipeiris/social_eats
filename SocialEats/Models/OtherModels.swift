//  OtherModels.swift

import Foundation

struct Reservation: Identifiable, Equatable, Hashable {
    var id: String { tableId }
    var tableId: String
    var userId: String
    var title: String
    var venueName: String
    var venueAddress: String
    var hostName: String
    var startTime: Date
    var seatNumber: Int
    var tableNumber: Int
    var qrToken: String
    var latitude: Double
    var longitude: Double
    var isVerified: Bool
    var savedAt: Date

    static func make(from table: CommunityTable, userId: String) -> Reservation {
        let seat = table.seatNumber(for: userId) ?? table.seatsFilled
        return Reservation(
            tableId: table.id,
            userId: userId,
            title: table.title,
            venueName: table.venueName,
            venueAddress: table.venueAddress,
            hostName: table.hostName,
            startTime: table.startTime,
            seatNumber: seat,
            tableNumber: table.tableNumber,
            qrToken: QRToken.make(tableId: table.id, userId: userId, seat: seat),
            latitude: table.latitude,
            longitude: table.longitude,
            isVerified: false,
            savedAt: Date()
        )
    }

    var isUpcomingOrActive: Bool {
        startTime.addingTimeInterval(3 * 60 * 60) > Date()
    }
}

struct ChatMessage: Identifiable, Equatable {
    enum Kind: String {
        case text
        case system
    }

    var id: String
    var senderId: String
    var senderName: String
    var text: String
    var sentAt: Date
    var isFromHost: Bool
    var kind: Kind = .text
    var isPending: Bool = false
}

struct ActivityItem: Identifiable, Equatable {
    enum Kind: String {
        case seatConfirmed
        case karmaUnlocked
        case tableInvite
        case meetupReminder
        case newTableNearby
    }

    var id: String
    var kind: Kind
    var title: String
    var body: String
    var createdAt: Date
    var tableId: String?
    var points: Int?
    var isRead: Bool = false

    var systemImage: String {
        switch kind {
        case .seatConfirmed: return "checkmark.seal.fill"
        case .karmaUnlocked: return "star.fill"
        case .tableInvite: return "person.2.fill"
        case .meetupReminder: return "clock"
        case .newTableNearby: return "mappin.and.ellipse"
        }
    }
}

struct ReceiptScanResult: Equatable {
    var restaurantName: String?
    var total: Double?
    var currencyCode: String
    var timestamp: Date?
    var rawLines: [String]

    var completeness: Double {
        var score = 0.0
        if restaurantName != nil { score += 0.4 }
        if total != nil { score += 0.4 }
        if timestamp != nil { score += 0.2 }
        return score
    }
}

enum ReceiptValidation: Equatable {
    case verified(matchScore: Double)
    case venueMismatch(found: String?)
    case missingTotal
    case outsideTimeWindow

    var isVerified: Bool {
        if case .verified = self { return true }
        return false
    }

    var message: String {
        switch self {
        case .verified(let score):
            return "Receipt matched (\(Int(score * 100))% venue match)"
        case .venueMismatch(let found):
            if let found { return "This receipt is from \"\(found)\", not your table's venue." }
            return "We couldn't read the restaurant name. Try again with better lighting."
        case .missingTotal:
            return "We couldn't find the bill total. Make sure the TOTAL line is visible."
        case .outsideTimeWindow:
            return "This receipt's time doesn't match your meetup."
        }
    }
}
