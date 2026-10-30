//  GuestBrowseView.swift

import SwiftUI

struct GuestBrowseView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var tablesStore: TablesStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var searchText = ""
    @State private var category: TableCategory?
    @State private var previewTable: CommunityTable?

    private let chips: [TableCategory] = [.pizza, .asian, .cafe, .tacos, .sushi]

    private var tables: [CommunityTable] {
        var options = TableFilterOptions()
        options.category = category
        options.searchText = searchText
        return TableFilter.apply(options, to: tablesStore.tables, userLocation: location.currentLocation)
    }

    private var columns: [GridItem] {
        sizeClass == .regular ? [GridItem(.flexible()), GridItem(.flexible())] : [GridItem(.flexible())]
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    guestBanner

                    HStack {
                        Image(systemName: "magnifyingglass").foregroundStyle(AppColors.textSecondary)
                        TextField("Search open tables nearby...", text: $searchText)
                        Image(systemName: "slider.horizontal.3").foregroundStyle(AppColors.textSecondary)
                    }
                    .inputFieldStyle()

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ChipView(title: "All", isSelected: category == nil) { category = nil }
                            ForEach(chips) { item in
                                ChipView(title: item.title, icon: item.emoji, isSelected: category == item) {
                                    category = (category == item) ? nil : item
                                }
                            }
                        }
                    }

                    HStack {
                        SectionHeader(title: "Live Community Tables", showsLiveDot: true)
                        Text("\(tables.count) active now")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }

                    if tables.isEmpty {
                        EmptyStateView(systemImage: "magnifyingglass",
                                       title: "No tables found",
                                       message: "Try another search or category.")
                    } else {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(tables) { table in
                                TableFeatureCard(table: table,
                                                 distanceText: DistanceText.away(table.distance(from: location.currentLocation))) {
                                    previewTable = table
                                }
                            }
                        }
                    }

                    joinCard
                }
                .padding(AppLayout.screenPadding)
                .frame(maxWidth: 900)
                .frame(maxWidth: .infinity)
            }
        }
        .screenBackground()
        .sheet(item: $previewTable) { table in
            GuestTablePreview(table: table) {
                previewTable = nil
                session.leaveGuestMode()
            }
            .presentationDetents([.medium, .large])
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            AppLogoBadge()
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Text("SocialEats").font(AppFont.headline)
                    Text("GUEST")
                        .font(AppFont.overline)
                        .foregroundStyle(AppColors.amber)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(AppColors.amberSoft))
                }
                Text("Guest Browse Feed")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Button("Sign In") { session.goToSignIn() }
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(Capsule().fill(AppColors.surfaceMuted))
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, 8)
    }

    private var guestBanner: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "eye")
                .foregroundStyle(AppColors.onPrimary)
                .frame(width: 36, height: 36)
                .background(Circle().fill(AppColors.amber))
            VStack(alignment: .leading, spacing: 4) {
                Text("Browsing as Guest • Read-only preview")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                Text("Explore active tables in your neighborhood. Create a free profile anytime to take a seat!")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            Button("Join") { session.leaveGuestMode() }
                .font(AppFont.footnote.weight(.bold))
                .foregroundStyle(AppColors.onPrimary)
                .padding(.horizontal, 14)
                .frame(minHeight: 34)
                .background(Capsule().fill(AppColors.primary))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppColors.amberSoft.opacity(0.7)))
    }

    private var joinCard: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.badge.plus")
                .foregroundStyle(AppColors.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(AppColors.primarySoft))
            Text("Want to grab a seat?")
                .font(AppFont.headline)
            Text("Guests can preview community tables, but seats fill fast! Join free to connect with local foodies.")
                .font(AppFont.footnote)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Create Free Account") { session.leaveGuestMode() }
                .buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(AppColors.surfaceMuted))
    }
}

private struct GuestTablePreview: View {
    let table: CommunityTable
    let onJoin: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    TableThumbnail(category: table.category, size: 64)
                    VStack(alignment: .leading) {
                        Text(table.title).font(AppFont.title)
                        Text("\(table.venueName) • \(table.startTime.friendlyDayTime)")
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Text(table.about)
                    .font(AppFont.body)
                    .foregroundStyle(AppColors.textSecondary)
                BadgeView(text: table.seatSummary, showsDot: true)
                Button("Create a free account to join", action: onJoin)
                    .buttonStyle(PrimaryButtonStyle())
            }
            .padding(20)
        }
        .screenBackground()
    }
}
