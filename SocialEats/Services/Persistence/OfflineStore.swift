//  OfflineStore.swift

import Foundation
import CoreData

protocol OfflineStoring: AnyObject {
    func saveReservation(_ reservation: Reservation)
    func reservations(for userId: String) -> [Reservation]
    func reservation(tableId: String, userId: String) -> Reservation?
    func deleteReservation(tableId: String, userId: String)
    func markVerified(tableId: String, userId: String)

    func cacheTables(_ tables: [CommunityTable])
    func cachedTables() -> [CommunityTable]
}

final class CoreDataOfflineStore: OfflineStoring {
    private let persistence: PersistenceController
    private var context: NSManagedObjectContext { persistence.context }

    init(persistence: PersistenceController) {
        self.persistence = persistence
    }

    func saveReservation(_ reservation: Reservation) {
        let object = fetchReservationObject(tableId: reservation.tableId, userId: reservation.userId)
            ?? CDReservation(context: context)

        object.tableId = reservation.tableId
        object.userId = reservation.userId
        object.title = reservation.title
        object.venueName = reservation.venueName
        object.venueAddress = reservation.venueAddress
        object.hostName = reservation.hostName
        object.startTime = reservation.startTime
        object.seatNumber = Int64(reservation.seatNumber)
        object.tableNumber = Int64(reservation.tableNumber)
        object.qrToken = reservation.qrToken
        object.latitude = reservation.latitude
        object.longitude = reservation.longitude
        object.isVerified = reservation.isVerified
        object.savedAt = reservation.savedAt
        persistence.save()
    }

    func reservations(for userId: String) -> [Reservation] {
        let request = NSFetchRequest<CDReservation>(entityName: "CDReservation")
        request.predicate = NSPredicate(format: "userId == %@", userId)
        request.sortDescriptors = [NSSortDescriptor(key: "startTime", ascending: true)]
        let objects = (try? context.fetch(request)) ?? []
        return objects.map(Self.toReservation)
    }

    func reservation(tableId: String, userId: String) -> Reservation? {
        fetchReservationObject(tableId: tableId, userId: userId).map(Self.toReservation)
    }

    func deleteReservation(tableId: String, userId: String) {
        guard let object = fetchReservationObject(tableId: tableId, userId: userId) else { return }
        context.delete(object)
        persistence.save()
    }

    func markVerified(tableId: String, userId: String) {
        guard let object = fetchReservationObject(tableId: tableId, userId: userId) else { return }
        object.isVerified = true
        persistence.save()
    }

    private func fetchReservationObject(tableId: String, userId: String) -> CDReservation? {
        let request = NSFetchRequest<CDReservation>(entityName: "CDReservation")
        request.predicate = NSPredicate(format: "tableId == %@ AND userId == %@", tableId, userId)
        request.fetchLimit = 1
        return try? context.fetch(request).first
    }

    private static func toReservation(_ object: CDReservation) -> Reservation {
        Reservation(
            tableId: object.tableId,
            userId: object.userId,
            title: object.title,
            venueName: object.venueName,
            venueAddress: object.venueAddress,
            hostName: object.hostName,
            startTime: object.startTime,
            seatNumber: Int(object.seatNumber),
            tableNumber: Int(object.tableNumber),
            qrToken: object.qrToken,
            latitude: object.latitude,
            longitude: object.longitude,
            isVerified: object.isVerified,
            savedAt: object.savedAt
        )
    }

    func cacheTables(_ tables: [CommunityTable]) {
        let deleteRequest = NSFetchRequest<CDCachedTable>(entityName: "CDCachedTable")
        let oldRows = (try? context.fetch(deleteRequest)) ?? []
        oldRows.forEach { context.delete($0) }
        persistence.save()  

        let encoder = JSONEncoder()
        for table in tables {
            guard let data = try? encoder.encode(table) else { continue }
            let row = CDCachedTable(context: context)
            row.tableId = table.id
            row.payload = data
            row.updatedAt = Date()
        }
        persistence.save()
    }

    func cachedTables() -> [CommunityTable] {
        let request = NSFetchRequest<CDCachedTable>(entityName: "CDCachedTable")
        let rows = (try? context.fetch(request)) ?? []
        let decoder = JSONDecoder()
        return rows
            .compactMap { try? decoder.decode(CommunityTable.self, from: $0.payload) }
            .sorted { $0.startTime < $1.startTime }
    }
}
