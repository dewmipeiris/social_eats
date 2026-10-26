//
//  NearbyAlertEngine.swift
//  SocialEats
//
//  Proposal MVP Feature 5, step 2:
//  "When a host creates a table within the user's defined proximity radius,
//   UNUserNotificationCenter schedules a local system banner."
//
//  This file decides WHICH tables deserve that banner. It is used in two places:
//   • while the app is open  -> on every live Firestore update (TablesStore)
//   • while the app is closed -> when iOS wakes the app in the background
//     (when the user has moved about 500 m)
//  It remembers what it already alerted about, so you never get the same alert twice.
//

import Foundation
import CoreLocation

enum NearbyAlertEngine {

    /// Pure decision logic (unit tested).
    /// - Parameters:
    ///   - createdAfter: only tables created after the last check count as "new"
    ///   - alreadyAlerted: table ids we've already sent a banner for
    static func tablesToAlert(_ tables: [CommunityTable],
                              createdAfter: Date,
                              alreadyAlerted: Set<String>,
                              currentUserId: String?,
                              userLocation: CLLocation?,
                              radiusKm: Double,
                              now: Date = Date()) -> [CommunityTable] {
        // Without a location we can't know if a table is "within the radius"
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

/// Remembers (in UserDefaults) when we last checked and what we already alerted about.
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

    /// Saves the ids we just alerted about (keeps the newest 200).
    func record(alerted ids: [String], checkedAt date: Date = Date()) {
        var all = defaults.stringArray(forKey: alertedKey) ?? []
        all.append(contentsOf: ids)
        defaults.set(Array(all.suffix(200)), forKey: alertedKey)
        defaults.set(date, forKey: lastCheckKey)
    }
}
