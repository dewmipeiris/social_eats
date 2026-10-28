//
//  AppContainer.swift
//  SocialEats
//
//  The "dependency container": creates every service ONCE and hands
//  them to ViewModels. Screens never create services themselves.
//
//  • live()    -> real Firebase (if GoogleService-Info.plist is in the project)
//  • demo()    -> in-memory mock services (app still fully works offline,
//                 handy for previews and if Firebase isn't set up yet)
//

import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

@MainActor
final class AppContainer: ObservableObject {

    /// True when running on mock data (no Firebase config file found)
    let isDemoMode: Bool

    // Backend services (protocols — can be real or mock)
    let auth: AuthServicing
    let users: UserServicing
    let tableService: TableServicing
    let chat: ChatServicing

    // Device services
    let biometrics: BiometricServicing
    let notifications: NotificationService
    let location: LocationService
    let receiptScanner: ReceiptScanning
    let offlineStore: OfflineStoring
    let network: NetworkMonitor
    let settings: SettingsStore

    // Shared state
    let session: SessionStore
    let tablesStore: TablesStore
    let reservations: ReservationManager

    /// Mock database (only in demo mode) — used by "Add sample tables"
    let mockDatabase: MockDatabase?
    private var cancellables = Set<AnyCancellable>()

    init(isDemoMode: Bool,
         auth: AuthServicing,
         users: UserServicing,
         tableService: TableServicing,
         chat: ChatServicing,
         biometrics: BiometricServicing,
         persistence: PersistenceController,
         settings: SettingsStore = SettingsStore(),
         mockDatabase: MockDatabase? = nil) {

        self.isDemoMode = isDemoMode
        self.auth = auth
        self.users = users
        self.tableService = tableService
        self.chat = chat
        self.biometrics = biometrics
        self.mockDatabase = mockDatabase
        self.settings = settings

        // Create device services as local constants first (Swift won't let us
        // read self.properties until every stored property has a value)
        let notifications = NotificationService()
        let location = LocationService()
        let offlineStore = CoreDataOfflineStore(persistence: persistence)
        self.notifications = notifications
        self.location = location
        self.offlineStore = offlineStore
        receiptScanner = VisionReceiptScanner()
        network = NetworkMonitor()

        let session = SessionStore(auth: auth, users: users, biometrics: biometrics, settings: settings)
        self.session = session

        tablesStore = TablesStore(
            tableService: tableService,
            offlineStore: offlineStore,
            notifications: notifications,
            settings: settings,
            currentLocation: { [weak location] in location?.currentLocation },
            currentUserId: { [weak session] in session?.userId }
        )

        reservations = ReservationManager(
            tables: tableService, users: users, biometrics: biometrics,
            offlineStore: offlineStore, notifications: notifications,
            location: location, settings: settings
        )

        wireUpDeepLinks()

        // Background "new table nearby" checks (Feature 5): run when iOS wakes us
        // after a significant move, and keep the low-power tracking in sync with
        // the Settings toggle + location permission.
        let tablesStore = self.tablesStore
        location.onSignificantMove = { [weak tablesStore] in
            Task { @MainActor in await tablesStore?.runBackgroundNearbyCheck() }
        }
        settings.$nearbyAlertsEnabled
            .combineLatest(location.$authorizationStatus)
            .sink { [weak location] enabled, status in
                location?.setBackgroundNearbyMonitoring(enabled, status: status)
            }
            .store(in: &cancellables)

        // Demo mode: once we know where the user is, put the sample tables nearby
        if let mockDatabase {
            location.$currentLocation
                .compactMap { $0 }
                .first()
                .sink { [weak mockDatabase] location in
                    mockDatabase?.reseedTables(around: location.coordinate)
                }
                .store(in: &cancellables)
        }
    }

    /// Tapping a notification or entering a venue geofence opens that table.
    private func wireUpDeepLinks() {
        notifications.onOpenTable = { [weak session = self.session] tableId in
            Task { @MainActor in session?.pendingTableId = tableId }
        }
        location.onEnterVenue = { [weak notifications = self.notifications] tableId, venueName in
            notifications?.notifyArrivedAtVenue(tableId: tableId, venueName: venueName)
        }
    }

    // MARK: - Factories

    /// Real app: Firebase if configured, otherwise demo mode.
    static func live() -> AppContainer {
        let hasFirebaseConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

        guard hasFirebaseConfig else {
            print("ℹ️ GoogleService-Info.plist not found — running SocialEats in DEMO MODE")
            return demo()
        }

        FirebaseApp.configure()

        // Firestore keeps its own offline cache, so chat messages and seat
        // changes made offline are sent automatically when back online.
        let firestoreSettings = FirestoreSettings()
        firestoreSettings.cacheSettings = PersistentCacheSettings()
        Firestore.firestore().settings = firestoreSettings

        return AppContainer(
            isDemoMode: false,
            auth: FirebaseAuthService(),
            users: FirestoreUserService(),
            tableService: FirestoreTableService(),
            chat: FirestoreChatService(),
            biometrics: BiometricService(),
            persistence: PersistenceController()
        )
    }

    /// Everything in memory — no internet or Firebase needed.
    static func demo(signedIn: Bool = false) -> AppContainer {
        let database = MockDatabase()
        return AppContainer(
            isDemoMode: true,
            auth: MockAuthService(signedInUserId: signedIn ? SampleData.demoUser.id : nil,
                                  remembersSignIn: !signedIn),
            users: MockUserService(database: database),
            tableService: MockTableService(database: database),
            chat: MockChatService(database: database),
            biometrics: BiometricService(),
            persistence: PersistenceController(inMemory: true),
            mockDatabase: database
        )
    }

    /// For SwiftUI previews: signed in with sample data.
    static var preview: AppContainer {
        let container = demo(signedIn: true)
        Task { await container.session.finishSignIn(userId: SampleData.demoUser.id) }
        container.tablesStore.start()
        return container
    }

    // MARK: - Demo helpers

    /// Settings > "Add sample tables near me": fills the backend with
    /// example tables around the user's current position (great for the demo video).
    /// A sample table is SKIPPED if the same one is already there and people can
    /// still join it, so pressing the button twice doesn't make duplicates.
    func addSampleTablesNearUser() async throws -> Int {
        let center = location.currentLocation?.coordinate ?? SampleData.defaultCenter
        let samples = SampleData.tables(around: center)

        // Tables that are already in the database
        let existing = try await tableService.fetchActiveTables()
        let now = Date()

        var added = 0
        for table in samples {
            // Same title at the same venue, and joining is still open (not started 30+ min ago)
            let alreadyThere = existing.contains { old in
                old.title == table.title
                    && old.venueName == table.venueName
                    && old.startTime.addingTimeInterval(30 * 60) > now
            }
            if alreadyThere { continue }      // skip it, no duplicate
            _ = try await tableService.createTable(table)
            added += 1
        }
        return added
    }
}

