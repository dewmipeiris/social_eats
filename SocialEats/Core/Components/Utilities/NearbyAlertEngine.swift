//  NearbyAlertEngine.swift

import Foundation
import CoreLocation

enum NearbyAlertEngine {

    static func tablesToAlert(_ tables: [CommunityTable],
                              createdAfter: Date,
                              alreadyAlerted: Set<String>,
                              currentUserId: String?,
                              userLocation: CLLocation?,
                              radiusKm: Double,
                              now: Date = Date()) -> [CommunityTable] {
        // Without a location we can't know if a table is within the radius
        guard let userLocation else { return [] }
        let radiusMetres = radiusKm * 1000

        return tables.filter { table in
            table.createdAt > createdAfter
                && !alreadyAlerted.contains(table.id)
                && table.hostId != currentUserId           // not my own table
                && !table.isAttending(currentUserId)       // not a table I already joined
                && !table.isFull
                && table.startTime > now                   // hasn't started yet
                && (table.distance(from: userLocation) ?? .greatestFiniteMagnitude) <= radiusMetres
        }
    }
}

final class NearbyAlertHistory {
    private let defaults: UserDefaults
    private let lastCheckKey = "nearbyAlerts.lastCheck"
    private let alertedKey = "nearbyAlerts.alertedIds"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // Very first launch: start "now" so the user isn't flooded with old tables
        if defaults.object(forKey: lastCheckKey) == nil {
            defaults.set(Date(), forKey: lastCheckKey)
        }
    }

    var lastCheck: Date {
        defaults.object(forKey: lastCheckKey) as? Date ?? Date()
    }

    var alertedIds: Set<String> {
        Set(defaults.stringArray(forKey: alertedKey) ?? [])
    }
    
    func record(alerted ids: [String], checkedAt date: Date = Date()) {
        var all = defaults.stringArray(forKey: alertedKey) ?? []
        all.append(contentsOf: ids)
        defaults.set(Array(all.suffix(200)), forKey: alertedKey)
        defaults.set(date, forKey: lastCheckKey)
    }
}
