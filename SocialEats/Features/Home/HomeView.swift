//
//  HomeView.swift
//  SocialEats
//
//  Prototype Figure 6 — Dashboard:
//  greeting, Shake to Match banner, search bar, category chips,
//  "Active Tables Near You" (live from Firestore) and a + button to host.
//

import SwiftUI

struct HomeView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: NavigationModel
    @EnvironmentObject private var tablesStore: TablesStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel: DashboardViewModel

    /// Bookmarked table ids (kept on the phone)
    @AppStorage("savedTableIds") private var savedTableIdsRaw = ""

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(container: container))
    }

    /// iPad shows 2 columns of cards, iPhone shows 1
    private var columns: [GridItem] {
        sizeClass == .regular
            ? [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
            : [GridItem(.flexible())]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                shakeBanner
                searchBar
                categoryChips
                if !viewModel.myUpcomingTables.isEmpty {
                    upcomingSection
                }
                tablesSection
            }
            .padding(.horizontal, AppLayout.screenPadding)
            .padding(.bottom, 90)
        }
        .refreshable { await viewModel.refresh() }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(title: "Home",
                      onSearch: { navigation.open(.search, on: navigation.selectedTab) },
                      avatarName: session.currentUser?.displayName ?? "Foodie",
                      onAvatar: { navigation.selectedTab = .profile })
        }
        .overlay(alignment: .bottomTrailing) { hostButton }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Sections

    private var greeting: some View {
        HStack(spacing: 12) {
            AvatarView(name: session.currentUser?.displayName ?? "Foodie", size: 46, showsOnlineDot: true)
            VStack(alignment: .leading, spacing: 2) {
                OverlineText(text: "Welcome back")
                Text("Hello, \(viewModel.greetingName) 👋")
                    .font(AppFont.title)
                    .foregroundStyle(AppColors.textPrimary)
            }
            Spacer()
            CircleIconButton(systemImage: "bell",
                             accessibilityText: session.unreadCount > 0 ? "Notifications, \(session.unreadCount) unread" : "Notifications",
                             showsBadge: session.unreadCount > 0) {
                navigation.open(.notifications, on: navigation.selectedTab)
            }
        }
        .padding(.top, 4)
    }

    private var shakeBanner: some View {
        Button {
            navigation.open(.shakeToMatch, on: navigation.selectedTab)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Label("LIVE DISCOVERY", systemImage: "bolt.fill")
                        .font(AppFont.overline)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(.white.opacity(0.22)))
                    Text("Shake to Match!")
                        .font(AppFont.title)
                    Text("Shake your phone to find an instant open table nearby")
                        .font(AppFont.footnote)
                        .opacity(0.9)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.system(size: 24, weight: .semibold))
                    .frame(width: 54, height: 54)
                    .background(Circle().fill(.white.opacity(0.22)))
            }
            .foregroundStyle(.white)
            .padding(16)
            .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(AppColors.shakeGradient))
            .shadow(color: AppColors.primary.opacity(0.3), radius: 10, y: 5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Shake to Match. Find an instant open table nearby")
    }

    private var searchBar: some View {
        Button {
            navigation.open(.search, on: navigation.selectedTab)
        } label: {
            HStack {
                Image(systemName: "magnifyingglass")
                Text("Search pizza, sushi, cafes...")
                Spacer()
                Image(systemName: "mic")
            }
            .font(AppFont.body)
            .foregroundStyle(AppColors.textSecondary)
            .inputFieldStyle()
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Search tables, with voice search")
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ChipView(title: "All", isSelected: viewModel.selectedCategory == nil) {
                    viewModel.select(nil)
                }
                ForEach(viewModel.categories) { category in
                    ChipView(title: category.title, icon: category.emoji,
                             isSelected: viewModel.selectedCategory == category) {
                        Haptics.selection()
                        viewModel.select(category)
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: "Your Upcoming Tables")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(viewModel.myUpcomingTables) { table in
                        Button {
                            navigation.open(.table(table.id), on: navigation.selectedTab)
                        } label: {
                            HStack(spacing: 10) {
                                TableThumbnail(category: table.category, size: 44, cornerRadius: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(table.title)
                                        .font(AppFont.subheadline.weight(.semibold))
                                        .foregroundStyle(AppColors.textPrimary)
                                        .lineLimit(1)
                                    Text(table.startTime.friendlyDayTime)
                                        .font(AppFont.caption)
                                        .foregroundStyle(AppColors.primary)
                                }
                            }
                            .frame(width: 230, alignment: .leading)
                            .cardStyle(padding: 10)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(table.title), \(table.startTime.friendlyDayTime)")
                    }
                }
            }
        }
    }

    private var tablesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "Active Tables Near You", showsLiveDot: true,
                          actionTitle: "See map") { navigation.selectedTab = .map }

            if tablesStore.isShowingCachedData {
                Label("Showing saved tables from your last visit", systemImage: "externaldrive")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.amber)
            }

            if viewModel.isLoading {
                // Skeleton cards while the first snapshot loads
                ForEach(0..<3, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: AppLayout.cardRadius)
                        .fill(AppColors.surface)
                        .frame(height: 100)
                        .redacted(reason: .placeholder)
                        .overlay(ProgressView().tint(AppColors.primary))
                }
                .accessibilityLabel("Loading tables")
            } else if viewModel.visibleTables.isEmpty {
                EmptyStateView(systemImage: "fork.knife.circle",
                               title: "No tables here yet",
                               message: viewModel.emptyMessage,
                               buttonTitle: "Host a Table") {
                    navigation.open(.createTable, on: navigation.selectedTab)
                }
                .cardStyle()
            } else {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(viewModel.visibleTables) { table in
                        // onTapGesture (not Button) so the bookmark button inside still works
                        TableRowCard(table: table,
                                     distanceText: viewModel.distanceText(for: table),
                                     isSaved: isSaved(table.id),
                                     onToggleSave: { toggleSaved(table.id) })
                            .onTapGesture {
                                navigation.open(.table(table.id), on: navigation.selectedTab)
                            }
                            .accessibilityAddTraits(.isButton)
                            .accessibilityAction {
                                navigation.open(.table(table.id), on: navigation.selectedTab)
                            }
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: viewModel.visibleTables.map(\.id))
            }
        }
    }

    /// Floating coral "+" button to host a new table (Feature 9).
    private var hostButton: some View {
        Button {
            navigation.open(.createTable, on: navigation.selectedTab)
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.onPrimary)
                .frame(width: 58, height: 58)
                .background(Circle().fill(AppColors.primary))
                .shadow(color: AppColors.primary.opacity(0.4), radius: 10, y: 5)
        }
        .padding(20)
        .accessibilityLabel("Host a new table")
    }

    // MARK: - Bookmarks

    private func isSaved(_ id: String) -> Bool {
        savedTableIdsRaw.split(separator: ",").contains(Substring(id))
    }

    private func toggleSaved(_ id: String) {
        var ids = Set(savedTableIdsRaw.split(separator: ",").map(String.init))
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        savedTableIdsRaw = ids.joined(separator: ",")
        Haptics.selection()
    }
}

#Preview {
    let container = AppContainer.preview
    return NavigationStack {
        HomeView(container: container)
    }
    .environmentObject(container)
    .environmentObject(container.session)
    .environmentObject(container.tablesStore)
    .environmentObject(NavigationModel())
}
