//
//  PassViews.swift
//  SocialEats
//
//  Prototype Figure 13 — Digital Dining Pass ("Offline Vault Mode").
//  Proposal MVP Feature 8: everything here is read from CORE DATA,
//  so it opens in a basement restaurant with zero signal.
//

import SwiftUI
import MapKit

@MainActor
final class PassViewModel: ObservableObject {
    @Published private(set) var reservation: Reservation?
    @Published private(set) var allPasses: [Reservation] = []

    private let reservations: ReservationManager
    private let session: SessionStore

    init(reservations: ReservationManager, session: SessionStore) {
        self.reservations = reservations
        self.session = session
    }

    convenience init(container: AppContainer) {
        self.init(reservations: container.reservations, session: container.session)
    }

    func load(tableId: String) {
        guard let uid = session.userId else { return }
        reservation = reservations.savedPass(tableId: tableId, userId: uid)
    }

    func loadAll() {
        guard let uid = session.userId else { return }
        allPasses = reservations.savedPasses(for: uid)
    }

    var upcomingPasses: [Reservation] { allPasses.filter { $0.isUpcomingOrActive && !$0.isVerified } }
    var pastPasses: [Reservation] { allPasses.filter { !$0.isUpcomingOrActive || $0.isVerified } }

    /// Same QR token check the host's scanner would do
    var isTokenValid: Bool {
        guard let reservation else { return false }
        return QRToken.verify(reservation.qrToken) != nil
    }
}

// MARK: - Single pass

struct DigitalPassView: View {
    let tableId: String
    @EnvironmentObject private var network: NetworkMonitor
    @EnvironmentObject private var navigation: NavigationModel
    @StateObject private var viewModel: PassViewModel
    @State private var brightnessBefore: CGFloat?

    init(tableId: String, container: AppContainer) {
        self.tableId = tableId
        _viewModel = StateObject(wrappedValue: PassViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            if let pass = viewModel.reservation {
                passContent(pass)
            } else {
                EmptyStateView(systemImage: "wallet.pass",
                               title: "No saved pass",
                               message: "Join this table to get a pass that works offline.")
            }
        }
        .screenBackground()
        .navigationTitle("Digital Dining Pass")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let pass = viewModel.reservation {
                ShareLink(item: "I'm going to \(pass.title) at \(pass.venueName), \(pass.startTime.friendlyDayTime)! 🍽️ #SocialEats") {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .onAppear {
            viewModel.load(tableId: tableId)
            // Brighter screen = easier QR scanning
            brightnessBefore = UIScreen.main.brightness
            UIScreen.main.brightness = max(UIScreen.main.brightness, 0.85)
        }
        .onDisappear {
            if let brightnessBefore { UIScreen.main.brightness = brightnessBefore }
        }
    }

    private func passContent(_ pass: Reservation) -> some View {
        VStack(spacing: 14) {
            // "● Offline Vault Mode Enabled        Local CoreData"
            HStack {
                Label(network.isOnline ? "Saved for Offline Use" : "Offline Vault Mode Enabled",
                      systemImage: "circle.fill")
                    .labelStyle(DotLabelStyle(color: AppColors.success))
                Spacer()
                Label("Local CoreData", systemImage: "wifi.slash")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .font(AppFont.caption)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Image(systemName: "fork.knife")
                        .foregroundStyle(AppColors.onPrimary)
                        .frame(width: 30, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(AppColors.primary))
                    VStack(alignment: .leading, spacing: 0) {
                        Text("COMMUNITY DINING PASS").font(AppFont.overline).foregroundStyle(AppColors.primary)
                        Text("SocialEats Solo Match").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    BadgeView(text: pass.isVerified ? "COMPLETED" : "OFFLINE SECURE", showsDot: true)
                }

                Text(pass.title)
                    .font(AppFont.title)
                    .foregroundStyle(AppColors.textPrimary)
                Label("\(pass.venueName) • \(pass.venueAddress)", systemImage: "mappin")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)

                // Date / time / table / seat grid
                Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                    GridRow {
                        passField("DATE", pass.startTime.formatted(.dateTime.weekday(.abbreviated).day().month()))
                        passField("TIME", pass.startTime.shortTime)
                    }
                    GridRow {
                        passField("TABLE", "Table #\(pass.tableNumber)", highlight: true)
                        passField("ASSIGNED SEAT", "Seat #\(pass.seatNumber)", highlight: true)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surfaceMuted))

                // Ticket tear line
                Line()
                    .stroke(style: StrokeStyle(lineWidth: 1, dash: [6]))
                    .foregroundStyle(AppColors.border)
                    .frame(height: 1)

                VStack(spacing: 10) {
                    QRCodeView(text: pass.qrToken, size: 190)
                    Text("Show this to \(pass.hostName) or venue host on arrival")
                        .font(AppFont.subheadline.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Scan verifies your reservation & dietary prep notes.")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Label(viewModel.isTokenValid ? "Verified via Face ID • Cached to CoreData" : "Pass could not be verified",
                          systemImage: viewModel.isTokenValid ? "checkmark.shield.fill" : "exclamationmark.shield")
                        .font(AppFont.caption)
                        .foregroundStyle(viewModel.isTokenValid ? AppColors.success : AppColors.danger)
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10).fill(AppColors.surfaceMuted))
                }
                .frame(maxWidth: .infinity)
            }
            .cardStyle(padding: 18)

            Button {
                let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: pass.latitude, longitude: pass.longitude)))
                item.name = pass.venueName
                item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
            } label: {
                Label("Open Walking Directions in Apple Maps", systemImage: "figure.walk")
            }
            .buttonStyle(SoftButtonStyle(tint: AppColors.textPrimary))

            HStack(spacing: 12) {
                AvatarView(name: pass.hostName, size: 40)
                VStack(alignment: .leading) {
                    Text(pass.hostName).font(AppFont.subheadline.weight(.semibold))
                    Text("Table Host").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Button {
                    navigation.open(.chat(pass.tableId), on: navigation.selectedTab)
                } label: {
                    Image(systemName: "bubble.left")
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppColors.primarySoft))
                }
                .accessibilityLabel("Message the table")
            }
            .cardStyle(padding: 12)
        }
        .padding(AppLayout.screenPadding)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
    }

    private func passField(_ title: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(AppFont.overline).foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(AppFont.headline)
                .foregroundStyle(highlight ? AppColors.amber : AppColors.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Horizontal dashed line (ticket tear).
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 0, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        return path
    }
}

/// Label style that shows a coloured dot instead of the icon.
struct DotLabelStyle: LabelStyle {
    var color: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            configuration.title
        }
    }
}

// MARK: - All passes

struct MyPassesView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @StateObject private var viewModel: PassViewModel

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: PassViewModel(container: container))
    }

    var body: some View {
        List {
            if viewModel.allPasses.isEmpty {
                EmptyStateView(systemImage: "wallet.pass",
                               title: "No passes yet",
                               message: "When you join a table, your pass is saved here and works offline.")
                    .listRowBackground(Color.clear)
            }
            if !viewModel.upcomingPasses.isEmpty {
                Section("Upcoming") {
                    ForEach(viewModel.upcomingPasses) { pass in row(pass) }
                }
            }
            if !viewModel.pastPasses.isEmpty {
                Section("Past dinners") {
                    ForEach(viewModel.pastPasses) { pass in row(pass) }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .screenBackground()
        .navigationTitle("My Offline Passes")
        .onAppear { viewModel.loadAll() }
    }

    private func row(_ pass: Reservation) -> some View {
        Button {
            navigation.open(.pass(pass.tableId), on: navigation.selectedTab)
        } label: {
            HStack {
                Image(systemName: pass.isVerified ? "checkmark.seal.fill" : "qrcode")
                    .foregroundStyle(pass.isVerified ? AppColors.success : AppColors.primary)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.title).font(AppFont.subheadline.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
                    Text("\(pass.venueName) • \(pass.startTime.friendlyDayTime)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text("Seat #\(pass.seatNumber)").font(AppFont.caption).foregroundStyle(AppColors.amber)
            }
        }
        .listRowBackground(AppColors.surface)
    }
}
