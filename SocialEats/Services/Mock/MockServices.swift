//
//  MockServices.swift
//  SocialEats
//
//  In-memory versions of every backend service.
//  Used for: unit tests, SwiftUI previews, and "Demo mode"
//  (the app runs without GoogleService-Info.plist).
//
//  They behave like the real ones — including live listeners —
//  so the UI updates the same way.
//

import Foundation
import CoreLocation

/// Shared in-memory "database" for all mock services.
final class MockDatabase {
    var tables: [String: CommunityTable] = [:]
    var users: [String: AppUser] = [:]
    var messages: [String: [ChatMessage]] = [:]
    var activity: [String: [ActivityItem]] = [:]
    var receipts: [String: ReceiptScanResult] = [:]
    /// "tableId_userId" -> RSVP status (same idea as the Firestore rsvps collection)
    var rsvps: [String: RSVPStatus] = [:]

    // Listener callbacks, keyed by a random id so they can be removed
    var tableListeners: [UUID: (Result<[CommunityTable], Error>) -> Void] = [:]
    var singleTableListeners: [UUID: (id: String, callback: (CommunityTable?) -> Void)] = [:]
    var messageListeners: [UUID: (tableId: String, callback: ([ChatMessage]) -> Void)] = [:]
    var userListeners: [UUID: (userId: String, callback: (AppUser?) -> Void)] = [:]
    var activityListeners: [UUID: (userId: String, callback: ([ActivityItem]) -> Void)] = [:]

    init(seed: Bool = true) {
        guard seed else { return }
        for table in SampleData.tables() { tables[table.id] = table }
        users[SampleData.demoUser.id] = SampleData.demoUser
        for member in SampleData.sampleMembers { users[member.id] = member }
        messages["t-taco"] = SampleData.sampleMessages
        activity[SampleData.demoUser.id] = SampleData.sampleActivity
    }

    /// Demo mode: move the sample tables next to the user's real location
    /// so distances and the map look realistic wherever you test the app.
    func reseedTables(around center: CLLocationCoordinate2D) {
        let userTables = tables.values.filter { $0.id.hasPrefix("new-") }   // tables the user created
        tables = [:]
        for table in SampleData.tables(around: center) { tables[table.id] = table }
        for table in userTables { tables[table.id] = table }
        notifyTables()
    }

    var sortedTables: [CommunityTable] {
        tables.values.sorted { $0.startTime < $1.startTime }
    }

    /// Tell every listener that tables changed.
    func notifyTables() {
        let list = sortedTables
        tableListeners.values.forEach { $0(.success(list)) }
        singleTableListeners.values.forEach { $0.callback(tables[$0.id]) }
    }

    func notifyMessages(tableId: String) {
        let list = messages[tableId] ?? []
        messageListeners.values.filter { $0.tableId == tableId }.forEach { $0.callback(list) }
    }

    func notifyUser(_ userId: String) {
        userListeners.values.filter { $0.userId == userId }.forEach { $0.callback(users[userId]) }
    }

    func notifyActivity(_ userId: String) {
        let list = (activity[userId] ?? []).sorted { $0.createdAt > $1.createdAt }
        activityListeners.values.filter { $0.userId == userId }.forEach { $0.callback(list) }
    }
}

// MARK: - Auth

final class MockAuthService: AuthServicing {
    /// Any 6-digit code works except this one (lets tests check the error path)
    static let wrongCode = "000000"

    private(set) var currentUserId: String?
    var currentDisplayName: String? = "Alex Morgan"
    var currentPhone: String?
    var currentEmail: String?

    init(signedInUserId: String? = nil) {
        currentUserId = signedInUserId
    }

    func sendOTP(to e164Phone: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 400_000_000)
        currentPhone = e164Phone
        return "mock-verification-id"
    }

    func verifyOTP(verificationID: String, code: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 300_000_000)
        guard code != Self.wrongCode, OTPValidator.isComplete(code) else {
            throw NSError(domain: "MockAuth", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Wrong code — please check the SMS and try again."])
        }
        currentUserId = SampleData.demoUser.id
        return SampleData.demoUser.id
    }

    func signInWithGoogle() async throws -> String {
        currentUserId = SampleData.demoUser.id
        return SampleData.demoUser.id
    }

    func signInWithEmail(_ email: String, password: String) async throws -> String {
        guard password.count >= 6 else {
            throw NSError(domain: "MockAuth", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Password must be at least 6 characters."])
        }
        currentEmail = email
        currentUserId = SampleData.demoUser.id
        return SampleData.demoUser.id
    }

    func signOut() throws {
        currentUserId = nil
    }
}

// MARK: - Tables

final class MockTableService: TableServicing {
    let database: MockDatabase

    init(database: MockDatabase) {
        self.database = database
    }

    func listenToActiveTables(onChange: @escaping (Result<[CommunityTable], Error>) -> Void) -> ListenerToken {
        let key = UUID()
        database.tableListeners[key] = onChange
        onChange(.success(database.sortedTables))           // first snapshot
        return ClosureListenerToken { [weak database] in database?.tableListeners[key] = nil }
    }

    func listenToTable(id: String, onChange: @escaping (CommunityTable?) -> Void) -> ListenerToken {
        let key = UUID()
        database.singleTableListeners[key] = (id, onChange)
        onChange(database.tables[id])
        return ClosureListenerToken { [weak database] in database?.singleTableListeners[key] = nil }
    }

    func fetchTable(id: String) async throws -> CommunityTable? {
        database.tables[id]
    }

    func fetchActiveTables() async throws -> [CommunityTable] {
        database.sortedTables
    }

    func createTable(_ table: CommunityTable) async throws -> String {
        var newTable = table
        newTable.id = "new-" + UUID().uuidString.prefix(8)
        database.tables[newTable.id] = newTable
        database.rsvps["\(newTable.id)_\(newTable.hostId)"] = .confirmed
        database.notifyTables()
        return newTable.id
    }

    func joinTable(id: String, userId: String, userName: String) async throws -> CommunityTable {
        guard let table = database.tables[id] else { throw TableJoinError.notFound }
        let updated = try table.adding(userId: userId, name: userName)
        database.tables[id] = updated
        database.rsvps["\(id)_\(userId)"] = .confirmed
        database.notifyTables()
        return updated
    }

    func leaveTable(id: String, userId: String) async throws {
        guard let table = database.tables[id] else { throw TableJoinError.notFound }
        database.tables[id] = try table.removing(userId: userId)
        database.rsvps["\(id)_\(userId)"] = .cancelled
        database.notifyTables()
    }

    func submitReceipt(tableId: String, userId: String, result: ReceiptScanResult) async throws {
        database.receipts["\(tableId)_\(userId)"] = result
        database.rsvps["\(tableId)_\(userId)"] = .completed
    }

    func rateTablemate(tableId: String, raterId: String, rateeId: String, stars: Int) async throws {}
}

// MARK: - Users

final class MockUserService: UserServicing {
    let database: MockDatabase

    init(database: MockDatabase) {
        self.database = database
    }

    func fetchUser(id: String) async throws -> AppUser? {
        database.users[id]
    }

    func saveUser(_ user: AppUser) async throws {
        database.users[user.id] = user
        database.notifyUser(user.id)
    }

    func listenToUser(id: String, onChange: @escaping (AppUser?) -> Void) -> ListenerToken {
        let key = UUID()
        database.userListeners[key] = (id, onChange)
        onChange(database.users[id])
        return ClosureListenerToken { [weak database] in database?.userListeners[key] = nil }
    }

    func addKarma(_ points: Int, to userId: String, mealCompleted: Bool) async throws {
        database.users[userId]?.karma += points
        if mealCompleted { database.users[userId]?.mealsShared += 1 }
        database.notifyUser(userId)
    }

    func addFriends(_ count: Int, to userId: String) async throws {
        database.users[userId]?.newFriends += max(count, 0)
        database.notifyUser(userId)
    }

    func listenToActivity(userId: String, onChange: @escaping ([ActivityItem]) -> Void) -> ListenerToken {
        let key = UUID()
        database.activityListeners[key] = (userId, onChange)
        onChange((database.activity[userId] ?? []).sorted { $0.createdAt > $1.createdAt })
        return ClosureListenerToken { [weak database] in database?.activityListeners[key] = nil }
    }

    func addActivity(_ item: ActivityItem, for userId: String) async throws {
        database.activity[userId, default: []].append(item)
        database.notifyActivity(userId)
    }

    func markActivityRead(userId: String, itemIds: [String]) async throws {
        guard var list = database.activity[userId] else { return }
        for index in list.indices where itemIds.contains(list[index].id) {
            list[index].isRead = true
        }
        database.activity[userId] = list
        database.notifyActivity(userId)
    }
}

// MARK: - Chat

final class MockChatService: ChatServicing {
    let database: MockDatabase

    init(database: MockDatabase) {
        self.database = database
    }

    func listenToMessages(tableId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerToken {
        let key = UUID()
        database.messageListeners[key] = (tableId, onChange)
        onChange(database.messages[tableId] ?? [])
        return ClosureListenerToken { [weak database] in database?.messageListeners[key] = nil }
    }

    func sendMessage(_ message: ChatMessage, tableId: String) async throws {
        database.messages[tableId, default: []].append(message)
        database.notifyMessages(tableId: tableId)
    }
}
