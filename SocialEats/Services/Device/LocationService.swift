//  LocationService.swift

import Foundation
import CoreLocation
import Combine
import UIKit

final class LocationService: NSObject, ObservableObject, CLLocationManagerDelegate {

    @Published private(set) var currentLocation: CLLocation?
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    var onEnterVenue: ((String, String) -> Void)?

    var onSignificantMove: (() -> Void)?
    private var isSignificantMonitoringOn = false

    static let geofenceRadius: CLLocationDistance = 150

    private let manager = CLLocationManager()
    private var monitor: CLMonitor?
    private var monitorTask: Task<Void, Never>?

    private var watchedVenues: [String: String] {
        get { UserDefaults.standard.dictionary(forKey: "watchedVenues") as? [String: String] ?? [:] }
        set { UserDefaults.standard.set(newValue, forKey: "watchedVenues") }
    }

    override init() {
        super.init()
        authorizationStatus = manager.authorizationStatus
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    func requestPermission() {
        if authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if isAuthorized {
            manager.startUpdatingLocation()
        }
    }

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

    func stopGeofence(tableId: String) {
        watchedVenues[tableId] = nil
        Task {
            let monitor = await ensureMonitor()
            await monitor.remove(tableId)
        }
    }

    private func startGeofenceEvents() {
        Task { _ = await ensureMonitor() }
    }

    private func ensureMonitor() async -> CLMonitor {
        if let monitor { return monitor }
        let newMonitor = await CLMonitor("SocialEatsVenueMonitor")
        monitor = newMonitor

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
