//  PersistenceController.swift

import Foundation
import CoreData

@objc(CDReservation)
final class CDReservation: NSManagedObject {
    @NSManaged var tableId: String
    @NSManaged var userId: String
    @NSManaged var title: String
    @NSManaged var venueName: String
    @NSManaged var venueAddress: String
    @NSManaged var hostName: String
    @NSManaged var startTime: Date
    @NSManaged var seatNumber: Int64
    @NSManaged var tableNumber: Int64
    @NSManaged var qrToken: String
    @NSManaged var latitude: Double
    @NSManaged var longitude: Double
    @NSManaged var isVerified: Bool
    @NSManaged var savedAt: Date
}

@objc(CDCachedTable)
final class CDCachedTable: NSManagedObject {
    @NSManaged var tableId: String
    @NSManaged var payload: Data
    @NSManaged var updatedAt: Date
}

enum SocialEatsModel {

    static let shared: NSManagedObjectModel = {
        let model = NSManagedObjectModel()

        func attribute(_ name: String, _ type: NSAttributeType, optional: Bool = false) -> NSAttributeDescription {
            let attribute = NSAttributeDescription()
            attribute.name = name
            attribute.attributeType = type
            attribute.isOptional = optional
            return attribute
        }

        let reservation = NSEntityDescription()
        reservation.name = "CDReservation"
        reservation.managedObjectClassName = NSStringFromClass(CDReservation.self)
        reservation.properties = [
            attribute("tableId", .stringAttributeType),
            attribute("userId", .stringAttributeType),
            attribute("title", .stringAttributeType),
            attribute("venueName", .stringAttributeType),
            attribute("venueAddress", .stringAttributeType),
            attribute("hostName", .stringAttributeType),
            attribute("startTime", .dateAttributeType),
            attribute("seatNumber", .integer64AttributeType),
            attribute("tableNumber", .integer64AttributeType),
            attribute("qrToken", .stringAttributeType),
            attribute("latitude", .doubleAttributeType),
            attribute("longitude", .doubleAttributeType),
            attribute("isVerified", .booleanAttributeType),
            attribute("savedAt", .dateAttributeType)
        ]

        reservation.uniquenessConstraints = [["tableId", "userId"]]

        let cachedTable = NSEntityDescription()
        cachedTable.name = "CDCachedTable"
        cachedTable.managedObjectClassName = NSStringFromClass(CDCachedTable.self)
        cachedTable.properties = [
            attribute("tableId", .stringAttributeType),
            attribute("payload", .binaryDataAttributeType),
            attribute("updatedAt", .dateAttributeType)
        ]
        cachedTable.uniquenessConstraints = [["tableId"]]

        model.entities = [reservation, cachedTable]
        return model
    }()
}


final class PersistenceController {

    let container: NSPersistentContainer

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "SocialEats", managedObjectModel: SocialEatsModel.shared)

        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }

        container.loadPersistentStores { _, error in
            if let error {
                print("❌ Core Data failed to load: \(error.localizedDescription)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
    }

    var context: NSManagedObjectContext { container.viewContext }

    func save() {
        guard context.hasChanges else { return }
        do {
            try context.save()
        } catch {
            print("❌ Core Data save error: \(error.localizedDescription)")
            context.rollback()
        }
    }
}
