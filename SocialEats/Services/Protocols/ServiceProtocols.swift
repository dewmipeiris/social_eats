//
//  ServiceProtocols.swift
//  SocialEats
//
//  "Contracts" for every backend service.
//
//  Why protocols?  ViewModels only talk to these protocols, never to
//  Firebase directly. That means:
//   1. We can swap in Mock services for unit tests and SwiftUI previews.
//   2. The app still runs in "Demo mode" if Firebase isn't set up yet.
//  This is called Dependency Injection (Component 5: architecture).
//

import Foundation

/// Anything that can stop a live listener (Firestore snapshot listener).
protocol ListenerToken {
    func remove()
}

// MARK: - Authentication (Feature 1)

protocol AuthServicing: AnyObject {
    /// Firebase user id of whoever is signed in (nil = signed out)
    var currentUserId: String? { get }
    var currentDisplayName: String? { get }
    var currentPhone: String? { get }
    var currentEmail: String? { get }

    /// Sends a 6-digit SMS code. Returns a verification id needed for step 2.
    func sendOTP(to e164Phone: String) async throws -> String
    /// Checks the 6-digit code. Returns the user id.
    func verifyOTP(verificationID: String, code: String) async throws -> String
    func signInWithGoogle() async throws -> String
    /// Signs in, or creates the account if it doesn't exist yet.
    func signInWithEmail(_ email: String, password: String) async throws -> String
    /// "Forgot password?" — Firebase emails a link to choose a new password.
    func sendPasswordReset(to email: String) async throws
    func signOut() throws
}

// MARK: - Users (profiles, karma, activity feed)

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

// MARK: - Community tables (Features 3, 4, 9)

protocol TableServicing: AnyObject {
    /// Real-time updates of all active tables (addSnapshotListener)
    func listenToActiveTables(onChange: @escaping (Result<[CommunityTable], Error>) -> Void) -> ListenerToken
    func listenToTable(id: String, onChange: @escaping (CommunityTable?) -> Void) -> ListenerToken
    func fetchTable(id: String) async throws -> CommunityTable?
    /// One-off read (used by the background check for new nearby tables)
    func fetchActiveTables() async throws -> [CommunityTable]
    /// Creates a table with the host in Seat #1. Returns the new id.
    func createTable(_ table: CommunityTable) async throws -> String
    /// Takes a seat safely (a transaction, so two people can't take the last seat).
    /// The same transaction writes an RSVP record (rsvps/{tableId}_{userId}) with status "confirmed".
    func joinTable(id: String, userId: String, userName: String) async throws -> CommunityTable
    /// Frees the seat and marks the RSVP "cancelled".
    func leaveTable(id: String, userId: String) async throws
    /// Saves a verified receipt and marks the RSVP "completed".
    func submitReceipt(tableId: String, userId: String, result: ReceiptScanResult) async throws
    func rateTablemate(tableId: String, raterId: String, rateeId: String, stars: Int) async throws
    /// Host only: moves the meetup to a new time ("Edit Time" on the detail screen)
    func updateTableTime(id: String, startTime: Date) async throws
}

// MARK: - Group chat (Feature 7)

protocol ChatServicing: AnyObject {
    func listenToMessages(tableId: String, onChange: @escaping ([ChatMessage]) -> Void) -> ListenerToken
    func sendMessage(_ message: ChatMessage, tableId: String) async throws
}

/// The RSVP states stored in the Firestore "rsvps" collection (proposal Feature 4).
enum RSVPStatus: String, Codable {
    case confirmed      // seat held (Face ID confirmed)
    case cancelled      // user released the seat
    case completed      // receipt verified after the meal
}

/// A token that does nothing (used by mocks).
struct EmptyListenerToken: ListenerToken {
    func remove() {}
}

/// A token that runs a closure when removed.
struct ClosureListenerToken: ListenerToken {
    let onRemove: () -> Void
    func remove() { onRemove() }
}
