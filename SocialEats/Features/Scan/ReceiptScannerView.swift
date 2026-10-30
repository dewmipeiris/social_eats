//  ReceiptScannerView.swift

import SwiftUI
import UIKit
import PhotosUI
import AVFoundation

struct ReceiptScannerView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: NavigationModel
    @EnvironmentObject private var tablesStore: TablesStore
    @StateObject private var viewModel: ReceiptScannerViewModel
    @State private var photoItem: PhotosPickerItem?
    @State private var showsTimeEditor = false
    @State private var editedTime = Date()

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ReceiptScannerViewModel(container: container))
    }

    var body: some View {
        Group {
            if case .success(let points) = viewModel.phase {
                ReceiptSuccessView(points: points, viewModel: viewModel) {
                    viewModel.reset()
                    navigation.popToRoot(navigation.selectedTab)
                    navigation.selectedTab = .home
                }
            } else if viewModel.eligibleTables.isEmpty {
                noTableState
            } else {
                scannerContent
            }
        }
        .screenBackground()
        .navigationTitle("Vision Scanner")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                CircleIconButton(systemImage: "bell",
                                 accessibilityText: "Notifications",
                                 showsBadge: session.unreadCount > 0) {
                    navigation.open(.notifications, on: navigation.selectedTab)
                }
            }
        }
        .onAppear { if viewModel.phase == .scanning { viewModel.startCamera() } }
        .onDisappear { viewModel.stopCamera() }
        .sheet(isPresented: $showsTimeEditor) {
            NavigationStack {
                Form {
                    DatePicker("Receipt time", selection: $editedTime,
                               displayedComponents: [.date, .hourAndMinute])
                    Text("Only the time can be corrected. The restaurant name and total always come from the scan.")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                }
                .navigationTitle("Edit Timestamp")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsTimeEditor = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            viewModel.updateTimestamp(editedTime)
                            showsTimeEditor = false
                        }
                    }
                }
            }
            .presentationDetents([.medium])
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await viewModel.analyse(image)
                }
                photoItem = nil
            }
        }
    }

    private var noTableState: some View {
        VStack {
            Spacer()
            EmptyStateView(systemImage: "doc.text.viewfinder",
                           title: "No meal to verify yet",
                           message: noTableMessage,
                           buttonTitle: "Find a Table") {
                navigation.selectedTab = .home
            }
            .cardStyle()
            .padding(AppLayout.screenPadding)
            Spacer()
        }
    }

    private var noTableMessage: String {
        if let next = viewModel.nextUpcomingTable {
            return "Your next meal, \(next.title) at \(next.venueName), is on \(next.startTime.friendlyDayTime). Receipt scanning opens 3 hours before it starts."
        }
        return "Join a table, enjoy your meal, then scan the paper receipt here to earn Foodie Karma."
    }

    private var scannerContent: some View {
        ScrollView {
            VStack(spacing: 16) {
                cameraCard
                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                }
                detailsCard
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 620)
            .frame(maxWidth: .infinity)
        }
    }

    private var cameraCard: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch viewModel.camera.state {
                case .running:
                    CameraPreview(session: viewModel.camera.session)
                case .denied:
                    cameraMessage("Camera access is off. Enable it in Settings, or pick a photo below.")
                case .unavailable:
                    cameraMessage("No camera on the Simulator. Tap \"Test Receipt\" or \"Choose Photo\" below — the same Vision scanner reads it.")
                case .idle:
                    Color.black.overlay(ProgressView().tint(.white))
                }
            }
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: AppLayout.cardRadius))

            if viewModel.camera.state == .running {
                ScanLineOverlay()
                    .frame(height: 300)
                    .allowsHitTesting(false)
            }

            VStack {
                HStack {
                    BadgeView(text: "AUTO-DETECT", foreground: .white, background: .black.opacity(0.55), showsDot: true)
                    Spacer()
                }
                Spacer()
                if let chip = viewModel.liveChipText {
                    Label(chip, systemImage: "sparkles")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(Capsule().fill(AppColors.surface.opacity(0.95)))
                        .transition(.scale.combined(with: .opacity))
                        .accessibilityLabel("Detected: \(chip)")
                }
            }
            .padding(12)
            .frame(height: 300)
            .animation(.spring(), value: viewModel.liveChipText)

            if viewModel.phase == .processing {
                RoundedRectangle(cornerRadius: AppLayout.cardRadius)
                    .fill(.black.opacity(0.5))
                    .frame(height: 300)
                    .overlay(ProgressView("Reading receipt on-device…").tint(.white).foregroundStyle(.white))
            }
        }
        .overlay(alignment: .bottom) {
            HStack(spacing: 14) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Choose Photo", systemImage: "photo")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(.black.opacity(0.55)))
                }
 
                #if targetEnvironment(simulator)
                Button {
                    Task { await viewModel.scanTestReceipt() }
                } label: {
                    Label("Test Receipt", systemImage: "doc.text")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.onPrimary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 40)
                        .background(Capsule().fill(AppColors.primary))
                }
                .accessibilityHint("Creates a sample receipt for your table and scans it")
                #endif

                if viewModel.camera.state == .running {
                    Button {
                        Task { await viewModel.captureFromCamera() }
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 58, height: 58)
                            .overlay(Circle().stroke(AppColors.primary, lineWidth: 4).padding(3))
                    }
                    .accessibilityLabel("Capture receipt")
                }
            }
            .padding(.bottom, -28)
        }
        .padding(.bottom, 28)
    }

    private func cameraMessage(_ text: String) -> some View {
        ZStack {
            if UIImage(named: "scanner_preview") != nil {
                Image("scanner_preview")
                    .resizable()
                    .scaledToFill()
                    .accessibilityHidden(true)
            }
            Color.black.opacity(0.55)
            Text(text)
                .font(AppFont.footnote)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(24)
        }
    }

    private var detailsCard: some View {
        let result = viewModel.scanResult ?? viewModel.liveResult
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Receipt Details", systemImage: "doc.text")
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.textPrimary)
                Spacer()
                if let match = viewModel.matchPercent {
                    BadgeView(text: "\(match)% Match", showsDot: true)
                }
            }

            if viewModel.eligibleTables.count > 1 {
                Picker("Meal", selection: $viewModel.selectedTableId) {
                    ForEach(viewModel.eligibleTables) { table in
                        Text("\(table.venueName) • \(table.startTime.shortTime)").tag(Optional(table.id))
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: viewModel.selectedTableId) { _, _ in viewModel.revalidate() }
            } else if let table = viewModel.selectedTable {
                Text("For: \(table.title) at \(table.venueName)")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }

            VStack(spacing: 0) {
                detailRow(icon: "storefront", title: "RESTAURANT",
                          value: result?.restaurantName ?? "Point camera at the receipt…",
                          trailing: viewModel.validation?.isVerified == true ? AnyView(Image(systemName: "checkmark.circle.fill").foregroundStyle(AppColors.success)) : nil)
                Divider().padding(.leading, 44)
                detailRow(icon: "banknote", title: "TOTAL AMOUNT",
                          value: result?.total.map { String(format: "%.2f", $0) } ?? "—",
                          trailing: AnyView(Text(result?.currencyCode ?? "LKR").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)))
                Divider().padding(.leading, 44)
                detailRow(icon: "clock", title: "TIMESTAMP",
                          value: result?.timestamp?.friendlyDayTime ?? "—",
                          trailing: viewModel.scanResult == nil ? nil : AnyView(
                            Button("Edit") {
                                editedTime = viewModel.scanResult?.timestamp ?? Date()
                                showsTimeEditor = true
                            }
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .accessibilityLabel("Edit receipt time")
                          ))
            }
            .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surfaceMuted))

            if let validation = viewModel.validation, !validation.isVerified {
                ErrorBanner(message: validation.message)
            }

            HStack(spacing: 10) {
                Image(systemName: "star.circle.fill").foregroundStyle(AppColors.amber).font(.title2)
                VStack(alignment: .leading, spacing: 0) {
                    Text("Foodie Karma Reward").font(AppFont.subheadline.weight(.semibold))
                    Text("Verified meals build your community reputation").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                Text("+\(viewModel.pointsPreview)").font(AppFont.headline).foregroundStyle(AppColors.amber)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.amberSoft.opacity(0.7)))
            .accessibilityElement(children: .combine)

            if viewModel.phase == .reviewed || viewModel.phase == .claiming {
                LoadingButton(title: "Verify & Claim Foodie Points", systemImage: "checkmark.seal",
                              isLoading: viewModel.phase == .claiming,
                              isEnabled: viewModel.validation?.isVerified == true) {
                    Task { await viewModel.verifyAndClaim() }
                }
                Button("Retake") {
                    viewModel.retake()
                    viewModel.startCamera()
                }
                .font(AppFont.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, minHeight: AppLayout.minTapTarget)
            } else {
                Text("Tip: lay the receipt flat in good light. Everything is read on your iPhone — nothing is uploaded to an AI service.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .cardStyle()
    }

    private func detailRow(icon: String, title: String, value: String, trailing: AnyView?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(AppColors.surface))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.overline).foregroundStyle(AppColors.textSecondary)
                Text(value).font(AppFont.headline).foregroundStyle(AppColors.textPrimary).lineLimit(1)
            }
            Spacer()
            trailing
        }
        .padding(12)
        .accessibilityElement(children: .combine)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}
}

struct ScanLineOverlay: View {
    @State private var moveDown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(AppColors.success.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [18, 10]))
                    .padding(28)
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, AppColors.success, .clear], startPoint: .leading, endPoint: .trailing))
                    .frame(height: 3)
                    .shadow(color: AppColors.success, radius: 6)
                    .offset(y: moveDown ? geo.size.height * 0.35 : -geo.size.height * 0.35)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) { moveDown = true }
        }
        .accessibilityHidden(true)
    }
}

struct ReceiptSuccessView: View {
    let points: Int
    @ObservedObject var viewModel: ReceiptScannerViewModel
    let onDone: () -> Void
    @EnvironmentObject private var session: SessionStore
    @State private var showConfetti = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ZStack {
                    if showConfetti { ConfettiView() }
                    Image(systemName: "star.fill")
                        .font(.system(size: 34))
                        .foregroundStyle(AppColors.onPrimary)
                        .frame(width: 84, height: 84)
                        .background(Circle().fill(AppColors.amber))
                        .overlay(Circle().stroke(.white, lineWidth: 5))
                        .shadow(color: AppColors.amber.opacity(0.4), radius: 12)
                }
                .frame(height: 120)

                BadgeView(text: "✓ BILL SETTLED & VERIFIED", foreground: .white, background: AppColors.success)
                Text("+\(points) Foodie Karma!")
                    .font(AppFont.largeTitle)
                    .foregroundStyle(AppColors.textPrimary)
                Text("Receipt verified at \(viewModel.selectedTable?.venueName ?? "your venue"). Your community reputation just leveled up!")
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)

                if let user = session.currentUser {
                    levelCard(user)
                }

                if let total = viewModel.scanResult?.total {
                    HStack {
                        Image(systemName: "doc.text").foregroundStyle(AppColors.textSecondary)
                        VStack(alignment: .leading) {
                            Text("Bill: \(viewModel.scanResult?.currencyCode ?? "LKR") \(String(format: "%.2f", total))")
                                .font(AppFont.subheadline.weight(.semibold))
                            Text("Receipt archived to shared dining history")
                                .font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surfaceMuted))
                }

                if !viewModel.tablemates.isEmpty {
                    rateCard
                }

                Button(action: onDone) {
                    Label("Done • Back to Dashboard", systemImage: "arrow.right")
                        .labelStyle(TrailingIconLabelStyle())
                }
                .buttonStyle(PrimaryButtonStyle())
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .onAppear { showConfetti = true }
    }

    private func levelCard(_ user: AppUser) -> some View {
        let level = KarmaCalculator.level(for: user.karma)
        let target = KarmaCalculator.nextLevelTarget(for: user.karma)
        return VStack(spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(name: user.displayName, size: 48, showsOnlineDot: true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(user.displayName).font(AppFont.headline)
                    Text("Karma Champion • \(user.mealsShared) meals shared")
                        .font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text("LEVEL \(level)").font(AppFont.overline).foregroundStyle(AppColors.amber)
                    Text("\(user.karma.formatted())").font(AppFont.title).foregroundStyle(AppColors.amber)
                    Text("/\(target.formatted()) pts").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
            ProgressView(value: KarmaCalculator.levelProgress(for: user.karma))
                .tint(AppColors.primary)
            HStack {
                Label("Level \(level) unlocked", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(AppColors.success)
                Spacer()
                Text("\(target - user.karma) pts to Level \(level + 1)")
                    .foregroundStyle(AppColors.amber)
            }
            .font(AppFont.caption)
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private var rateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Rate Your Tablemates", systemImage: "person.2.fill")
                    .font(AppFont.headline)
                Spacer()
                BadgeView(text: "+\(KarmaCalculator.ratingTablematePoints) karma each")
            }
            ForEach(viewModel.tablemates, id: \.id) { mate in
                HStack {
                    AvatarView(name: mate.name, size: 36)
                    Text(mate.name).font(AppFont.subheadline.weight(.semibold))
                    Spacer()
                    StarRatingView(rating: viewModel.ratedTablemates[mate.id] ?? 0,
                                   isLocked: viewModel.ratedTablemates[mate.id] != nil) { stars in
                        Task { await viewModel.rate(tablemateId: mate.id, stars: stars) }
                    }
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.surfaceMuted))
            }
        }
        .cardStyle()
    }
}

struct StarRatingView: View {
    let rating: Int
    var isLocked: Bool = false
    let onRate: (Int) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { star in
                Button {
                    Haptics.selection()
                    onRate(star)
                } label: {
                    Image(systemName: star <= rating ? "star.fill" : "star")
                        .foregroundStyle(star <= rating ? AppColors.amber : AppColors.textTertiary)
                        .frame(width: 28, height: 36)
                }
                .disabled(isLocked)
                .buttonStyle(.plain)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rating")
        .accessibilityValue(rating == 0 ? "Not rated" : "\(rating) of 5 stars")
        .accessibilityAdjustableAction { direction in
            guard !isLocked else { return }
            switch direction {
            case .increment: onRate(min(rating + 1, 5))
            case .decrement: onRate(max(rating - 1, 1))
            @unknown default: break
            }
        }
    }
}

struct ConfettiView: View {
    @State private var fall = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let colors: [Color] = [AppColors.primary, AppColors.amber, AppColors.success, AppColors.teal]

    var body: some View {
        GeometryReader { geo in
            ForEach(0..<24, id: \.self) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(colors[index % colors.count])
                    .frame(width: 6, height: 10)
                    .rotationEffect(.degrees(Double(index) * 37))
                    .position(x: CGFloat((index * 53) % Int(max(geo.size.width, 1))),
                              y: fall ? geo.size.height + 20 : -10)
                    .opacity(fall ? 0 : 1)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeIn(duration: 1.8)) { fall = true }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
