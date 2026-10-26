//
//  ReservationManager.swift
//  SocialEats
//
//  Everything that happens when you take, cancel or complete a seat,
//  in ONE place so every screen does it the same way:
//
//  JOIN:     Face ID ✔ -> Firestore transaction -> Core Data offline pass
//            -> 1-hour reminder -> venue geofence -> activity feed
//  CANCEL:   Face ID ✔ -> Firestore -> remove pass, reminder and geofence
//  COMPLETE: Vision receipt verified -> save receipt -> +karma -> mark pass verified
//

import Foundation

@MainActor
final class ReservationManager {

    private let tables: TableServicing
    private let users: UserServicing
    private let biometrics: BiometricServicing
    private let offlineStore: OfflineStoring
    private let notifications: NotificationServicing
    private let location: LocationService?
    private let settings: SettingsStore

    init(tables: TableServicing, users: UserServicing, biometrics: BiometricServicing,
         offlineStore: OfflineStoring, notifications: NotificationServicing,
         location: LocationService?, settings: SettingsStore) {
        self.tables = tables
        self.users = users
        self.biometrics = biometrics
        self.offlineStore = offlineStore
        self.notifications = notifications
        self.location = location
        self.settings = settings
    }

    /// Asks for Face ID only when the user has protection switched on.
    private func confirmWithBiometrics(reason: String) async throws {
        guard settings.faceIDProtectionEnabled, biometrics.availableKind != .none else { return }
        if case .failure(let error) = await biometrics.authenticate(reason: reason) {
            throw error
        }
    }

    // MARK: - Join

    /// Takes a seat and returns the saved offline reservation.
    func join(_ table: CommunityTable, user: AppUser) async throws -> Reservation {
        // Check locally first so we don't ask for Face ID on a full table
        if let reason = table.joinBlockReason(for: user.id) { throw reason }

        try await confirmWithBiometrics(reason: "Confirm your seat at \(table.venueName)")

        let updated = try await tables.joinTable(id: table.id, userId: user.id, userName: user.displayName)
        let reservation = Reservation.make(from: updated, userId: user.id)
        afterSeatConfirmed(updated, reservation: reservation, userId: user.id)
        return reservation
    }

    /// Saves the pass and sets up reminders — also used right after HOSTING a table.
    func afterSeatConfirmed(_ table: CommunityTable, reservation: Reservation, userId: String) {
        offlineStore.saveReservation(reservation)

        if settings.meetupRemindersEnabled {
            notifications.scheduleMeetupReminder(for: table)
        }
        location?.requestAlwaysPermission()
        location?.startGeofence(for: table)

        let item = ActivityItem(
            id: "seat-\(table.id)",
            kind: .seatConfirmed,
            title: table.isHost(userId) ? "Your table is live! 🎉" : "\(table.hostName) confirmed your seat!",
            body: "\(table.title) at \(table.venueName) • \(table.startTime.friendlyDayTime)",
            createdAt: Date(),
            tableId: table.id
        )
        Task { try? await users.addActivity(item, for: userId) }
    }

    // MARK: - Cancel

    func cancel(_ table: CommunityTable, userId: String) async throws {
        try await confirmWithBiometrics(reason: "Cancel your seat at \(table.venueName)")
        try await tables.leaveTable(id: table.id, userId: userId)
        offlineStore.deleteReservation(tableId: table.id, userId: userId)
        notifications.cancelMeetupReminder(tableId: table.id)
        location?.stopGeofence(tableId: table.id)
    }

    // MARK: - Complete (receipt verified)

    /// Returns the karma points earned.
    func completeMeal(table: CommunityTable, userId: String, receipt: ReceiptScanResult) async throws -> Int {
        let points = KarmaCalculator.pointsForVerifiedMeal(isHost: table.isHost(userId))

        try await tables.submitReceipt(tableId: table.id, userId: userId, result: receipt)
        try await users.addKarma(points, to: userId, mealCompleted: true)
        // Everyone else at the table counts as a "New Friend" on the profile
        try? await users.addFriends(table.attendeeIds.filter { $0 != userId }.count, to: userId)
        offlineStore.markVerified(tableId: table.id, userId: userId)
        location?.stopGeofence(tableId: table.id)
        notifications.notifyKarmaEarned(points: points, venueName: table.venueName)

        let item = ActivityItem(
            id: "karma-\(table.id)",
            kind: .karmaUnlocked,
            title: "Dining Karma Unlocked!",
            body: "Your receipt from \(table.venueName) was verified.",
            createdAt: Date(),
            tableId: table.id,
            points: points
        )
        try? await users.addActivity(item, for: userId)
        return points
    }

    /// "Rate Your Tablemates" — each rating gives the rater +15 karma.
    func rate(tablemateId: String, stars: Int, table: CommunityTable, raterId: String) async throws {
        try await tables.rateTablemate(tableId: table.id, raterId: raterId, rateeId: tablemateId, stars: stars)
        try await users.addKarma(KarmaCalculator.ratingTablematePoints, to: raterId, mealCompleted: false)
    }

    // MARK: - Offline passes

    func savedPasses(for userId: String) -> [Reservation] {
        offlineStore.reservations(for: userId)
    }

    func savedPass(tableId: String, userId: String) -> Reservation? {
        offlineStore.reservation(tableId: tableId, userId: userId)
    }
}
