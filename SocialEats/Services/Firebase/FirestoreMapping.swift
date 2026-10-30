//  FirestoreMapping.swift

import Foundation
import FirebaseFirestore

enum FirestorePath {
    static let users = "users"
    static let tables = "tables"
    static let messages = "messages"
    static let activity = "activity"
    static let receipts = "receipts"
    static let ratings = "ratings"
    static let rsvps = "rsvps"
}

func firestoreValue<T>(_ value: T?) -> Any {
    if let value { return value }
    return NSNull()
}

private extension Dictionary where Key == String, Value == Any {
    func string(_ key: String, default value: String = "") -> String { self[key] as? String ?? value }
    func int(_ key: String, default value: Int = 0) -> Int { (self[key] as? NSNumber)?.intValue ?? value }
    func double(_ key: String, default value: Double = 0) -> Double { (self[key] as? NSNumber)?.doubleValue ?? value }
    func strings(_ key: String) -> [String] { self[key] as? [String] ?? [] }
    func date(_ key: String) -> Date { (self[key] as? Timestamp)?.dateValue() ?? Date() }

    func enums<T: RawRepresentable>(_ key: String) -> [T] where T.RawValue == String {
        strings(key).compactMap { T(rawValue: $0) }
    }
}

extension AppUser {
    init?(id: String, data: [String: Any]?) {
        guard let data else { return nil }
        self.init(
            id: id,
            displayName: data.string("displayName", default: "Foodie"),
            username: data.string("username", default: "@foodie"),
            phoneNumber: data["phoneNumber"] as? String,
            email: data["email"] as? String,
            karma: data.int("karma", default: KarmaCalculator.startingKarma),
            mealsShared: data.int("mealsShared"),
            newFriends: data.int("newFriends"),
            tablesHosted: data.int("tablesHosted"),
            hostRating: data.double("hostRating", default: 5),
            dietaryTags: data.enums("dietaryTags"),
            ambiences: data.enums("ambiences"),
            cuisines: data.enums("cuisines"),
            diningStyle: DiningStyle(rawValue: data.string("diningStyle")) ?? .smallGroup,
            joinedAt: data.date("joinedAt")
        )
    }

    var firestoreData: [String: Any] {
        [
            "displayName": displayName,
            "username": username,
            "phoneNumber": firestoreValue(phoneNumber),
            "email": firestoreValue(email),
            "karma": karma,
            "mealsShared": mealsShared,
            "newFriends": newFriends,
            "tablesHosted": tablesHosted,
            "hostRating": hostRating,
            "dietaryTags": dietaryTags.map(\.rawValue),
            "ambiences": ambiences.map(\.rawValue),
            "cuisines": cuisines.map(\.rawValue),
            "diningStyle": diningStyle.rawValue,
            "joinedAt": Timestamp(date: joinedAt)
        ]
    }
}

extension CommunityTable {
    init?(id: String, data: [String: Any]?) {
        guard let data, let category = TableCategory(rawValue: data.string("category")) else { return nil }
        self.init(
            id: id,
            title: data.string("title"),
            about: data.string("about"),
            venueName: data.string("venueName"),
            venueAddress: data.string("venueAddress"),
            category: category,
            hostId: data.string("hostId"),
            hostName: data.string("hostName"),
            hostRating: data.double("hostRating", default: 5),
            hostTablesHosted: data.int("hostTablesHosted"),
            startTime: data.date("startTime"),
            latitude: data.double("latitude"),
            longitude: data.double("longitude"),
            capacity: data.int("capacity", default: 4),
            attendeeIds: data.strings("attendeeIds"),
            attendeeNames: data.strings("attendeeNames"),
            dietaryTags: data.enums("dietaryTags"),
            pricePerPerson: data.double("pricePerPerson"),
            perk: data["perk"] as? String,
            tableNumber: data.int("tableNumber", default: 100),
            createdAt: data.date("createdAt")
        )
    }

    var firestoreData: [String: Any] {
        [
            "title": title,
            "about": about,
            "venueName": venueName,
            "venueAddress": venueAddress,
            "category": category.rawValue,
            "hostId": hostId,
            "hostName": hostName,
            "hostRating": hostRating,
            "hostTablesHosted": hostTablesHosted,
            "startTime": Timestamp(date: startTime),
            "latitude": latitude,
            "longitude": longitude,
            "capacity": capacity,
            "attendeeIds": attendeeIds,
            "attendeeNames": attendeeNames,
            "seatsFilled": attendeeIds.count,       // stored too, handy for queries
            "dietaryTags": dietaryTags.map(\.rawValue),
            "pricePerPerson": pricePerPerson,
            "perk": firestoreValue(perk),
            "tableNumber": tableNumber,
            "createdAt": Timestamp(date: createdAt),
            "isActive": true
        ]
    }
}

extension ChatMessage {
    init?(id: String, data: [String: Any]) {
        self.init(
            id: id,
            senderId: data.string("senderId"),
            senderName: data.string("senderName"),
            text: data.string("text"),
            // While a message is still uploading its server time is nil -> use now
            sentAt: (data["sentAt"] as? Timestamp)?.dateValue() ?? Date(),
            isFromHost: data["isFromHost"] as? Bool ?? false,
            kind: Kind(rawValue: data.string("kind")) ?? .text
        )
    }

    var firestoreData: [String: Any] {
        [
            "senderId": senderId,
            "senderName": senderName,
            "text": text,
            "sentAt": FieldValue.serverTimestamp(),
            "isFromHost": isFromHost,
            "kind": kind.rawValue
        ]
    }
}

extension ActivityItem {
    init?(id: String, data: [String: Any]) {
        guard let kind = Kind(rawValue: data.string("kind")) else { return nil }
        self.init(
            id: id,
            kind: kind,
            title: data.string("title"),
            body: data.string("body"),
            createdAt: data.date("createdAt"),
            tableId: data["tableId"] as? String,
            points: data["points"] as? Int,
            isRead: data["isRead"] as? Bool ?? false
        )
    }

    var firestoreData: [String: Any] {
        [
            "kind": kind.rawValue,
            "title": title,
            "body": body,
            "createdAt": Timestamp(date: createdAt),
            "tableId": firestoreValue(tableId),
            "points": firestoreValue(points),
            "isRead": isRead
        ]
    }
}

struct FirestoreListenerToken: ListenerToken {
    let registration: ListenerRegistration
    func remove() { registration.remove() }
}
