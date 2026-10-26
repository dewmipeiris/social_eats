//
//  ExploreMapViewModel.swift
//  SocialEats
//
//  MapKit + Core Location — the Map tab (prototype Figure 13), part of the core app:
//   • live pins driven by real Firestore data (not hard-coded)
//   • category filter chips + dietary filters from Settings
//   • your alert radius drawn as a circle (the same radius used for
//     "new table nearby" notifications and geofences)
//

import Foundation
import MapKit
import SwiftUI

@MainActor
final class ExploreMapViewModel: ObservableObject {

    @Published var position: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(center: SampleData.defaultCenter, latitudinalMeters: 3000, longitudinalMeters: 3000)))
    @Published var selectedTableId: String?
    @Published var category: TableCategory?
    @Published var searchText = ""

    /// Chips shown above the map
    let chips: [TableCategory] = [.pizza, .ramen, .burgers, .sushi, .cafe, .tacos]

    private let tablesStore: TablesStore
    private let location: LocationService
    private let settings: SettingsStore

    init(tablesStore: TablesStore, location: LocationService, settings: SettingsStore) {
        self.tablesStore = tablesStore
        self.location = location
        self.settings = settings
    }

    /// The tables shown as pins: live tables, filtered by the chip,
    /// the search box and the dietary choices from Settings.
    /// (Worked out again every time the map screen redraws.)
    var tables: [CommunityTable] {
        var options = TableFilterOptions()
        options.category = category
        options.searchText = searchText
        options.dietaryTags = settings.dietaryTags
        return TableFilter.apply(options, to: tablesStore.tables, userLocation: location.currentLocation)
    }

    convenience init(container: AppContainer) {
        self.init(tablesStore: container.tablesStore, location: container.location, settings: container.settings)
    }

    // MARK: - Derived

    var selectedTable: CommunityTable? {
        guard let selectedTableId else { return nil }
        return tables.first { $0.id == selectedTableId }
    }

    var userCoordinate: CLLocationCoordinate2D? { location.currentLocation?.coordinate }
    var radiusMetres: CLLocationDistance { settings.proximityRadiusKm * 1000 }

    func distanceText(for table: CommunityTable) -> String {
        let metres = table.distance(from: location.currentLocation)
        guard metres != nil else { return "" }
        return "\(DistanceText.short(metres)) (\(DistanceText.walkMinutes(metres)))"
    }

    // MARK: - Actions

    func select(_ table: CommunityTable) {
        selectedTableId = table.id
        withAnimation(.easeInOut) {
            position = .region(MKCoordinateRegion(center: table.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
        }
    }

    func toggle(_ chip: TableCategory) {
        category = (category == chip) ? nil : chip
        selectedTableId = nil
    }

    func recenterOnUser() {
        withAnimation(.easeInOut) {
            position = .userLocation(fallback: .automatic)
        }
    }

    /// Zooms out so every pin is visible.
    func showAllTables() {
        guard !tables.isEmpty else { return }
        let lats = tables.map(\.latitude), lons = tables.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max(0.01, (lats.max()! - lats.min()!) * 1.6),
                                    longitudeDelta: max(0.01, (lons.max()! - lons.min()!) * 1.6))
        withAnimation(.easeInOut) {
            position = .region(MKCoordinateRegion(center: center, span: span))
        }
    }
}
