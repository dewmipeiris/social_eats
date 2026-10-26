//
//  LocationService.swift
//  SocialEats
//
//  Core Location:
//   • Live user location -> distances on cards, map, "nearby" alerts
//   • GEOFENCING with CLMonitor -> when you walk within 150 m of a venue
//     you have a seat at, we send an "You've arrived" notification
//     (powers the Feature 5 "geofenced alerts").
//

import Foundation
import CoreLocation
import Combine
import UIKit

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    /// Latest known position of the user (nil until permission is given)
    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    /// Called when the user enters a venue geofence (tableId, venueName)
    var onEnterVenue: ((String, String) -> Void)?

    /// Called when iOS wakes the app in the BACKGROUND because the user moved
    /// ~500 m (significant-change service). Used to check for new tables nearby
    /// even when the app is closed (proposal Feature 5, step 1).
    var onSignificantMove: (() -> Void)?
    private var isSignificantMonitoringOn = false

    /// Geofence radius around each venue
    static let geofenceRadius: CLLocationDistance = 150

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?

    /// tableId -> venue name, saved so we still know the name after a relaunch
    private var watchedVenues: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "watchedVenues") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "watchedVenues") }
    }

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters   // saves battery
        manager.distanceFilter = 50                                   // update every 50 m
    }

    // MARK: - Permission & updates

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    /// Asks for "While Using the App" permission (needed for distances).
    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

    /// Asks for "Always" so geofence alerts work with the app closed.
    func requestAlwaysPermission() {
        if authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if isAuthorized {
            manager.startUpdatingLocation()
            startGeofenceEvents()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last, latest.horizontalAccuracy >= 0 else { return }
        currentLocation = latest

        // Woken up in the background by a significant move -> look for new tables
        if UIApplication.shared.applicationState == .background {
            onSignificantMove?()
        }
    }

    // MARK: - Background tracking (significant location changes)

    /// Turns the low-power "significant change" service on or off.
    /// It only runs with "Always" permission and uses cell towers, not GPS,
    /// so it barely uses battery. iOS can even relaunch a closed app with it.
    /// - Parameter status: pass the NEW status when called from a Combine sink
    ///   (@Published sends the value just before the property itself changes).
    func setBackgroundNearbyMonitoring(_ enabled: Bool, status: CLAuthorizationStatus? = nil) {
        let canRun = enabled
            && (status ?? authorizationStatus) == .authorizedAlways
            && CLLocationManager.significantLocationChangeMonitoringAvailable()

        if canRun && !isSignificantMonitoringOn {
            manager.startMonitoringSignificantLocationChanges()
            isSignificantMonitoringOn = true
        } else if !canRun && isSignificantMonitoringOn {
            manager.stopMonitoringSignificantLocationChanges()
            isSignificantMonitoringOn = false
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("⚠️ Location error: \(error.localizedDescription)")
    }

    // MARK: - Geofencing (CLMonitor, iOS 17+)

    /// Starts watching the area around a venue the user has a seat at.
    func startGeofence(for table: CommunityTable) {
        watchedVenues[table.id] = table.venueName
        Task {
            let monitor = await ensureMonitor()
            let condition = CLMonitor.CircularGeographicCondition(
                center: table.coordinate,
                radius: Self.geofenceRadius
            )
            await monitor.add(condition, identifier: table.id, assuming: .unsatisfied)
        }
    }

    /// Stops watching a venue (seat cancelled or meal finished).
    func stopGeofence(tableId: String) {
        watchedVenues[tableId] = nil
        Task {
            let monitor = await ensureMonitor()
            await monitor.remove(tableId)
        }
    }

    /// Creates the CLMonitor once and starts listening for enter events.
    private func startGeofenceEvents() {
        Task { _ = await ensureMonitor() }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let newMonitor = await CLMonitor("SocialEatsVenueMonitor")
        monitor = newMonitor

        // Listen forever for "entered region" events
        monitorTask = Task { [weak self] in
            do {
                for try await event in await newMonitor.events {
                    guard event.state == .satisfied else { continue }   // satisfied = inside
                    let tableId = event.identifier
                    await MainActor.run {
                        let venue = self?.watchedVenues[tableId] ?? "your venue"
                        self?.onEnterVenue?(tableId, venue)
                    }
                }
            } catch {
                print("⚠️ Geofence monitor stopped: \(error.localizedDescription)")
            }
        }
        return newMonitor
    }

    deinit {
        monitorTask?.cancel()
    }
}
