//
//  ProfileView.swift
//  SocialEats
//
//  Prototype Figure 18 — User Profile:
//  karma balance + tier progress, stats, taste & dietary profile.
//

import SwiftUI

@MainActor
final class ProfileViewModel: ObservableObject {
    @Published var editedName = ""
    @Published var errorMessage: String?
    @Published private(set) var isSaving = false

    private let session: SessionStore

    init(session: SessionStore) {
        self.session = session
    }

    convenience init(container: AppContainer) {
        self.init(session: container.session)
    }

    var user: AppUser? { session.currentUser }

    var tier: KarmaCalculator.Tier { KarmaCalculator.tier(for: user?.karma ?? 0) }
    var nextTier: KarmaCalculator.Tier? { KarmaCalculator.nextTier(after: user?.karma ?? 0) }
    var tierProgress: Double { KarmaCalculator.tierProgress(for: user?.karma ?? 0) }
    var level: Int { KarmaCalculator.level(for: user?.karma ?? 0) }

    /// "50 pts needed to unlock Gold Epicurean"
    var pointsToNextTier: String {
        guard let user, let next = nextTier else { return "Top tier reached 👑" }
        return "\(next.minimumKarma - user.karma) pts needed to unlock \(next.rawValue)"
    }

    var memberSince: String {
        guard let user else { return "" }
        return "Member since " + user.joinedAt.formatted(.dateTime.month(.wide).year())
    }

    func beginEditing() {
        editedName = user?.displayName ?? ""
    }

    var isNameValid: Bool { NameValidator.isValid(editedName) }

    func saveName() async -> Bool {
        guard var user, isNameValid else {
            errorMessage = "Use 2–40 letters for your name."
            return false
        }
        isSaving = true
        defer { isSaving = false }
        user.displayName = editedName.trimmingCharacters(in: .whitespaces)
        do {
            try await session.updateProfile(user)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct ProfileView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var navigation: NavigationModel
    @StateObject private var viewModel: ProfileViewModel
    @State private var showsEditName = false
    @State private var showsLogoutConfirm = false

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ProfileViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            if let user = session.currentUser {
                VStack(spacing: 16) {
                    headerCard(user)
                    karmaCard(user)
                    statsCard(user)
                    tasteCard(user)
                    settingsCard
                    Text("SocialEats • \(viewModel.memberSince)")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.textTertiary)
                }
                .padding(AppLayout.screenPadding)
                .frame(maxWidth: 680)
                .frame(maxWidth: .infinity)
            } else {
                ProgressView().padding(40)
            }
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(title: "Profile",
                      onSearch: { navigation.open(.search, on: navigation.selectedTab) },
                      onBell: { navigation.open(.notifications, on: navigation.selectedTab) },
                      hasUnread: session.unreadCount > 0)
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showsEditName) { editNameSheet }
        .confirmationDialog("Log out?", isPresented: $showsLogoutConfirm) {
            Button("Log Out", role: .destructive) { session.signOut() }
        }
    }

    // MARK: - Cards

    private func headerCard(_ user: AppUser) -> some View {
        VStack(spacing: 10) {
            AvatarView(name: user.displayName, size: 88, showsOnlineDot: true)
            Text(user.displayName).font(AppFont.title).foregroundStyle(AppColors.textPrimary)
            Text(user.username).font(AppFont.subheadline).foregroundStyle(AppColors.textSecondary)
            BadgeView(text: "🍴 Verified Foodie • Level \(viewModel.level)",
                      foreground: AppColors.amber, background: AppColors.amberSoft)
            HStack(spacing: 10) {
                Button {
                    viewModel.beginEditing()
                    showsEditName = true
                } label: {
                    Label("Edit Profile", systemImage: "pencil")
                }
                .buttonStyle(PrimaryButtonStyle())

                ShareLink(item: "I'm \(user.displayName) on SocialEats — \(user.mealsShared) shared meals and \(user.karma) foodie karma! Join me at a community table 🍽️") {
                    Image(systemName: "square.and.arrow.up")
                        .foregroundStyle(AppColors.primary)
                        .frame(width: AppLayout.buttonHeight, height: AppLayout.buttonHeight)
                        .background(RoundedRectangle(cornerRadius: AppLayout.buttonRadius).fill(AppColors.primarySoft))
                }
                .accessibilityLabel("Share profile")
            }
        }
        .frame(maxWidth: .infinity)
        .cardStyle(padding: 18)
    }

    private func karmaCard(_ user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(Int(viewModel.tierProgress * 100))% Complete")
                    .font(AppFont.caption.weight(.semibold))
                    .foregroundStyle(AppColors.amber)
                Text("Dining Karma Balance").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                Spacer()
                BadgeView(text: "🏅 \(viewModel.tier.rawValue)", foreground: AppColors.amber, background: AppColors.amberSoft)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(user.karma.formatted())
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy))
                    .foregroundStyle(AppColors.textPrimary)
                    .contentTransition(.numericText())
                Text("pts").font(AppFont.subheadline).foregroundStyle(AppColors.textSecondary)
            }
            if let next = viewModel.nextTier {
                HStack {
                    Text("Next tier: \(next.rawValue)").font(AppFont.caption)
                    Spacer()
                }
            }
            ProgressView(value: viewModel.tierProgress).tint(AppColors.primary)
            Text(viewModel.pointsToNextTier)
                .font(AppFont.caption)
                .foregroundStyle(AppColors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Label("Priority Table Hold active on your next booking", systemImage: "sparkles")
                .font(AppFont.footnote.weight(.semibold))
                .foregroundStyle(AppColors.success)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.successSoft))
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }

    private func statsCard(_ user: AppUser) -> some View {
        HStack {
            stat(icon: "fork.knife", value: "\(user.mealsShared)", label: "Social Dinners", color: AppColors.primary)
            stat(icon: "person.2", value: "\(user.newFriends)", label: "New Friends", color: AppColors.amber)
            stat(icon: "hand.thumbsup", value: "\(user.hostRatingPercent)%", label: "Host Rating", color: AppColors.success)
        }
        .cardStyle()
    }

    private func stat(icon: String, value: String, label: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundStyle(color)
            Text(value).font(AppFont.title).foregroundStyle(AppColors.textPrimary)
            Text(label).font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func tasteCard(_ user: AppUser) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Taste & Dietary Profile").font(AppFont.headline)
                Spacer()
                Button("Manage") { navigation.open(.editTasteProfile, on: navigation.selectedTab) }
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
            ChipGrid {
                ForEach(user.ambiences) { item in ChipView(title: item.title, icon: item.emoji) }
                ForEach(user.cuisines) { item in ChipView(title: item.title) }
                ForEach(settings.dietaryTags) { tag in
                    BadgeView(text: "\(tag.isAllergy ? "⊘" : "✓") \(tag.title)",
                              foreground: tag.isAllergy ? AppColors.danger : AppColors.teal,
                              background: tag.isAllergy ? AppColors.dangerSoft : AppColors.tealSoft)
                }
            }
            if user.ambiences.isEmpty && user.cuisines.isEmpty && settings.dietaryTags.isEmpty {
                Text("Tell us what you love to eat so we can match you better.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .cardStyle()
    }

    private var settingsCard: some View {
        VStack(spacing: 0) {
            OverlineText(text: "Account settings").frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
            menuRow(icon: "fork.knife", title: "Dietary & Allergen Preferences") { navigation.selectedTab = .settings }
            Divider()
            menuRow(icon: "wallet.pass", title: "My Offline Passes") { navigation.open(.myPasses, on: navigation.selectedTab) }
            Divider()
            Toggle(isOn: $settings.nearbyAlertsEnabled) {
                Label("Push & Table Alerts", systemImage: "bell.badge")
                    .foregroundStyle(AppColors.textPrimary)
            }
            .tint(AppColors.success)
            .frame(minHeight: 48)
            Divider()
            Button { showsLogoutConfirm = true } label: {
                Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    .foregroundStyle(AppColors.danger)
                    .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            }
        }
        .cardStyle()
    }

    private func menuRow(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: icon).foregroundStyle(AppColors.textPrimary)
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(AppColors.textTertiary)
            }
            .frame(minHeight: 48)
        }
        .buttonStyle(.plain)
    }

    private var editNameSheet: some View {
        NavigationStack {
            Form {
                Section("Display name") {
                    TextField("Your name", text: $viewModel.editedName)
                        .textContentType(.name)
                    if !viewModel.isNameValid {
                        Text("Use 2–40 letters").font(AppFont.caption).foregroundStyle(AppColors.danger)
                    }
                }
                if let error = viewModel.errorMessage {
                    Text(error).foregroundStyle(AppColors.danger)
                }
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { showsEditName = false } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await viewModel.saveName() { showsEditName = false } }
                    }
                    .disabled(!viewModel.isNameValid || viewModel.isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
