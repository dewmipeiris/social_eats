//
//  DashboardViewModel.swift
//  SocialEats
//
//  Proposal MVP Feature 3 — Dashboard.
//  Uses Combine to re-filter the live table list automatically whenever:
//   • Firestore pushes new tables
//   • the user moves (new location)
//   • a category chip is tapped
//   • dietary preferences / radius change in Settings
//

import Foundation
import Combine
import CoreLocation

@MainActor
final class DashboardViewModel: ObservableObject {

    // MARK: - Outputs
    @Published private(set) var visibleTables: [CommunityTable] = []
    @Published private(set) var myUpcomingTables: [CommunityTable] = []
    @Published private(set) var userLocation: CLLocation?

    // MARK: - Inputs
    /// nil = "All" chip
    @Published var selectedCategory: TableCategory?

    /// Chips shown in the horizontal scroller (matches the prototype order)
    let categories: [TableCategory] = [.pizza, .sushi, .cafe, .student, .tacos, .ramen, .burgers, .coWork]

    private let tablesStore: TablesStore
    private let settings: SettingsStore
    private let session: SessionStore
    private var cancellables = Set<AnyCancellable>()

    init(tablesStore: TablesStore,
         locationPublisher: AnyPublisher<CLLocation?, Never>,
         settings: SettingsStore,
         session: SessionStore) {
        self.tablesStore = tablesStore
        self.settings = settings
        self.session = session

        // Combine: whenever ANY input changes, rebuild the visible list
        Publishers.CombineLatest4(
            tablesStore.$tables,
            locationPublisher,
            $selectedCategory,
            settings.$dietaryTags
        )
        .combineLatest(settings.$proximityRadiusKm)
        .receive(on: RunLoop.main)
        .sink { [weak self] values, radius in
            let (tables, location, category, dietary) = values
            self?.rebuild(tables: tables, location: location, category: category,
                          dietary: dietary, radiusKm: radius)
        }
        .store(in: &cancellables)
    }

    /// Convenience init used by the real app.
    convenience init(container: AppContainer) {
        self.init(tablesStore: container.tablesStore,
                  locationPublisher: container.location.$currentLocation.eraseToAnyPublisher(),
                  settings: container.settings,
                  session: container.session)
    }

    // MARK: - State for the view

    var isLoading: Bool { tablesStore.isLoading && visibleTables.isEmpty }
    var errorMessage: String? { tablesStore.errorMessage }
    var greetingName: String { session.currentUser?.firstName ?? "Foodie" }

    /// Message for the empty state (changes if filters are hiding tables)
    var emptyMessage: String {
        if selectedCategory != nil || !settings.dietaryTags.isEmpty {
            return "No tables match your filters right now. Try \"All\" or widen your radius in Settings."
        }
        return "No open tables nearby yet. Be the first — host one!"
    }

    func select(_ category: TableCategory?) {
        selectedCategory = (selectedCategory == category) ? nil : category
    }

    func distanceText(for table: CommunityTable) -> String {
        DistanceText.away(table.distance(from: userLocation))
    }

    func refresh() async {
        tablesStore.refresh()
        try? await Task.sleep(nanoseconds: 600_000_000)
    }

    // MARK: - Private

    private func rebuild(tables: [CommunityTable], location: CLLocation?, category: TableCategory?,
                         dietary: [DietaryTag], radiusKm: Double) {
        userLocation = location

        var options = TableFilterOptions()
        options.category = category
        options.dietaryTags = dietary
        // Only limit by radius when we actually know where the user is
        options.radiusKm = location == nil ? nil : radiusKm

        let userId = session.userId
        visibleTables = TableFilter.apply(options, to: tables, userLocation: location)
            .filter { !$0.isAttending(userId) }

        myUpcomingTables = tables
            .filter { $0.isAttending(userId) && $0.startTime.addingTimeInterval(3 * 3600) > Date() }
            .sorted { $0.startTime < $1.startTime }
    }
}
