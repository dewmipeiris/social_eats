//
//  Navigation.swift
//  SocialEats
//
//  Every screen you can "push" to, in one enum. Any NavigationStack in
//  the app can open any of these with `path.append(.table(id))`.
//

import SwiftUI

enum AppRoute: Hashable {
    case table(String)          // Restaurant / table detail
    case chat(String)           // Table group chat
    case pass(String)           // Digital dining pass (offline)
    case myPasses               // All saved passes
    case notifications
    case search
    case shakeToMatch
    case createTable
    case scanner                // Receipt scanner
    case editTasteProfile
}

/// The five tabs from the prototype's bottom bar (plus Notifications on iPad).
enum AppTab: String, CaseIterable, Identifiable, Hashable {
    case home, map, scan, settings, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .map: return "Map"
        case .scan: return "Scan"
        case .settings: return "Settings"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .map: return "map"
        case .scan: return "qrcode.viewfinder"
        case .settings: return "gearshape"
        case .profile: return "person"
        }
    }
}

/// Remembers which tab is selected and the navigation path in each tab.
@MainActor
final class NavigationModel: ObservableObject {
    @Published var selectedTab: AppTab = .home
    @Published var paths: [AppTab: NavigationPath] = [:]

    /// Two-way binding to one tab's path (for NavigationStack(path:))
    func path(for tab: AppTab) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[tab] ?? NavigationPath() },
            set: { self.paths[tab] = $0 }
        )
    }

    /// Opens a screen on the given tab (switching to it first).
    func open(_ route: AppRoute, on tab: AppTab = .home) {
        selectedTab = tab
        var path = paths[tab] ?? NavigationPath()
        path.append(route)
        paths[tab] = path
    }

    func popToRoot(_ tab: AppTab) {
        paths[tab] = NavigationPath()
    }
}

/// Attaches the destination for every AppRoute to a NavigationStack.
struct AppRouteDestinations: ViewModifier {
    @EnvironmentObject private var container: AppContainer

    func body(content: Content) -> some View {
        content.navigationDestination(for: AppRoute.self) { route in
            switch route {
            case .table(let id):
                TableDetailView(tableId: id, container: container)
            case .chat(let id):
                TableChatView(tableId: id, container: container)
            case .pass(let id):
                DigitalPassView(tableId: id, container: container)
            case .myPasses:
                MyPassesView(container: container)
            case .notifications:
                NotificationsView()
            case .search:
                SearchView(container: container)
            case .shakeToMatch:
                ShakeToMatchView(container: container)
            case .createTable:
                CreateTableView(container: container)
            case .scanner:
                ReceiptScannerView(container: container)
            case .editTasteProfile:
                EditTasteProfileView()
            }
        }
    }
}

extension View {
    func withAppRoutes() -> some View {
        modifier(AppRouteDestinations())
    }
}

/// Wraps ProfileSetupView in edit mode with the user's current choices.
struct EditTasteProfileView: View {
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        let user = session.currentUser
        ProfileSetupView(mode: .edit, draft: TasteProfileDraft(
            ambiences: user?.ambiences ?? [],
            cuisines: user?.cuisines ?? [],
            diningStyle: user?.diningStyle ?? .smallGroup,
            dietaryTags: user?.dietaryTags ?? []
        ))
    }
}
