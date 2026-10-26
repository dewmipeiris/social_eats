//
//  NotificationService.swift
//  SocialEats
//
//  Push notifications with the UserNotifications framework
//  (proposal MVP Feature 5). We send three kinds of alerts:
//   1. "New table nearby"  – when a host opens a table inside your radius
//   2. "Meetup in 1 hour"  – reminder before a table you joined
//   3. "You've arrived"    – geofence alert when you walk into the venue area
//  Tapping an alert opens that table's screen (deep link).
//

import Foundation
import UserNotifications

protocol NotificationServicing: AnyObject {
    func requestPermission() async -> Bool
    func notifyNewTableNearby(_ table: CommunityTable, distanceMetres: Double?)
    func scheduleMeetupReminder(for table: CommunityTable)
    func cancelMeetupReminder(tableId: String)
    func notifyArrivedAtVenue(tableId: String, venueName: String)
    func notifyKarmaEarned(points: Int, venueName: String)
}

final class NotificationService: NSObject, NotificationServicing, UNUserNotificationCenterDelegate {

    /// Key used to store the table id inside each notification
    static let tableIdKey = "tableId"

    private let center = UNUserNotificationCenter.current()

    /// Called when the user taps a notification (set by AppRouter).
    var onOpenTable: ((String) -> Void)?

    override init() {
        super.init()
        center.delegate = self
    }

    func requestPermission() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            return false
        }
    }

    // MARK: - Sending

    func notifyNewTableNearby(_ table: CommunityTable, distanceMetres: Double?) {
        let content = UNMutableNotificationContent()
        content.title = "New table nearby \(table.category.emoji)"
        let seatsText = table.seatsLeft == 1 ? "1 seat left" : "\(table.seatsLeft) seats left"
        content.body = "\(table.hostName) just opened \"\(table.title)\" \(DistanceText.away(distanceMetres)) — \(seatsText)!"
        content.sound = .default
        content.userInfo = [Self.tableIdKey: table.id]
        content.threadIdentifier = "nearby"

        // Deliver straight away (1 second trigger)
        add(id: "nearby-\(table.id)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    }

    func scheduleMeetupReminder(for table: CommunityTable) {
        let reminderDate = table.startTime.addingTimeInterval(-60 * 60)
        guard reminderDate > Date() else { return }   // too late to remind

        let content = UNMutableNotificationContent()
        content.title = "Meetup in 1 hour ⏰"
        content.body = "\(table.title) at \(table.venueName) starts soon. Check in with the host when you arrive."
        content.sound = .default
        content.userInfo = [Self.tableIdKey: table.id]

        let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: reminderDate)
        add(id: "reminder-\(table.id)", content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false))
    }

    func cancelMeetupReminder(tableId: String) {
        center.removePendingNotificationRequests(withIdentifiers: ["reminder-\(tableId)"])
    }

    func notifyArrivedAtVenue(tableId: String, venueName: String) {
        let content = UNMutableNotificationContent()
        content.title = "You've arrived at \(venueName) 📍"
        content.body = "Open your offline pass and show the QR code to your host."
        content.sound = .default
        content.userInfo = [Self.tableIdKey: tableId]
        add(id: "arrived-\(tableId)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    }

    func notifyKarmaEarned(points: Int, venueName: String) {
        let content = UNMutableNotificationContent()
        content.title = "+\(points) Foodie Karma! ⭐️"
        content.body = "Your receipt from \(venueName) was verified."
        content.sound = .default
        add(id: "karma-\(UUID().uuidString)", content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false))
    }

    private func add(id: String, content: UNMutableNotificationContent, trigger: UNNotificationTrigger) {
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
            if let error { print("⚠️ Notification error: \(error.localizedDescription)") }
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    /// Show banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }

    /// User tapped a notification -> open the matching table.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if let tableId = response.notification.request.content.userInfo[Self.tableIdKey] as? String {
            DispatchQueue.main.async { [weak self] in
                self?.onOpenTable?(tableId)
            }
        }
        completionHandler()
    }
}

/// Test version that just records what was sent.
final class MockNotificationService: NotificationServicing {
    private(set) var nearbyAlerts: [String] = []
    private(set) var reminders: [String] = []
    private(set) var arrivals: [String] = []

    func requestPermission() async -> Bool { true }
    func notifyNewTableNearby(_ table: CommunityTable, distanceMetres: Double?) { nearbyAlerts.append(table.id) }
    func scheduleMeetupReminder(for table: CommunityTable) { reminders.append(table.id) }
    func cancelMeetupReminder(tableId: String) { reminders.removeAll { $0 == tableId } }
    func notifyArrivedAtVenue(tableId: String, venueName: String) { arrivals.append(tableId) }
    func notifyKarmaEarned(points: Int, venueName: String) {}
}
