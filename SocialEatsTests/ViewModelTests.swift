//
//  ViewModelTests.swift
//  SocialEatsTests
//
//  Tests the ViewModels and managers with MOCK services injected
//  (this is why the app uses protocols + dependency injection).
//  Also tests Core Data offline storage with an in-memory store.
//

import Testing
import Foundation
import Combine
import CoreLocation
@testable import SocialEats

/// Builds everything a test needs, wired to in-memory mocks.
@MainActor
struct TestEnvironment {
    let database = MockDatabase()
    let auth: MockAuthService
    let users: MockUserService
    let tables: MockTableService
    let chat: MockChatService
    let biometrics: MockBiometricService
    let notifications = MockNotificationService()
    let offlineStore = CoreDataOfflineStore(persistence: PersistenceController(inMemory: true))
    let settings: SettingsStore
    let session: SessionStore
    let reservations: ReservationManager

    init(signedIn: Bool = true, faceIDPasses: Bool = true) {
        auth = MockAuthService(signedInUserId: signedIn ? SampleData.demoUser.id : nil)
        users = MockUserService(database: database)
        tables = MockTableService(database: database)
        chat = MockChatService(database: database)
        biometrics = MockBiometricService(shouldSucceed: faceIDPasses)

        // Fresh UserDefaults for every test so settings don't leak
        let defaults = UserDefaults(suiteName: "tests-\(UUID().uuidString)")!
        settings = SettingsStore(defaults: defaults)
        settings.hasSeenOnboarding = true

        session = SessionStore(auth: auth, users: users, biometrics: biometrics, settings: settings)
        reservations = ReservationManager(tables: tables, users: users, biometrics: biometrics,
                                          offlineStore: offlineStore, notifications: notifications,
                                          location: nil, settings: settings)
    }

    /// A TablesStore wired to the mocks, with its own clean alert history.
    func makeTablesStore(userId: String?, location: CLLocation? = nil) -> TablesStore {
        let history = NearbyAlertHistory(defaults: UserDefaults(suiteName: "alerts-\(UUID().uuidString)")!)
        return TablesStore(tableService: tables, offlineStore: offlineStore, notifications: notifications,
                           settings: settings, alertHistory: history,
                           currentLocation: { location }, currentUserId: { userId })
    }

    /// Signs the demo user in and waits until the profile is loaded.
    func signIn() async {
        await session.finishSignIn(userId: SampleData.demoUser.id)
    }
}

/// Waits (up to ~3 s) for an async condition — used for auto-submitting OTP.
@MainActor
func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0..<60 where !condition() {
        try? await Task.sleep(nanoseconds: 50_000_000)
    }
}

// MARK: - Session / app flow

@Suite("Session flow")
@MainActor
struct SessionStoreTests {

    @Test("First launch shows onboarding")
    func firstLaunch() async {
        let env = TestEnvironment(signedIn: false)
        env.settings.hasSeenOnboarding = false
        await env.session.bootstrap()
        #expect(env.session.phase == .onboarding)
    }

    @Test("Signed-in user with Face ID protection sees 'Welcome Back' and logs in with Face ID")
    func faceIDLoginOnLaunch() async {
        let env = TestEnvironment(signedIn: true)
        env.settings.faceIDProtectionEnabled = true
        await env.session.bootstrap()
        #expect(env.session.phase == .signIn)
        #expect(env.session.hasSavedAccount)

        let error = await env.session.unlockWithBiometrics()
        #expect(error == nil)
        #expect(env.session.phase == .main)
    }

    @Test("Failed Face ID keeps the user on the sign-in screen")
    func failedUnlock() async {
        let env = TestEnvironment(signedIn: true, faceIDPasses: false)
        env.settings.faceIDProtectionEnabled = true
        await env.session.bootstrap()
        let error = await env.session.unlockWithBiometrics()
        #expect(error != nil)
        #expect(env.session.phase == .signIn)
    }

    @Test("Face ID login without a saved account explains what to do")
    func faceIDNeedsSavedAccount() async {
        let env = TestEnvironment(signedIn: false)
        let error = await env.session.unlockWithBiometrics()
        #expect(error?.contains("Sign in once") == true)
    }

    @Test("A brand-new user gets a profile with starting karma and their taste choices")
    func newUserProfile() async {
        let env = TestEnvironment(signedIn: true)
        env.database.users = [:]                       // nobody in the database yet
        env.session.completeTasteProfile(TasteProfileDraft(ambiences: [.quietIntrovert], cuisines: [.streetTacos],
                                                            diningStyle: .soloExplorer, dietaryTags: [.vegan]))
        await env.signIn()

        let user = env.session.currentUser
        #expect(user?.karma == KarmaCalculator.startingKarma)
        #expect(user?.cuisines == [.streetTacos])
        #expect(user?.diningStyle == .soloExplorer)
        #expect(env.settings.dietaryTags == [.vegan])
        #expect(env.database.users[SampleData.demoUser.id] != nil)   // saved to the backend
    }

    @Test("Signing out returns to sign-in and clears the user")
    func signOut() async {
        let env = TestEnvironment()
        await env.signIn()
        env.session.signOut()
        #expect(env.session.phase == .signIn)
        #expect(env.session.currentUser == nil)
    }
}

// MARK: - Auth

@Suite("Phone OTP sign-in")
@MainActor
struct AuthViewModelTests {

    @Test("Invalid phone shows an error and stays on step 1")
    func invalidPhone() async {
        let env = TestEnvironment(signedIn: false)
        let viewModel = AuthViewModel(auth: env.auth, session: env.session)
        viewModel.phoneInput = "123"
        await viewModel.sendCode()
        #expect(viewModel.step == .enterDetails)
        #expect(viewModel.errorMessage != nil)
    }

    @Test("Valid phone sends a code and starts the 30 s resend timer")
    func sendsCode() async {
        let env = TestEnvironment(signedIn: false)
        let viewModel = AuthViewModel(auth: env.auth, session: env.session)
        viewModel.phoneInput = "77 123 4567"
        #expect(viewModel.isPhoneValid)
        await viewModel.sendCode()
        #expect(viewModel.step == .enterCode)
        #expect(viewModel.maskedPhone == "+94 77 ••• 4567")
        #expect(viewModel.canResend == false)
        #expect(viewModel.resendSecondsLeft > 25)
    }

    @Test("Typing the 6th digit signs the user in automatically")
    func autoSubmit() async {
        let env = TestEnvironment(signedIn: false)
        let viewModel = AuthViewModel(auth: env.auth, session: env.session)
        viewModel.phoneInput = "0771234567"
        await viewModel.sendCode()
        viewModel.otpCode = "123456"
        await waitUntil { env.session.phase == .main }
        #expect(env.session.phase == .main)
    }

    @Test("Wrong code shows an error and clears the boxes")
    func wrongCode() async {
        let env = TestEnvironment(signedIn: false)
        let viewModel = AuthViewModel(auth: env.auth, session: env.session)
        viewModel.phoneInput = "0771234567"
        await viewModel.sendCode()
        viewModel.otpCode = MockAuthService.wrongCode
        await waitUntil { viewModel.errorMessage != nil }
        #expect(viewModel.errorMessage != nil)
        #expect(viewModel.otpCode.isEmpty)
        #expect(env.session.phase != .main)
    }

    @Test("Typing an email in the top field opens the password sheet")
    func emailPath() async {
        let env = TestEnvironment(signedIn: false)
        let viewModel = AuthViewModel(auth: env.auth, session: env.session)
        viewModel.identifierInput = "alex@example.com"
        await viewModel.continueWithIdentifier()
        #expect(viewModel.showsPasswordSheet)
        #expect(viewModel.emailForPassword == "alex@example.com")
    }
}

// MARK: - Reservations

@Suite("Joining, cancelling and completing a table")
@MainActor
struct ReservationManagerTests {

    @Test("Joining with Face ID saves an offline pass, reminder and activity")
    func joinSuccess() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let user = try #require(env.session.currentUser)
        let table = try #require(env.database.tables["t-sushi"])          // 2/4 seats

        let reservation = try await env.reservations.join(table, user: user)

        #expect(reservation.seatNumber == 3)
        #expect(env.database.tables["t-sushi"]?.seatsFilled == 3)       // backend updated
        #expect(env.offlineStore.reservation(tableId: "t-sushi", userId: user.id) != nil)   // Core Data
        #expect(env.notifications.reminders.contains("t-sushi"))
        #expect(env.biometrics.requestCount == 1)
        #expect(env.database.rsvps["t-sushi_\(user.id)"] == .confirmed)       // RSVP state saved
        await waitUntil { env.database.activity[user.id]?.contains { $0.id == "seat-t-sushi" } == true }
        #expect(env.database.activity[user.id]?.contains { $0.id == "seat-t-sushi" } == true)
    }

    @Test("If Face ID fails, no seat is taken")
    func joinBiometricFails() async throws {
        let env = TestEnvironment(faceIDPasses: false)
        await env.signIn()
        let user = try #require(env.session.currentUser)
        let table = try #require(env.database.tables["t-sushi"])

        await #expect(throws: BiometricError.failed) {
            try await env.reservations.join(table, user: user)
        }
        #expect(env.database.tables["t-sushi"]?.seatsFilled == 2)
        #expect(env.offlineStore.reservation(tableId: "t-sushi", userId: user.id) == nil)
    }

    @Test("Face ID is skipped when protection is turned off")
    func noFaceIDWhenDisabled() async throws {
        let env = TestEnvironment()
        env.settings.faceIDProtectionEnabled = false
        await env.signIn()
        let user = try #require(env.session.currentUser)
        _ = try await env.reservations.join(try #require(env.database.tables["t-pizza"]), user: user)
        #expect(env.biometrics.requestCount == 0)
    }

    @Test("Cancelling removes the seat, pass and reminder")
    func cancel() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let user = try #require(env.session.currentUser)
        _ = try await env.reservations.join(try #require(env.database.tables["t-sushi"]), user: user)

        try await env.reservations.cancel(try #require(env.database.tables["t-sushi"]), userId: user.id)

        #expect(env.database.tables["t-sushi"]?.seatsFilled == 2)
        #expect(env.offlineStore.reservation(tableId: "t-sushi", userId: user.id) == nil)
        #expect(!env.notifications.reminders.contains("t-sushi"))
        #expect(env.database.rsvps["t-sushi_\(user.id)"] == .cancelled)
    }

    @Test("The host can move their table to a new time, and their offline pass updates")
    func hostChangesTime() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let user = try #require(env.session.currentUser)
        // Make the demo user the host of the sushi table
        env.database.tables["t-sushi"]?.hostId = user.id
        let table = try #require(env.database.tables["t-sushi"])
        let newTime = Date().addingTimeInterval(5 * 60 * 60)

        try await env.reservations.changeTime(of: table, to: newTime, userId: user.id)

        #expect(env.database.tables["t-sushi"]?.startTime == newTime)
        #expect(env.offlineStore.reservation(tableId: "t-sushi", userId: user.id)?.startTime == newTime)
    }

    @Test("Someone who isn't the host can't change the time")
    func guestCantChangeTime() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let user = try #require(env.session.currentUser)
        let table = try #require(env.database.tables["t-sushi"])
        let oldTime = table.startTime

        try await env.reservations.changeTime(of: table, to: Date().addingTimeInterval(9000), userId: user.id)

        #expect(env.database.tables["t-sushi"]?.startTime == oldTime)
    }

    @Test("A verified receipt adds karma and marks the pass complete")
    func completeMeal() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let user = try #require(env.session.currentUser)
        let karmaBefore = user.karma
        _ = try await env.reservations.join(try #require(env.database.tables["t-sushi"]), user: user)
        let table = try #require(env.database.tables["t-sushi"])

        let receipt = ReceiptScanResult(restaurantName: "Matsuya Kitchen", total: 4200, currencyCode: "LKR",
                                        timestamp: Date(), rawLines: [])
        let points = try await env.reservations.completeMeal(table: table, userId: user.id, receipt: receipt)

        #expect(points == 200)
        #expect(env.database.users[user.id]?.karma == karmaBefore + 200)
        #expect(env.database.users[user.id]?.mealsShared == user.mealsShared + 1)
        #expect(env.offlineStore.reservation(tableId: "t-sushi", userId: user.id)?.isVerified == true)
        #expect(env.database.rsvps["t-sushi_\(user.id)"] == .completed)
        // Host + 1 guest were at the table -> 2 new friends
        #expect(env.database.users[user.id]?.newFriends == user.newFriends + 2)
    }
}

// MARK: - Dashboard

@Suite("Dashboard filtering (Combine)")
@MainActor
struct DashboardViewModelTests {

    @Test("Category chip filters the live list and hides tables I've joined")
    func categoryFilter() async throws {
        let env = TestEnvironment()
        await env.signIn()
        let store = env.makeTablesStore(userId: SampleData.demoUser.id)
        store.start()
        await waitUntil { !store.tables.isEmpty }

        let location = CurrentValueSubject<CLLocation?, Never>(nil)
        let viewModel = DashboardViewModel(tablesStore: store, locationPublisher: location.eraseToAnyPublisher(),
                                           settings: env.settings, session: env.session)
        await waitUntil { !viewModel.visibleTables.isEmpty }
        #expect(viewModel.visibleTables.count == SampleData.tables().count)

        viewModel.select(.sushi)
        await waitUntil { viewModel.visibleTables.count == 1 }
        #expect(viewModel.visibleTables.map(\.category) == [.sushi])

        // Join one table -> it moves to "Your Upcoming Tables"
        viewModel.select(nil)
        let user = try #require(env.session.currentUser)
        _ = try await env.reservations.join(try #require(env.database.tables["t-sushi"]), user: user)
        await waitUntil { viewModel.myUpcomingTables.contains { $0.id == "t-sushi" } }
        #expect(viewModel.myUpcomingTables.map(\.id).contains("t-sushi"))
        #expect(!viewModel.visibleTables.map(\.id).contains("t-sushi"))
    }

    @Test("Cached tables are saved to Core Data for offline use")
    func cachesTables() async {
        let env = TestEnvironment()
        let store = env.makeTablesStore(userId: nil)
        store.start()
        await waitUntil { !store.tables.isEmpty }
        #expect(env.offlineStore.cachedTables().count == SampleData.tables().count)
    }

    @Test("A new table opened by someone else triggers a nearby alert")
    func nearbyAlert() async throws {
        let env = TestEnvironment()
        let center = SampleData.defaultCenter
        let store = env.makeTablesStore(userId: "me",
                                        location: CLLocation(latitude: center.latitude, longitude: center.longitude))
        store.start()
        await waitUntil { !store.tables.isEmpty }

        var newTable = try #require(env.database.tables["t-pizza"])
        newTable.hostId = "someone"
        newTable.createdAt = Date()            // a brand-new table (sample ones are 3 h old)
        let newId = try await env.tables.createTable(newTable)
        await waitUntil { env.notifications.nearbyAlerts.contains(newId) }
        #expect(env.notifications.nearbyAlerts == [newId])     // only the NEW table, not the first load
    }
}

// MARK: - Chat

@Suite("Group chat")
@MainActor
struct ChatViewModelTests {

    @Test("Members can send; message appears in the live list")
    func memberSends() async {
        let env = TestEnvironment()
        await env.signIn()
        // Demo user joins the taco table first
        env.database.tables["t-taco"]?.attendeeIds.append(SampleData.demoUser.id)
        env.database.tables["t-taco"]?.attendeeNames.append(SampleData.demoUser.displayName)

        let viewModel = ChatViewModel(tableId: "t-taco", chat: env.chat, tableService: env.tables,
                                      users: env.users, session: env.session)
        viewModel.start()
        await waitUntil { viewModel.table != nil }
        #expect(viewModel.canChat)

        let before = viewModel.messages.count
        viewModel.draft = "On my way! 🚶"
        await viewModel.send()
        await waitUntil { viewModel.messages.count == before + 1 }
        #expect(viewModel.messages.last?.text == "On my way! 🚶")
        #expect(viewModel.draft.isEmpty)
    }

    @Test("Non-members cannot send messages")
    func nonMemberBlocked() async {
        let env = TestEnvironment()
        await env.signIn()
        let viewModel = ChatViewModel(tableId: "t-pizza", chat: env.chat, tableService: env.tables,
                                      users: env.users, session: env.session)
        viewModel.start()
        await waitUntil { viewModel.table != nil }
        viewModel.draft = "hello"
        #expect(!viewModel.canSend)
        await viewModel.send()
        #expect(env.database.messages["t-pizza"] == nil)
    }
}

// MARK: - Search & offline storage

@Suite("Voice search keywords")
struct SearchKeywordTests {
    @Test(arguments: [
        ("Cozy ramen spots nearby with open seats", "ramen"),
        ("find the best pizza near me", "pizza"),
        ("sushi", "sushi")
    ])
    func keywords(spoken: String, expected: String) async {
        let result = await MainActor.run { SearchViewModel.keywords(from: spoken) }
        #expect(result == expected)
    }
}

@Suite("Core Data offline store")
@MainActor
struct OfflineStoreTests {

    @Test("Save, load, verify and delete a reservation")
    func reservationLifecycle() throws {
        let store = CoreDataOfflineStore(persistence: PersistenceController(inMemory: true))
        let table = try SampleData.tables()[1].adding(userId: "me", name: "Me")
        let reservation = Reservation.make(from: table, userId: "me")

        store.saveReservation(reservation)
        #expect(store.reservations(for: "me").count == 1)
        #expect(store.reservation(tableId: table.id, userId: "me")?.qrToken == reservation.qrToken)

        // Saving again updates instead of duplicating
        store.saveReservation(reservation)
        #expect(store.reservations(for: "me").count == 1)

        store.markVerified(tableId: table.id, userId: "me")
        #expect(store.reservation(tableId: table.id, userId: "me")?.isVerified == true)

        store.deleteReservation(tableId: table.id, userId: "me")
        #expect(store.reservations(for: "me").isEmpty)
    }

    @Test("Other users' passes are kept separate")
    func perUser() throws {
        let store = CoreDataOfflineStore(persistence: PersistenceController(inMemory: true))
        let table = SampleData.tables()[0]
        store.saveReservation(Reservation.make(from: table, userId: table.hostId))
        #expect(store.reservations(for: "someone-else").isEmpty)
    }

    @Test("Table cache round-trips through JSON + Core Data")
    func tableCache() {
        let store = CoreDataOfflineStore(persistence: PersistenceController(inMemory: true))
        let tables = SampleData.tables()
        store.cacheTables(tables)
        store.cacheTables(tables)          // replacing the cache shouldn't duplicate
        let cached = store.cachedTables()
        #expect(cached.count == tables.count)
        #expect(Set(cached.map(\.id)) == Set(tables.map(\.id)))
    }
}

