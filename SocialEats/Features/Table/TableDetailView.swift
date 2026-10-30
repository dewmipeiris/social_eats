//  TableDetailView.swift

import SwiftUI
import UIKit
import MapKit

struct TableDetailView: View {
    @EnvironmentObject private var navigation: NavigationModel
    @Environment(\.dismiss) private var dismiss
    @State private var passToOpen: String?
    @StateObject private var viewModel: TableDetailViewModel
    @State private var showsCancelConfirm = false
    @State private var showsEditTime = false
    @State private var showsCheckIn = false
    @State private var newTime = Date()

    init(tableId: String, container: AppContainer) {
        _viewModel = StateObject(wrappedValue: TableDetailViewModel(tableId: tableId, container: container))
    }

    var body: some View {
        Group {
            if let table = viewModel.table {
                content(table)
            } else if viewModel.isLoading {
                ProgressView("Loading table…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(systemImage: "questionmark.circle",
                               title: "Table not found",
                               message: "This table may have been removed by the host.",
                               buttonTitle: "Go back") { dismiss() }
            }
        }
        .screenBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(item: $viewModel.confirmedReservation, onDismiss: openWaitingPass) { reservation in
            ReservationConfirmedSheet(reservation: reservation) {
                passToOpen = reservation.tableId
                viewModel.confirmedReservation = nil
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .alert("Cancel your seat?", isPresented: $showsCancelConfirm) {
                    Button("Keep Seat", role: .cancel) { }
                    Button("Cancel Seat", role: .destructive) {
                        Task { await viewModel.cancelSeat() }
                    }
                } message: {
                    Text("Your seat will be released for someone else. Face ID or Touch ID is needed to confirm.")
                }

        .sheet(isPresented: $showsEditTime) {
            EditTimeSheet(newTime: $newTime, isSaving: viewModel.isWorking,
                          errorMessage: viewModel.errorMessage) {
                Task {
                    if await viewModel.changeTime(to: newTime) {
                        showsEditTime = false
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showsCheckIn) {
            CheckInScannerSheet()
        }
    }

    private func openWaitingPass() {
        guard let tableId = passToOpen else { return }
        passToOpen = nil
        navigation.open(.pass(tableId), on: navigation.selectedTab)
    }

    private func content(_ table: CommunityTable) -> some View {
        ScrollView {
            VStack(spacing: 0) {
                hero(table)
                VStack(alignment: .leading, spacing: 18) {
                    titleBlock(table)
                    hostCard(table)
                    infoChips(table)
                    aboutBlock(table)
                    confirmedTableCard(table)
                    dietaryBlock(table)
                    locationBlock(table)
                    if viewModel.isAttending { memberActions(table) }
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) { viewModel.errorMessage = nil }
                    }
                }
                .padding(AppLayout.screenPadding)
                .background(
                    UnevenRoundedRectangle(topLeadingRadius: 26, topTrailingRadius: 26)
                        .fill(AppColors.background)
                )
                .offset(y: -24)
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .ignoresSafeArea(edges: .top)
        .safeAreaInset(edge: .bottom) { bottomBar(table) }
    }

    private func hero(_ table: CommunityTable) -> some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if UIImage(named: "table_hero") != nil {
                    Image("table_hero")
                        .resizable()
                        .scaledToFill()
                        .allowsHitTesting(false)   // hidden overflow must not block the buttons
                } else {
                    FoodPhoto(category: table.category, emojiSize: 110)
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .clipped()
            .accessibilityHidden(true)

            if viewModel.isAttending {
                Text("Confirmed Reservation")
                    .font(AppFont.caption)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(.black.opacity(0.4)))
                    .padding(.leading, 16).padding(.bottom, 40)
            }
        }
        .overlay(alignment: .top) {
            HStack {
                heroButton("chevron.left", label: "Back") { dismiss() }
                Spacer()
                ShareLink(item: "Join me at \"\(table.title)\" at \(table.venueName), \(table.startTime.friendlyDayTime) on SocialEats! 🍽️") {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppColors.surface.opacity(0.9)))
                }
                .accessibilityLabel("Share table")
            }
            .padding(.horizontal, 16)
            .padding(.top, 56)
        }
    }

    private func heroButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: 40, height: 40)
                .background(Circle().fill(AppColors.surface.opacity(0.9)))
        }
        .accessibilityLabel(label)
    }

    private func titleBlock(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                OverlineText(text: "Social dining & networking", color: AppColors.primary)
                Spacer()
                Label(table.venueName, systemImage: "fork.knife")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.primary)
                    .lineLimit(1)
            }
            Text(table.title)
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
        }
    }

    private func hostCard(_ table: CommunityTable) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: table.hostName, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(table.hostName)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Community Host • \(table.hostTablesHosted) Tables Hosted")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                VStack(alignment: .leading, spacing: 0) {
                    Text(String(format: "%.1f", table.hostRating)).font(AppFont.subheadline.weight(.bold))
                    if table.hostRating >= 4.8 { Text("SuperHost").font(AppFont.overline) }
                }
            }
            .foregroundStyle(AppColors.amber)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Capsule().fill(AppColors.amberSoft))
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppColors.surfaceMuted))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Hosted by \(table.hostName), rating \(String(format: "%.1f", table.hostRating)), \(table.hostTablesHosted) tables hosted")
    }

    private func infoChips(_ table: CommunityTable) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                BadgeView(text: "➤ \(viewModel.distanceText)", foreground: AppColors.primary, background: AppColors.primarySoft)
                BadgeView(text: "🕖 \(table.startTime.friendlyDayTime)", foreground: AppColors.amber, background: AppColors.amberSoft)
                BadgeView(text: table.isFull ? "Full" : "\(table.seatsLeft) Seat\(table.seatsLeft == 1 ? "" : "s") Left",
                          foreground: AppColors.success, background: AppColors.successSoft)
                if !viewModel.walkingText.isEmpty {
                    BadgeView(text: "🚶 \(viewModel.walkingText)", foreground: AppColors.teal, background: AppColors.tealSoft)
                }
                if table.pricePerPerson > 0 {
                    BadgeView(text: "~LKR \(Int(table.pricePerPerson)) pp", foreground: AppColors.textSecondary,
                              background: AppColors.surfaceMuted)
                }
            }
        }
    }

    private func aboutBlock(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("About the Meetup")
                .font(AppFont.headline)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            Text(table.about)
                .font(AppFont.body)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func confirmedTableCard(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Confirmed Table")
                    .font(AppFont.headline)
                Text("(\(table.seatsFilled) of \(table.capacity) filled)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Text("Table #\(table.tableNumber)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.primary)
            }
            HStack {
                AvatarStack(names: table.attendeeNames, maxVisible: 4, size: 36)
                if !table.isFull && !viewModel.isAttending {
                    Circle()
                        .strokeBorder(AppColors.primary, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                        .frame(width: 36, height: 36)
                        .overlay(Text("YOU").font(.system(size: 9, weight: .bold)).foregroundStyle(AppColors.primary))
                        .accessibilityHidden(true)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(table.attendeeNames.prefix(3).map { $0.split(separator: " ").first.map(String.init) ?? $0 }
                            .joined(separator: ", "))
                        .font(AppFont.subheadline.weight(.semibold))
                        .lineLimit(1)
                    if !table.isFull {
                        Text(viewModel.isAttending ? "\(table.seatsLeft) open chair\(table.seatsLeft == 1 ? "" : "s")"
                                                   : "+1 open chair for you")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            
            HStack(spacing: 4) {
                ForEach(0..<table.capacity, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 3)
                        .fill(index < table.seatsFilled ? AppColors.success : AppColors.border)
                        .frame(height: 8)
                }
            }
            .accessibilityHidden(true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(AppColors.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    private func dietaryBlock(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Dietary & Kitchen Options")
                .font(AppFont.subheadline.weight(.semibold))
                .foregroundStyle(AppColors.textSecondary)
            if table.dietaryTags.isEmpty {
                Text("No special dietary options listed — ask the host in chat.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                ChipGrid {
                    ForEach(table.dietaryTags) { tag in
                        BadgeView(text: "✓ \(tag.title)", foreground: AppColors.success, background: AppColors.successSoft)
                    }
                }
            }
        }
    }

    private func locationBlock(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Location & Parking")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("Open in Maps ›") { viewModel.openWalkingDirections() }
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            ZStack(alignment: .bottom) {
                Map(initialPosition: .region(MKCoordinateRegion(center: table.coordinate,
                                                                latitudinalMeters: 700, longitudinalMeters: 700)),
                    interactionModes: []) {
                    Marker(table.venueName, systemImage: "fork.knife", coordinate: table.coordinate)
                        .tint(AppColors.primary)
                    UserAnnotation()
                }
                .frame(height: 170)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .onTapGesture { viewModel.openWalkingDirections() }
                .accessibilityLabel("Map showing \(table.venueName)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Opens walking directions in Apple Maps")

                Button {
                    viewModel.openWalkingDirections()
                } label: {
                    HStack {
                        Image(systemName: "mappin.circle").foregroundStyle(AppColors.primary)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(table.venueName)
                                .font(AppFont.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.textPrimary)
                            Text(table.venueAddress)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                        BadgeView(text: "Open")
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surface))
                }
                .buttonStyle(.plain)
                .padding(8)
                .accessibilityLabel("\(table.venueName), \(table.venueAddress), open now")
                .accessibilityHint("Opens walking directions in Apple Maps")
            }
        }
    }

    private func memberActions(_ table: CommunityTable) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    navigation.open(.chat(table.id), on: navigation.selectedTab)
                } label: {
                    Label("Group Chat", systemImage: "bubble.left.and.bubble.right")
                }
                .buttonStyle(SoftButtonStyle())

                Button {
                    navigation.open(.scanner, on: navigation.selectedTab)
                } label: {
                    Label("Scan Receipt", systemImage: "doc.text.viewfinder")
                }
                .buttonStyle(SoftButtonStyle())
            }
            if viewModel.isHost {
                Button {
                    newTime = table.startTime
                    showsEditTime = true
                } label: {
                    Label("Edit Meetup Time", systemImage: "clock.arrow.circlepath")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minTapTarget)
                }
                .accessibilityHint("Change when your table meets")

                Button {
                    showsCheckIn = true
                } label: {
                    Label("Check In a Guest", systemImage: "qrcode.viewfinder")
                }
                .buttonStyle(SoftButtonStyle())
            } else {
                Button(role: .destructive) {
                    showsCancelConfirm = true
                } label: {
                    Label("Cancel My Seat", systemImage: "faceid")
                        .font(AppFont.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.danger)
                        .frame(maxWidth: .infinity, minHeight: AppLayout.minTapTarget)
                }
            }
        }
    }

    private func bottomBar(_ table: CommunityTable) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("FREE")
                    .font(AppFont.overline)
                    .foregroundStyle(AppColors.success)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.successSoft))
                Text("Seat hold")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Text("LKR 0.00")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Free seat hold")

            LoadingButton(title: viewModel.joinButtonTitle,
                          systemImage: viewModel.isAttending ? "qrcode" : "arrow.right",
                          isLoading: viewModel.isWorking,
                          isEnabled: viewModel.isAttending || viewModel.canJoin) {
                if viewModel.isAttending {
                    navigation.open(.pass(table.id), on: navigation.selectedTab)
                } else {
                    Task { await viewModel.join() }
                }
            }
            .accessibilityHint(viewModel.isAttending ? "Opens your offline dining pass" : "Confirms your seat with Face ID")
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, 12)
        .background(AppColors.surface.shadow(.drop(color: .black.opacity(0.08), radius: 8, y: -2)))
    }
}

struct ReservationConfirmedSheet: View {
    let reservation: Reservation
    let onDone: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                BadgeView(text: "✓ RSVP Confirmed!", showsDot: false)
                    .font(AppFont.subheadline)
                Text("Seat #\(reservation.seatNumber) Reserved • Table #\(reservation.tableNumber)")
                    .font(AppFont.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.amber)

                QRCodeView(text: reservation.qrToken, size: 180)

                Text("Show this QR code to host \(reservation.hostName) or venue staff upon arrival")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 10) {
                    Image(systemName: "person")
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(AppColors.primarySoft))
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Host: \(reservation.hostName)").font(AppFont.subheadline.weight(.semibold))
                        Text("\(reservation.venueName) • \(reservation.startTime.shortTime)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(AppColors.success)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.amberSoft.opacity(0.6)))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(AppColors.amber.opacity(0.5), lineWidth: 1))

                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(
                        latitude: reservation.latitude, longitude: reservation.longitude)))
                    item.name = reservation.venueName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("Get Walking Directions (Apple Maps)", systemImage: "location.north.line")
                }
                .buttonStyle(SoftButtonStyle())

                Button(action: onDone) {
                    Label("Done • View Offline Pass", systemImage: "wallet.pass")
                }
                .buttonStyle(PrimaryButtonStyle())

                Button("Close Preview") { dismiss() }
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(minHeight: AppLayout.minTapTarget)
            }
            .padding(24)
        }
        .screenBackground()
    }
}

struct QRCodeView: View {
    let text: String
    var size: CGFloat = 180

    var body: some View {
        Group {
            if let image = QRCodeGenerator.image(from: QRToken.checkInLink(for: text)) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "qrcode")
                    .resizable()
                    .scaledToFit()
            }
        }
        .frame(width: size, height: size)
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(AppColors.border, lineWidth: 1))
        .accessibilityLabel("Check-in QR code")
    }
}

struct EditTimeSheet: View {
    @Binding var newTime: Date
    let isSaving: Bool
    var errorMessage: String? = nil
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Everyone at your table will see the new time.")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                DatePicker("Meetup time", selection: $newTime,
                           in: Date()...Date().addingTimeInterval(7 * 24 * 60 * 60))
                    .datePickerStyle(.compact)
                    .font(AppFont.body)

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColors.danger)
                        .multilineTextAlignment(.center)
                }

                LoadingButton(title: "Save New Time", systemImage: "checkmark",
                              isLoading: isSaving, isEnabled: true, action: onSave)
                Spacer()
            }
            .padding(20)
            .navigationTitle("Edit Meetup Time")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .screenBackground()
        }
    }
}
