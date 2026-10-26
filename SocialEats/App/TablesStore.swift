//
//  TablesStore.swift
//  SocialEats
//
//  ONE shared live list of community tables that every screen reads
//  (Dashboard, Map, Shake to Match, Search). This is the "Repository"
//  pattern: one listener to Firestore instead of one per screen.
//
//  It also:
//   • caches the list in Core Data for offline use (Above & Beyond: offline support)
//   • sends a "new table nearby" notification when a host opens a table
//     inside the user's radius (proposal Feature 5)
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class TablesStore: ObservableObject {

    @Published private(set) var tables: [CommunityTable] = []
    @Published private(set) var isLoading = true
    @Published private(set) var errorMessage: String?
    /// True when we are showing the Core Data copy because the network failed
    @Published private(set) var isShowingCachedData = false

    private let tableService: TableServicing
    private let offlineStore: OfflineStoring
    private let notifications: NotificationServicing
    private let settings: SettingsStore
    private let currentUserId: () -> String?
    /// Where the user is right now (a closure so tests can pass a fixed spot)
    private let currentLocation: () -> CLLocation?
    /// Remembers which tables we already sent "nearby" banners for
    private let alertHistory: NearbyAlertHistory

    private var listener: ListenerToken?

    init(tableService: TableServicing,
         offlineStore: OfflineStoring,
         notifications: NotificationServicing,
         settings: SettingsStore,
         alertHistory: NearbyAlertHistory = NearbyAlertHistory(),
         currentLocation: @escaping () -> CLLocation?,
         currentUserId: @escaping () -> String?) {
        self.tableService = tableService
        self.offlineStore = offlineStore
        self.notifications = notifications
        self.settings = settings
        self.alertHistory = alertHistory
        self.currentLocation = currentLocation
        self.currentUserId = currentUserId
    }

    // MARK: - Start / stop

    func start() {
        guard listener == nil else { return }

        // Show the cached copy instantly while the network loads
        let cached = offlineStore.cachedTables()
        if !cached.isEmpty {
            tables = cached
            isLoading = false
        }

        listener = tableService.listenToActiveTables { [weak self] result in
            Task { @MainActor in self?.handle(result) }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    /// Pull-to-refresh: restart the listener.
    func refresh() {
        stop()
        start()
    }

    // MARK: - Lookups

    func table(id: String) -> CommunityTable? {
        tables.first { $0.id == id }
    }

    /// Tables the user has a seat at (including hosting), soonest first.
    func joinedTables(userId: String?) -> [CommunityTable] {
        tables.filter { $0.isAttending(userId) }.sorted { $0.startTime < $1.startTime }
    }

    // MARK: - Private

    private func handle(_ result: Result<[CommunityTable], Error>) {
        isLoading = false
        switch result {
        case .success(let list):
            detectNewNearbyTables(in: list)
            tables = list
            errorMessage = nil
            isShowingCachedData = false
            offlineStore.cacheTables(list)

        case .failure(let error):
            // Network problem -> fall back to the Core Data cache
            let cached = offlineStore.cachedTables()
            if !cached.isEmpty {
                tables = cached
                isShowingCachedData = true
            }
            errorMessage = "Couldn't load live tables: \(error.localizedDescription)"
        }
    }

    /// Sends an alert for each brand-new table inside the user's radius
    /// (shared by the live listener and the background check).
    @discardableResult
    private func detectNewNearbyTables(in list: [CommunityTable]) -> Int {
        guard settings.nearbyAlertsEnabled else { return 0 }

        let location = currentLocation()
        let newTables = NearbyAlertEngine.tablesToAlert(
            list,
            createdAfter: alertHistory.lastCheck.addingTimeInterval(-10 * 60),   // 10 min grace for phone clock differences
            alreadyAlerted: alertHistory.alertedIds,
            currentUserId: currentUserId(),
            userLocation: location,
            radiusKm: settings.proximityRadiusKm
        )
        for table in newTables {
            notifications.notifyNewTableNearby(table, distanceMetres: table.distance(from: location))
        }
        alertHistory.record(alerted: newTables.map(\.id))
        return newTables.count
    }

    // MARK: - Background check (app closed)

    /// Called when iOS wakes the app in the background (significant location
    /// change — the user moved about 500 m). Downloads tables once and alerts
    /// about new ones nearby. Returns true if it worked.
    @discardableResult
    func runBackgroundNearbyCheck() async -> Bool {
        do {
            let list = try await tableService.fetchActiveTables()
            detectNewNearbyTables(in: list)
            offlineStore.cacheTables(list)
            return true
        } catch {
            return false
        }
    }
}
