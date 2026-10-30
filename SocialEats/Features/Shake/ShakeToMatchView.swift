//  ShakeToMatchView.swift

import SwiftUI

struct ShakeToMatchView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @EnvironmentObject private var tablesStore: TablesStore
    @EnvironmentObject private var location: LocationService
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var passToOpen: String?
    @StateObject private var viewModel: ShakeToMatchViewModel
    @State private var pulse = false

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ShakeToMatchViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                BadgeView(text: "⚡️ LIVE RADAR ACTIVE", showsDot: false)
                Text("Shake to Match")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Finding open social tables within \(viewModel.radiusText) right now.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                radar
                    .frame(height: 300)

                statusPill

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                }

                if let match = viewModel.match {
                    matchCard(match)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if viewModel.noMatchFound {
                    EmptyStateView(systemImage: "magnifyingglass",
                                   title: "No open tables in range",
                                   message: "Try a bigger radius in Settings, or host your own table!",
                                   buttonTitle: "Host a Table") {
                        navigation.open(.createTable, on: navigation.selectedTab)
                    }
                    .cardStyle()
                }

                if !viewModel.isMotionAvailable || viewModel.match == nil {
                    Button {
                        Task { await viewModel.handleShake() }
                    } label: {
                        Label(viewModel.isMotionAvailable ? "Can't shake? Tap to match" : "Simulate Shake",
                              systemImage: "hand.tap")
                    }
                    .buttonStyle(SoftButtonStyle())
                }
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
            .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.8), value: viewModel.match?.id)
        }
        .screenBackground()
        .navigationTitle("Shake to Match")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            viewModel.start()
            if !reduceMotion { pulse = true }
        }
        .onDisappear { viewModel.stop() }
        .onDeviceShake { Task { await viewModel.handleShake() } }
        .sheet(item: $viewModel.confirmedReservation, onDismiss: openWaitingPass) { reservation in
            ReservationConfirmedSheet(reservation: reservation) {
                passToOpen = reservation.tableId
                viewModel.confirmedReservation = nil
            }
        }
    }

    private func openWaitingPass() {
        guard let tableId = passToOpen else { return }
        passToOpen = nil
        navigation.open(.pass(tableId), on: navigation.selectedTab)
    }

    private var radar: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)

            ZStack {
                ForEach(1...3, id: \.self) { ring in
                    Circle()
                        .stroke(AppColors.primary.opacity(0.35), lineWidth: 1)
                        .background(Circle().fill(AppColors.primarySoft.opacity(0.18 * Double(4 - ring))))
                        .frame(width: size * CGFloat(ring) / 3, height: size * CGFloat(ring) / 3)
                }
                Circle()
                    .stroke(AppColors.primary.opacity(pulse ? 0 : 0.5), lineWidth: 2)
                    .frame(width: pulse ? size : size * 0.2, height: pulse ? size : size * 0.2)
                    .animation(reduceMotion ? nil : .easeOut(duration: 2).repeatForever(autoreverses: false), value: pulse)

                Circle()
                    .stroke(AppColors.amber, lineWidth: 3)
                    .frame(width: size * 0.28 * CGFloat(min(max(viewModel.liveForce, 1), 3)),
                           height: size * 0.28 * CGFloat(min(max(viewModel.liveForce, 1), 3)))
                    .opacity(viewModel.liveForce > 1.3 ? 0.8 : 0)
                    .animation(.easeOut(duration: 0.1), value: viewModel.liveForce)

                VStack(spacing: 2) {
                    AvatarView(name: "You", size: 54)
                        .overlay(Circle().stroke(AppColors.surface, lineWidth: 3))
                    Text("You").font(AppFont.caption.weight(.semibold))
                }
                .rotationEffect(.degrees(viewModel.isSearching && !reduceMotion ? 8 : 0))
                .animation(viewModel.isSearching && !reduceMotion
                           ? .easeInOut(duration: 0.08).repeatForever(autoreverses: true) : .default,
                           value: viewModel.isSearching)

                ForEach(viewModel.blips) { blip in
                    let distance = blip.radius * Double(size) / 2
                    HStack(spacing: 6) {
                        Circle().fill(viewModel.match?.id == blip.id ? AppColors.primary : AppColors.amber)
                            .frame(width: 10, height: 10)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(blip.name).font(AppFont.caption.weight(.semibold)).lineLimit(1)
                            Text(blip.detail).font(.system(size: 10, design: .rounded)).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(Capsule().fill(AppColors.surface))
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .position(x: center.x + CGFloat(sin(blip.angle) * distance),
                              y: center.y - CGFloat(cos(blip.angle) * distance))
                    .accessibilityElement(children: .combine)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Radar showing \(viewModel.blips.count) open tables nearby")
    }

    private var statusPill: some View {
        Group {
            if viewModel.isSearching {
                Label("Scanning nearby tables…", systemImage: "dot.radiowaves.left.and.right")
            } else {
                Label("\(viewModel.blips.count) matching tables ready", systemImage: "bolt.fill")
            }
        }
        .font(AppFont.footnote.weight(.semibold))
        .foregroundStyle(AppColors.amber)
        .padding(.horizontal, 14).padding(.vertical, 8)
        .background(Capsule().fill(AppColors.amberSoft))
        .accessibilityAddTraits(.updatesFrequently)
    }

    private func matchCard(_ table: CommunityTable) -> some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                TableThumbnail(category: table.category, size: 64)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(table.venueName).font(AppFont.headline).lineLimit(1)
                        Spacer()
                        Label(String(format: "%.1f", table.hostRating), systemImage: "star.fill")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColors.amber)
                    }
                    Text(table.title).font(AppFont.footnote).foregroundStyle(AppColors.textSecondary).lineLimit(1)
                    HStack {
                        BadgeView(text: "\(table.seatsLeft) seat\(table.seatsLeft == 1 ? "" : "s") remaining")
                        Text("Host: \(table.hostName.split(separator: " ").first.map(String.init) ?? table.hostName)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            .onTapGesture { navigation.open(.table(table.id), on: navigation.selectedTab) }
            .accessibilityElement(children: .combine)
            .accessibilityHint("Opens table details")

            LoadingButton(title: "Reserve Free Hold", systemImage: "arrow.right", isLoading: viewModel.isJoining) {
                Task { await viewModel.reserveMatch() }
            }
            Button {
                Task { await viewModel.handleShake() }
            } label: {
                Label("Shake again to rescan", systemImage: "iphone.radiowaves.left.and.right")
            }
            .buttonStyle(SoftButtonStyle(tint: AppColors.textSecondary))
        }
        .cardStyle()
    }
}
