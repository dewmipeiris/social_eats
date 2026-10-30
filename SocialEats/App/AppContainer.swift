//  AppContainer.swift

import Foundation
import Combine
import FirebaseCore
import FirebaseFirestore

@MainActor
final class AppContainer: ObservableObject {

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

    private func wireUpDeepLinks() {
        notifications.onOpenTable = { [weak session = self.session] tableId in
            Task { @MainActor in session?.pendingTableId = tableId }
        }
        location.onEnterVenue = { [weak notifications = self.notifications] tableId, venueName in
            notifications?.notifyArrivedAtVenue(tableId: tableId, venueName: venueName)
        }
    }

// Factories
    static func live() -> AppContainer {
        let hasFirebaseConfig = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

        guard hasFirebaseConfig else {
            print("ℹ️ GoogleService-Info.plist not found — running SocialEats in DEMO MODE")
            return demo()
        }

        FirebaseApp.configure()

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

    static var preview: AppContainer {
        let container = demo(signedIn: true)
        Task { await container.session.finishSignIn(userId: SampleData.demoUser.id) }
        container.tablesStore.start()
        return container
    }

// Demo helpers
    
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

