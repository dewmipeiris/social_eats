//
//  ShakeToMatchViewModel.swift
//  SocialEats
//
//  Proposal Advanced Feature 2 — Motion-Triggered Gesture Discovery.
//  Core Motion accelerometer > 2.5g  ->  haptic buzz  ->  random open
//  table within your radius (favourite cuisines first)  ->  preview card.
//

import Foundation
import CoreLocation
import Combine

/// A dot on the radar.
struct RadarBlip: Identifiable, Equatable {
    let id: String
    let name: String
    let detail: String
    /// 0...1 distance from the centre of the radar
    let radius: Double
    /// Angle in radians (0 = north)
    let angle: Double
}

@MainActor
final class ShakeToMatchViewModel: ObservableObject {

    @Published private(set) var match: CommunityTable?
    @Published private(set) var isSearching = false
    @Published private(set) var liveForce: Double = 1.0
    @Published private(set) var noMatchFound = false
    @Published var errorMessage: String?
    @Published var confirmedReservation: Reservation?
    @Published private(set) var isJoining = false

    private let motion: MotionServicing
    private let tablesStore: TablesStore
    private let location: LocationService
    private let settings: SettingsStore
    private let session: SessionStore
    private let reservations: ReservationManager

    init(motion: MotionServicing, tablesStore: TablesStore, location: LocationService,
         settings: SettingsStore, session: SessionStore, reservations: ReservationManager) {
        self.motion = motion
        self.tablesStore = tablesStore
        self.location = location
        self.settings = settings
        self.session = session
        self.reservations = reservations

        motion.onShake = { [weak self] in
            Task { @MainActor in await self?.handleShake() }
        }
        motion.onForceUpdate = { [weak self] force in
            Task { @MainActor in self?.liveForce = force }
        }
    }

    convenience init(container: AppContainer) {
        self.init(motion: MotionService(), tablesStore: container.tablesStore, location: container.location,
                  settings: container.settings, session: container.session, reservations: container.reservations)
    }

    // MARK: - Derived

    var isMotionAvailable: Bool { motion.isAvailable }

    /// How far away a matched table can be.
    /// (The proposal said 1 km; changed to 5 km after testing, because in a real city
    /// there often isn't an open table within 1 km. Mention this in the report.)
    static let matchRadiusKm = 2.0

    var radiusText: String { "\(Int(Self.matchRadiusKm)) km" }

    /// Open tables inside the radius, positioned on the radar by real bearing.
    var blips: [RadarBlip] {
        let userLocation = location.currentLocation
        let maxMetres = Self.matchRadiusKm * 1000
        var options = TableFilterOptions()
        options.radiusKm = Self.matchRadiusKm
        options.dietaryTags = settings.dietaryTags
        options.hideFull = true

        return TableFilter.apply(options, to: tablesStore.tables, userLocation: userLocation)
            .filter { !$0.isAttending(session.userId) }
            .prefix(6)
            .map { table in
                let distance = table.distance(from: userLocation) ?? maxMetres / 2
                return RadarBlip(
                    id: table.id,
                    name: table.venueName,
                    detail: "\(DistanceText.short(distance)) • \(table.seatsLeft) seat\(table.seatsLeft == 1 ? "" : "s")",
                    radius: min(0.92, max(0.3, distance / maxMetres)),
                    angle: Self.bearing(from: userLocation?.coordinate, to: table.coordinate)
                )
            }
    }

    var matchDistanceText: String {
        guard let match else { return "" }
        return DistanceText.away(match.distance(from: location.currentLocation))
    }

    // MARK: - Lifecycle

    func start() { motion.start() }
    func stop() { motion.stop() }

    // MARK: - Shake

    /// Called by Core Motion (or the Simulator shake / test button).
    func handleShake() async {
        guard !isSearching else { return }
        Haptics.impact(.heavy)
        isSearching = true
        noMatchFound = false

        // Short "radar sweep" so the result feels earned
        try? await Task.sleep(nanoseconds: 900_000_000)

        let favourites = (session.currentUser?.cuisines ?? []).flatMap(\.matchingCategories)
        match = TableFilter.randomMatch(
            from: tablesStore.tables,
            userId: session.userId,
            favouriteCategories: favourites,
            userLocation: location.currentLocation,
            radiusKm: Self.matchRadiusKm,
            dietaryTags: settings.dietaryTags,
            excluding: match?.id
        )
        noMatchFound = (match == nil)
        isSearching = false
        if match != nil { Haptics.success() }
    }

    /// "Reserve Free Hold" — same Face ID + transaction flow as the detail screen.
    func reserveMatch() async {
        guard let match, let user = session.currentUser else { return }
        isJoining = true
        do {
            confirmedReservation = try await reservations.join(match, user: user)
        } catch BiometricError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
        }
        isJoining = false
    }

    // MARK: - Maths

    /// Compass bearing (radians) from the user to a table.
    static func bearing(from start: CLLocationCoordinate2D?, to end: CLLocationCoordinate2D) -> Double {
        // No location yet: spread blips around using the coordinate itself
        guard let start else { return (end.latitude * 1000 + end.longitude * 1000).truncatingRemainder(dividingBy: 2 * .pi) }
        let lat1 = start.latitude * .pi / 180, lat2 = end.latitude * .pi / 180
        let deltaLon = (end.longitude - start.longitude) * .pi / 180
        let y = sin(deltaLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(deltaLon)
        return atan2(y, x)
    }
}

