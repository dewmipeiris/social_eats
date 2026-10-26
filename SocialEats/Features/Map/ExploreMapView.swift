//
//  ExploreMapView.swift
//  SocialEats
//
//  Prototype Figure 17 — Explore Map.
//  iPhone: full-screen map + bottom card.
//  iPad: list of tables on the left, map on the right (LO1 adaptation).
//

import SwiftUI
import MapKit

struct ExploreMapView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @EnvironmentObject private var session: SessionStore
    // Watched so the map redraws when tables, your location or filters change
    @EnvironmentObject private var tablesStore: TablesStore
    @EnvironmentObject private var location: LocationService
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.horizontalSizeClass) private var sizeClass
    @StateObject private var viewModel: ExploreMapViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ExploreMapViewModel(container: container))
    }

    var body: some View {
        Group {
            if sizeClass == .regular {
                HStack(spacing: 0) {
                    sideList
                        .frame(width: 340)
                    Divider()
                    mapLayer
                }
            } else {
                mapLayer
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 8) {
                AppHeader(title: "Explore Map",
                          onSearch: { navigation.open(.search, on: navigation.selectedTab) },
                          onBell: { navigation.open(.notifications, on: navigation.selectedTab) },
                          hasUnread: session.unreadCount > 0)
                filterBar
            }
            .padding(.bottom, 8)
            .background(AppColors.background.opacity(0.95))
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    // MARK: - Map

    private var mapLayer: some View {
        Map(position: $viewModel.position, selection: $viewModel.selectedTableId) {
            UserAnnotation()

            // Your alert / geofence radius
            if let user = viewModel.userCoordinate {
                MapCircle(center: user, radius: viewModel.radiusMetres)
                    .foregroundStyle(AppColors.primary.opacity(0.08))
                    .stroke(AppColors.primary.opacity(0.4), lineWidth: 1)
            }

            ForEach(viewModel.tables) { table in
                Annotation(table.venueName, coordinate: table.coordinate, anchor: .bottom) {
                    TableMapPin(table: table, isSelected: viewModel.selectedTableId == table.id)
                }
                .tag(table.id)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottom) {
            if let table = viewModel.selectedTable {
                selectedCard(table)
                    .padding(AppLayout.screenPadding)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if viewModel.tables.isEmpty {
                Text("No tables match these filters")
                    .font(AppFont.footnote.weight(.semibold))
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Capsule().fill(AppColors.surface))
                    .padding(.bottom, 24)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.selectedTableId)
    }

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(AppColors.primary)
                    TextField("Search area or cuisine...", text: $viewModel.searchText)
                }
                .inputFieldStyle()
                Button { viewModel.showAllTables() } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 48, height: 48)
                        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))
                }
                .accessibilityLabel("Show all tables")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.chips) { chip in
                        ChipView(title: "\(chip.title) tables", icon: chip.emoji,
                                 isSelected: viewModel.category == chip) {
                            viewModel.toggle(chip)
                        }
                    }
                }
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
    }

    // MARK: - Bottom card

    private func selectedCard(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Capsule().fill(AppColors.border).frame(width: 36, height: 4).frame(maxWidth: .infinity)
            HStack {
                Label("Hosted by \(table.hostName.split(separator: " ").first.map(String.init) ?? "")", systemImage: "person")
                    .font(AppFont.footnote)
                Text("★ \(String(format: "%.1f", table.hostRating))")
                    .font(AppFont.caption.weight(.bold))
                    .foregroundStyle(AppColors.amber)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.amberSoft))
                Spacer()
                Label(viewModel.distanceText(for: table), systemImage: "location.north")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.title).font(AppFont.title).lineLimit(2)
                    Text(table.about).font(AppFont.footnote).foregroundStyle(AppColors.textSecondary).lineLimit(1)
                }
                Spacer()
                TableThumbnail(category: table.category, size: 56)
            }
            HStack {
                AvatarStack(names: table.attendeeNames, maxVisible: 3, size: 26)
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(table.seatsFilled)/\(table.capacity) Seats Taken").font(AppFont.subheadline.weight(.bold))
                    Text(table.isFull ? "Table is full" : "\(table.seatsLeft) spot\(table.seatsLeft == 1 ? "" : "s") left")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.success)
                }
                Spacer()
                HStack(spacing: 3) {
                    ForEach(0..<table.capacity, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(index < table.seatsFilled ? AppColors.success : AppColors.border)
                            .frame(width: 10, height: 22)
                    }
                }
                .accessibilityHidden(true)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))

            Text("🕐 \(table.startTime.friendlyDayTime) • ~LKR \(Int(table.pricePerPerson)) per person")
                .font(AppFont.caption)
                .foregroundStyle(AppColors.textSecondary)

            Button {
                navigation.open(.table(table.id), on: navigation.selectedTab)
            } label: {
                Label(table.isAttending(session.userId) ? "View My Table" : "Join Table & Reserve", systemImage: "fork.knife")
            }
            .buttonStyle(PrimaryButtonStyle())
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 22).fill(AppColors.surface))
        .shadow(color: .black.opacity(0.12), radius: 14, y: 4)
        .frame(maxWidth: 520)
    }

    // MARK: - iPad side list

    private var sideList: some View {
        List(viewModel.tables) { table in
            Button {
                viewModel.select(table)
            } label: {
                HStack(spacing: 10) {
                    TableThumbnail(category: table.category, size: 44, cornerRadius: 10)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(table.title).font(AppFont.subheadline.weight(.semibold)).lineLimit(1)
                            .foregroundStyle(AppColors.textPrimary)
                        Text("\(table.venueName) • \(table.seatSummary)").font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .listRowBackground(viewModel.selectedTableId == table.id ? AppColors.primarySoft : Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
    }
}

/// Custom map pin: "● 1 Open" bubble above a round category icon.
struct TableMapPin: View {
    let table: CommunityTable
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(table.isFull ? "Full" : "● \(table.seatsLeft) Open")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(Capsule().fill(table.isFull ? AppColors.textTertiary : AppColors.success))
            Text(table.category.emoji)
                .font(.system(size: isSelected ? 24 : 18))
                .frame(width: isSelected ? 48 : 38, height: isSelected ? 48 : 38)
                .background(Circle().fill(isSelected ? AppColors.primary : AppColors.surface))
                .overlay(Circle().stroke(AppColors.primary, lineWidth: 2))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .animation(.spring(response: 0.3), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(table.title) at \(table.venueName), \(table.seatsLeft) seats open")
        .accessibilityAddTraits(.isButton)
    }
}
