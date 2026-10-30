//  ExploreMapViewModel.swift

import Combine
import Foundation
import MapKit
import SwiftUI
import UIKit

@MainActor
final class ExploreMapViewModel: ObservableObject {

    @Published var position: MapCameraPosition = .userLocation(fallback: .region(
        MKCoordinateRegion(center: SampleData.defaultCenter, latitudinalMeters: 3000, longitudinalMeters: 3000)))
    @Published var selectedTableId: String?
    @Published var category: TableCategory?
    @Published var searchText = ""
    @Published private(set) var route: MKRoute?
    @Published private(set) var isLoadingRoute = false

    let chips: [TableCategory] = [.pizza, .ramen, .burgers, .sushi, .cafe, .tacos]

    private let tablesStore: TablesStore
    private let location: LocationService
    private let settings: SettingsStore

    init(tablesStore: TablesStore, location: LocationService, settings: SettingsStore) {
        self.tablesStore = tablesStore
        self.location = location
        self.settings = settings
    }

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

    var selectedTable: CommunityTable? {
        guard let selectedTableId else { return nil }
        return tables.first { $0.id == selectedTableId }
    }

    var userCoordinate: CLLocationCoordinate2D? { location.currentLocation?.coordinate }
    var radiusMetres: CLLocationDistance { settings.proximityRadiusKm * 1000 }
    var hasUserLocation: Bool { location.currentLocation != nil }

    /// Short text for lists: "1.2km (15 min walk)" — or "" if we don't know where you are.
    func distanceText(for table: CommunityTable) -> String {
        let metres = table.distance(from: location.currentLocation)
        guard metres != nil else { return "" }
        return "\(DistanceText.short(metres)) (\(DistanceText.walkMinutes(metres)))"
    }

    func distanceFromYou(for table: CommunityTable) -> String {
        if let route, selectedTableId == table.id {
            let minutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
            return "\(DistanceText.short(route.distance)) • \(minutes) min walk from you"
        }
        if let metres = table.distance(from: location.currentLocation) {
            return "\(DistanceText.short(metres)) • \(DistanceText.walkMinutes(metres)) from you"
        }
        return "Turn on Location to see how far it is"
    }
    
    var straightLine: [CLLocationCoordinate2D]? {
        guard route == nil, let user = userCoordinate, let table = selectedTable else { return nil }
        return [user, table.coordinate]
    }

    func select(_ table: CommunityTable) {
        selectedTableId = table.id
        withAnimation(.easeInOut) {
            position = .region(MKCoordinateRegion(center: table.coordinate, latitudinalMeters: 900, longitudinalMeters: 900))
        }
    }

    func loadRoute() async {
        route = nil
        guard let table = selectedTable, let userCoordinate else { return }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: table.coordinate))
        request.transportType = .walking

        isLoadingRoute = true
        defer { isLoadingRoute = false }
        do {
            let response = try await MKDirections(request: request).calculate()
            guard selectedTableId == table.id, let best = response.routes.first else { return }
            route = best
            let rect = best.polyline.boundingMapRect
            let padding = max(rect.size.width, rect.size.height) * 0.35
            withAnimation(.easeInOut) {
                position = .rect(rect.insetBy(dx: -padding, dy: -padding))
            }
        } catch {
            route = nil
            let a = MKMapPoint(userCoordinate), b = MKMapPoint(table.coordinate)
            let rect = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y),
                                 width: abs(a.x - b.x), height: abs(a.y - b.y))
            let padding = max(rect.size.width, rect.size.height) * 0.35 + 200
            withAnimation(.easeInOut) {
                position = .rect(rect.insetBy(dx: -padding, dy: -padding))
            }
        }
    }

    func openDirections(to table: CommunityTable) {
        let lat = table.latitude, lon = table.longitude
        let link = "https://www.google.com/maps/dir/?api=1&destination=\(lat),\(lon)&travelmode=walking"
        if let url = URL(string: link) {
            UIApplication.shared.open(url)
        }
    }

    func toggle(_ chip: TableCategory) {
        category = (category == chip) ? nil : chip
        selectedTableId = nil
        route = nil
    }

    func recenterOnUser() {
        withAnimation(.easeInOut) {
            position = .userLocation(fallback: .automatic)
        }
    }

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
