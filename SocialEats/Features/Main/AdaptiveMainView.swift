//  AdaptiveMainView.swift

import SwiftUI

struct AdaptiveMainView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var network: NetworkMonitor
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var navigation = NavigationModel()

    var body: some View {
        Group {
            if sizeClass == .regular {
                iPadLayout
            } else {
                iPhoneLayout
            }
        }
        .environmentObject(navigation)
        // Offline banner floats at the top on every screen
        .safeAreaInset(edge: .top, spacing: 0) {
            if !network.isOnline {
                OfflineBanner()
                    .padding(.horizontal, AppLayout.screenPadding)
                    .padding(.vertical, 4)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut, value: network.isOnline)
        .onChange(of: session.pendingTableId) { _, tableId in
            openPendingTable(tableId)
        }
        .onAppear { openPendingTable(session.pendingTableId) }
    }

    private func openPendingTable(_ tableId: String?) {
        guard let tableId else { return }
        navigation.popToRoot(.home)
        navigation.open(.table(tableId), on: .home)
        session.pendingTableId = nil
    }

    private var iPhoneLayout: some View {
        TabView(selection: $navigation.selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack(path: navigation.path(for: tab)) {
                    rootView(for: tab)
                        .withAppRoutes()
                }
                .tabItem { Label(tab.title, systemImage: tab.systemImage) }
                // Tab bar colour from the prototype (white / #17181D)
                .toolbarBackground(AppColors.surface, for: .tabBar)
                .toolbarBackground(.visible, for: .tabBar)
                .tag(tab)
            }
        }
    }

    private var iPadLayout: some View {
        NavigationSplitView(columnVisibility: sidebarVisibility) {
            List {
                Section {
                    ForEach(AppTab.allCases) { tab in
                        Button {
                            navigation.selectedTab = tab
                        } label: {
                            Label(tab.title, systemImage: tab.systemImage)
                                .foregroundStyle(navigation.selectedTab == tab ? AppColors.primary : AppColors.textPrimary)
                                .font(AppFont.body.weight(navigation.selectedTab == tab ? .semibold : .regular))
                        }
                        .listRowBackground(navigation.selectedTab == tab ? AppColors.primarySoft : Color.clear)
                        .accessibilityAddTraits(navigation.selectedTab == tab ? [.isSelected] : [])
                    }
                }
                Section("Quick actions") {
                    Button {
                        navigation.open(.shakeToMatch, on: .home)
                    } label: {
                        Label("Shake to Match", systemImage: "iphone.radiowaves.left.and.right")
                    }
                    Button {
                        navigation.open(.createTable, on: .home)
                    } label: {
                        Label("Host a Table", systemImage: "plus.circle")
                    }
                    Button {
                        navigation.open(.notifications, on: .home)
                    } label: {
                        Label("Notifications", systemImage: "bell")
                            .badge(session.unreadCount)
                    }
                }
            }
            .navigationTitle("SocialEats")
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .tint(AppColors.primary)
        } detail: {
            NavigationStack(path: navigation.path(for: navigation.selectedTab)) {
                rootView(for: navigation.selectedTab)
                    .withAppRoutes()
            }
            .id(navigation.selectedTab)
        }
        .navigationSplitViewStyle(.balanced)
    }
    
    @available(iOS 16.0, *)
        private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
            Binding(
                get: { navigation.isSidebarShown ? .all : .detailOnly },
                set: { navigation.isSidebarShown = ($0 != .detailOnly) }
            )
        }

    @ViewBuilder
    private func rootView(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeView(container: container)
        case .map: ExploreMapView(container: container)
        case .scan: ReceiptScannerView(container: container)
        case .settings: SettingsView(container: container)
        case .profile: ProfileView(container: container)
        }
    }
}

struct SidebarToggleButton: View {
    @EnvironmentObject private var navigation: NavigationModel
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if sizeClass == .regular && !navigation.isSidebarShown {
            Button {
                withAnimation(.easeInOut) { navigation.isSidebarShown = true }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(AppColors.surface))
            }
            .padding(.leading, AppLayout.screenPadding)
            .accessibilityLabel("Show sidebar")
                        .transition(.opacity)
        }
    }
}
