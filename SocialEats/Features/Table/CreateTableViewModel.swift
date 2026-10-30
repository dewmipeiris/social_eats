//  CreateTableViewModel.swift

import Foundation
import MapKit
import Combine

struct VenueResult: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let address: String
    let coordinate: CLLocationCoordinate2D

    static func == (lhs: VenueResult, rhs: VenueResult) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class CreateTableViewModel: ObservableObject {

    @Published var title = ""
    @Published var about = ""
    @Published var category: TableCategory = .cafe
    @Published var startTime = Date().addingTimeInterval(2 * 60 * 60)
    @Published var capacity = 4
    @Published var dietaryTags: Set<DietaryTag> = []
    @Published var pricePerPerson: Double = 2000
    @Published var perk = ""

    @Published var venueQuery = ""
    @Published private(set) var venueResults: [VenueResult] = []
    @Published private(set) var selectedVenue: VenueResult?
    @Published private(set) var isSearchingVenues = false

    @Published private(set) var isSaving = false
    @Published var errorMessage: String?
    @Published private(set) var createdTableId: String?

    static let capacityRange = 2...8

    private let tableService: TableServicing
    private let reservations: ReservationManager
    private let session: SessionStore
    private let location: LocationService
    private var searchTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    init(tableService: TableServicing, reservations: ReservationManager,
         session: SessionStore, location: LocationService) {
        self.tableService = tableService
        self.reservations = reservations
        self.session = session
        self.location = location

        $venueQuery
            .removeDuplicates()
            .debounce(for: .milliseconds(400), scheduler: RunLoop.main)
            .sink { [weak self] query in self?.searchVenues(query) }
            .store(in: &cancellables)
    }

    convenience init(container: AppContainer) {
        self.init(tableService: container.tableService, reservations: container.reservations,
                  session: container.session, location: container.location)
    }

    var titleError: String? {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        return trimmed.count < 3 ? "Give your table a name (3+ characters)" : nil
    }

    var timeError: String? {
        startTime < Date().addingTimeInterval(10 * 60) ? "Pick a time at least 10 minutes from now" : nil
    }

    var isValid: Bool {
        title.trimmingCharacters(in: .whitespaces).count >= 3
            && selectedVenue != nil
            && timeError == nil
            && Self.capacityRange.contains(capacity)
    }

    var seatsSummary: String {
        "You (Seat #1) + \(capacity - 1) guest seat\(capacity - 1 == 1 ? "" : "s")"
    }

    func toggle(_ tag: DietaryTag) {
        if dietaryTags.contains(tag) { dietaryTags.remove(tag) } else { dietaryTags.insert(tag) }
    }

    func selectVenue(_ venue: VenueResult) {
        selectedVenue = venue
        venueQuery = venue.name
        venueResults = []
    }

    func clearVenue() {
        selectedVenue = nil
        venueQuery = ""
    }

    private func searchVenues(_ query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2, trimmed != selectedVenue?.name else {
            venueResults = []
            return
        }

        let center = location.currentLocation?.coordinate ?? SampleData.defaultCenter
        searchTask = Task {
            isSearchingVenues = true
            defer { isSearchingVenues = false }

            let request = MKLocalSearch.Request()
            request.naturalLanguageQuery = trimmed
            request.resultTypes = .pointOfInterest
            request.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .brewery, .winery, .foodMarket])
            request.region = MKCoordinateRegion(center: center, latitudinalMeters: 10_000, longitudinalMeters: 10_000)

            guard let response = try? await MKLocalSearch(request: request).start(), !Task.isCancelled else { return }
            venueResults = response.mapItems.prefix(6).map { item in
                VenueResult(name: item.name ?? trimmed,
                            address: item.placemark.title ?? "",
                            coordinate: item.placemark.coordinate)
            }
        }
    }

    func useCurrentLocationAsVenue() {
        let name = venueQuery.trimmingCharacters(in: .whitespaces)
        guard let coordinate = location.currentLocation?.coordinate else {
            errorMessage = "Turn on location to use your current spot."
            return
        }
        selectVenue(VenueResult(name: name.isEmpty ? "My spot" : name, address: "Near your location", coordinate: coordinate))
    }

    func createTable() async {
        guard isValid, let venue = selectedVenue, let user = session.currentUser else {
            errorMessage = "Please complete the form first."
            return
        }
        isSaving = true
        errorMessage = nil

        var table = CommunityTable(
            id: "",
            title: title.trimmingCharacters(in: .whitespaces),
            about: about.isEmpty ? "Come hang out over good food! 🍽️" : about,
            venueName: venue.name,
            venueAddress: venue.address,
            category: category,
            hostId: user.id,
            hostName: user.displayName,
            hostRating: user.hostRating,
            hostTablesHosted: user.tablesHosted + 1,
            startTime: startTime,
            latitude: venue.coordinate.latitude,
            longitude: venue.coordinate.longitude,
            capacity: capacity,
            attendeeIds: [user.id],
            attendeeNames: [user.displayName],
            dietaryTags: DietaryTag.allCases.filter { dietaryTags.contains($0) },
            pricePerPerson: pricePerPerson,
            perk: perk.isEmpty ? nil : perk,
            tableNumber: Int.random(in: 100...999),
            createdAt: Date()
        )

        do {
            table.id = try await tableService.createTable(table)

            reservations.afterSeatConfirmed(table, reservation: Reservation.make(from: table, userId: user.id),
                                            userId: user.id)
            var updatedUser = user
            updatedUser.tablesHosted += 1
            try? await session.updateProfile(updatedUser)

            Haptics.success()
            createdTableId = table.id
        } catch {
            errorMessage = error.localizedDescription
            Haptics.error()
        }
        isSaving = false
    }
}
