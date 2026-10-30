//  ServiceProtocols.swift

import Foundation

protocol ListenerToken {
    func remove()
}

protocol AuthServicing: AnyObject {
    var currentUserId: String? { get }
    var currentDisplayName: String? { get }
    var currentPhone: String? { get }
    var currentEmail: String? { get }

    func sendOTP(to e164Phone: String) async throws -> String
    func verifyOTP(verificationID: String, code: String) async throws -> String
    func signInWithGoogle() async throws -> String
    func signInWithEmail(_ email: String, password: String) async throws -> String
    func sendPasswordReset(to email: String) async throws
    func signOut() throws
}

protocol UserServicing: AnyObject {
    func fetchUser(id: String) async throws -> AppUser?
    func saveUser(_ user: AppUser) async throws
    func listenToUser(id: String, onChange: @escaping (AppUser?) -> Void) -> ListenerToken
    func addKarma(_ points: Int, to userId: String, mealCompleted: Bool) async throws
    /// "New Friends" stat on the profile — everyone you shared a verified meal with
    func addFriends(_ count: Int, to userId: String) async throws
    func listenToActivity(userId: String, onChange: @escaping ([ActivityItem]) -> Void) -> ListenerToken
    func addActivity(_ item: ActivityItem, for userId: String) async throws
    func markActivityRead(userId: String, itemIds: [String]) async throws
}

protocol TableServicing: AnyObject {
    func listenToActiveTables(onChange: @escaping (Result<[CommunityTable], Error>) -> Void) -> ListenerToken
    func listenToTable(id: String, onChange: @escaping (CommunityTable?) -> Void) -> ListenerToken
    func fetchTable(id: String) async throws -> CommunityTable?
    func fetchActiveTables() async throws -> [CommunityTable]
    func createTable(_ table: CommunityTable) async throws -> String
    func joinTable(id: String, userId: String, userName: String) async throws -> CommunityTable
    func leaveTable(id: String, userId: String) async throws
    func submitReceipt(tableId: String, userId: String, result: ReceiptScanResult) async throws
    func rateTablemate(tableId: String, raterId: String, rateeId: String, stars: Int) async throws
    func updateTableTime(id: String, startTime: Date) async throws
}

protocol ChatServicing: AnyObject {
    func listenToMessages(tableId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerToken
    func sendMessage(_ message: ChatMessage, tableId: String) async throws
}

enum RSVPStatus: String, Codable {
    case confirmed
    case cancelled
    case completed
}

struct EmptyListenerToken: ListenerToken {
    func remove() {}
}

struct ClosureListenerToken: ListenerToken {
    let onRemove: () -> Void
    func remove() { onRemove() }
}
