//  TableDetailViewModel.swift

import Foundation
import MapKit
import Combine
import UIKit

@MainActor
final class TableDetailViewModel: ObservableObject {

    @Published private(set) var table: CommunityTable?
    @Published private(set) var isLoading = true
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?
    @Published var confirmedReservation: Reservation?
    @Published private(set) var walkingText: String = ""

    let tableId: String
    private let tableService: TableServicing
    private let reservations: ReservationManager
    private let session: SessionStore
    private let location: LocationService
    private var listener: ListenerToken?
    private var hasRequestedRoute = false

    init(tableId: String, tableService: TableServicing, reservations: ReservationManager,
         session: SessionStore, location: LocationService, initialTable: CommunityTable?) {
        self.tableId = tableId
        self.tableService = tableService
        self.reservations = reservations
        self.session = session
        self.location = location
        self.table = initialTable
        self.isLoading = initialTable == nil
    }

    convenience init(tableId: String, container: AppContainer) {
        self.init(tableId: tableId,
                  tableService: container.tableService,
                  reservations: container.reservations,
                  session: container.session,
                  location: container.location,
                  initialTable: container.tablesStore.table(id: tableId))
    }

    var userId: String? { session.userId }
    var isAttending: Bool { table?.isAttending(userId) ?? false }
    var isHost: Bool { table?.isHost(userId) ?? false }

    var distanceText: String {
        DistanceText.away(table?.distance(from: location.currentLocation))
    }

    var joinButtonTitle: String {
        guard let table else { return "Join This Table Now" }
        if isAttending { return "View My Pass" }
        if table.isFull { return "Table Full" }
        // You can join until 30 minutes after  the start time
        if table.joinBlockReason(for: userId ?? "") == .tableExpired { return "Meetup Already Started" }
        return "Join This Table Now"
    }

    var canJoin: Bool {
        guard let table, let userId else { return false }
        return table.joinBlockReason(for: userId) == nil
    }

    func start() {
        guard listener == nil else { return }
        listener = tableService.listenToTable(id: tableId) { [weak self] table in
            Task { @MainActor in
                guard let self else { return }
                self.isLoading = false
                if let table { self.table = table }
                if self.table == nil { self.errorMessage = TableJoinError.notFound.localizedDescription }
                await self.loadWalkingTime()
            }
        }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    func join() async {
        guard let table, let user = session.currentUser else { return }
        isWorking = true
        errorMessage = nil
        do {
            let reservation = try await reservations.join(table, user: user)
            Haptics.success()
            confirmedReservation = reservation
        } catch BiometricError.cancelled {

        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        isWorking = false
    }

    func cancelSeat() async {
        guard let table, let userId else { return }
        isWorking = true
        errorMessage = nil
        do {
            try await reservations.cancel(table, userId: userId)
            Haptics.success()
        } catch BiometricError.cancelled {
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        isWorking = false
    }

    func changeTime(to newTime: Date) async -> Bool {
        guard let table, let userId else { return false }
        guard newTime > Date() else {
            errorMessage = "Please choose a time in the future."
            return false
        }
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }
        do {
            try await reservations.changeTime(of: table, to: newTime, userId: userId)
            Haptics.success()
            return true
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
            return false
        }
    }

    func openWalkingDirections() {
        guard let table else { return }
        let link = "https://www.google.com/maps/dir/?api=1&destination=\(table.latitude),\(table.longitude)&travelmode=walking"
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func loadWalkingTime() async {
        guard let table else { return }
        let straightLine = table.distance(from: location.currentLocation)
        walkingText = DistanceText.walkMinutes(straightLine)

        guard !hasRequestedRoute, let userLocation = location.currentLocation else { return }
        hasRequestedRoute = true

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userLocation.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: table.coordinate))
        request.transportType = .walking

        if let response = try? await MKDirections(request: request).calculateETA() {
            let minutes = max(1, Int((response.expectedTravelTime / 60).rounded()))
            walkingText = "\(minutes) min walk"
        }
    }
}
