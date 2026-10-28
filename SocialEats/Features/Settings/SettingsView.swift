//
//  SettingsView.swift
//  SocialEats
//
//  Prototype Figure 7 — Settings & Preferences (MVP Feature 2):
//  theme (Light/Dark/System), nearby alerts + radius, dietary filters,
//  Face ID protection, privacy policy and log out.
//

import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var errorMessage: String?
    @Published var infoMessage: String?
    @Published private(set) var isSeeding = false

    let container: AppContainer
    var settings: SettingsStore { container.settings }

    init(container: AppContainer) {
        self.container = container
    }

    var biometricKind: BiometricKind { container.biometrics.availableKind }
    var isDemoMode: Bool { container.isDemoMode }

    var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "v\(version) (\(build))"
    }

    /// Dietary chips also sync to the Firestore profile.
    func toggleDietary(_ tag: DietaryTag) {
        settings.toggleDietary(tag)
        Haptics.selection()
        guard var user = container.session.currentUser else { return }
        user.dietaryTags = settings.dietaryTags
        Task { try? await container.session.updateProfile(user) }
    }

    /// Turning Face ID protection ON must pass Face ID first (so nobody else can enable/disable it).
    func setFaceIDProtection(_ enabled: Bool) async {
        if biometricKind == .none {
            errorMessage = BiometricError.notAvailable.localizedDescription
            return
        }
        let result = await container.biometrics.authenticate(
            reason: enabled ? "Turn on Face ID protection" : "Turn off Face ID protection")
        switch result {
        case .success: settings.faceIDProtectionEnabled = enabled
        case .failure(let error): errorMessage = error.localizedDescription
        }
    }

    func setNearbyAlerts(_ enabled: Bool) async {
        settings.nearbyAlertsEnabled = enabled
        if enabled {
            let granted = await container.notifications.requestPermission()
            if !granted {
                errorMessage = "Notifications are off for SocialEats. Turn them on in the iPhone Settings app."
            }
        }
    }

    func addSampleTables() async {
        isSeeding = true
        do {
            let count = try await container.addSampleTablesNearUser()
            infoMessage = count == 0
                            ? "Sample tables are already there 👍"
                            : "Added \(count) sample tables near you 🎉"
        } catch {
            errorMessage = error.localizedDescription
        }
        isSeeding = false
    }

    func signOut() {
        container.session.signOut()
    }
}

struct SettingsView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var navigation: NavigationModel
    @EnvironmentObject private var session: SessionStore
    @StateObject private var viewModel: SettingsViewModel
    @State private var showsLogoutConfirm = false
    @State private var showsPrivacy = false

    init(container: AppContainer) {
        _viewModel = StateObject(wrappedValue: SettingsViewModel(container: container))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        OverlineText(text: "SocialEats experience")
                        Text("Settings & Preferences")
                            .font(AppFont.title)
                            .foregroundStyle(AppColors.textPrimary)
                    }
                    Spacer()
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(AppColors.primary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppColors.primarySoft))
                        .accessibilityHidden(true)
                }

                if let error = viewModel.errorMessage {
                    ErrorBanner(message: error) { viewModel.errorMessage = nil }
                }
                if let info = viewModel.infoMessage {
                    Label(info, systemImage: "checkmark.circle.fill")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColors.success)
                }

                appearanceSection
                notificationSection
                dietarySection
                accessibilitySection
                accountSection
                aboutSection
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .safeAreaInset(edge: .top, spacing: 0) {
            AppHeader(title: "Settings",
                      onSearch: { navigation.open(.search, on: navigation.selectedTab) },
                      onBell: { navigation.open(.notifications, on: navigation.selectedTab) },
                      hasUnread: session.unreadCount > 0,
                      avatarName: session.currentUser?.displayName,
                      onAvatar: { navigation.selectedTab = .profile })
        }
        .toolbar(.hidden, for: .navigationBar)
        // Standard iOS alert in the middle of the screen: "Log out?"  [Cancel] [Log Out]
        .alert("Log out?", isPresented: $showsLogoutConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Log Out", role: .destructive) { viewModel.signOut() }
        } message: {
            Text("You can sign back in anytime with your phone number. Your offline passes stay on this phone.")
        }
        .sheet(isPresented: $showsPrivacy) { PrivacyPolicyView() }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OverlineText(text: "Appearance")
                Spacer()
                Text("Preview Mode").font(AppFont.caption).foregroundStyle(AppColors.primary)
            }
            HStack(spacing: 6) {
                ForEach(AppTheme.allCases) { theme in
                    let isOn = settings.theme == theme
                    Button {
                        withAnimation(.easeInOut) { settings.theme = theme }
                        Haptics.selection()
                    } label: {
                        Label(theme.title, systemImage: theme.iconName)
                            .font(AppFont.subheadline.weight(isOn ? .semibold : .regular))
                            .foregroundStyle(isOn ? AppColors.textPrimary : AppColors.textSecondary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .background(RoundedRectangle(cornerRadius: 10).fill(isOn ? AppColors.surface : Color.clear))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(isOn ? AppColors.primary : Color.clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? [.isSelected] : [])
                }
            }
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surfaceMuted))
        }
    }

    // MARK: - Notifications & geofence

    private var notificationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText(text: "Notifications & Geofence")
            VStack(spacing: 14) {
                Toggle(isOn: Binding(get: { settings.nearbyAlertsEnabled },
                                     set: { value in Task { await viewModel.setNearbyAlerts(value) } })) {
                    settingRow(icon: "table.furniture", title: "Nearby Table Alerts", subtitle: "Real-time open seat invitations")
                }
                .tint(AppColors.success)

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label("Proximity Radius: \(settings.radiusLabel)", systemImage: "scope")
                            .font(AppFont.subheadline.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Spacer()
                        BadgeView(text: settings.radiusHint, foreground: AppColors.amber, background: AppColors.amberSoft)
                    }
                    Slider(value: $settings.proximityRadiusKm, in: SettingsStore.radiusRange, step: 0.5)
                        .tint(AppColors.primary)
                        .accessibilityLabel("Proximity radius")
                        .accessibilityValue(settings.radiusLabel)
                    HStack {
                        Text("0.5 km (Walking)")
                        Spacer()
                        Text("5.0 km (Drive)")
                    }
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .accessibilityHidden(true)
                }

                Divider()

                Toggle(isOn: $settings.meetupRemindersEnabled) {
                    settingRow(icon: "alarm", title: "Meetup Reminders", subtitle: "1 hour before your table starts")
                }
                .tint(AppColors.success)
            }
            .cardStyle()
        }
    }

    // MARK: - Dietary

    private var dietarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                OverlineText(text: "Dietary Preferences")
                Spacer()
                Text("Saved to Social Taste Profile").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
            }
            VStack(alignment: .leading, spacing: 10) {
                Text("Filter social culinary invitations and restaurant recommendations matching your lifestyle.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                ChipGrid {
                    ForEach(DietaryTag.allCases) { tag in
                        ChipView(title: tag.title, icon: tag.emoji,
                                 isSelected: settings.dietaryTags.contains(tag),
                                 selectedColor: tag.isAllergy ? AppColors.danger : (tag == .halal ? AppColors.halalChip : AppColors.teal)) {
                            viewModel.toggleDietary(tag)
                        }
                    }
                }
            }
            .cardStyle()
        }
    }

    // MARK: - Accessibility (proposal Feature 2: "provides accessibility options")

    /// The slider works with numbers (0...5), so this turns the
    /// saved text size into a number and back again.
    private var textSizeSliderValue: Binding<Double> {
        Binding(
            get: { Double(settings.textSize.rawValue) },
            set: { newValue in
                settings.textSize = AppTextSize(rawValue: Int(newValue.rounded())) ?? .standard
            }
        )
    }

    private var accessibilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText(text: "Accessibility")
            VStack(spacing: 12) {
                // Text Size: "A-" button, slider, "A+" button
                VStack(alignment: .leading, spacing: 10) {
                    settingRow(icon: "textformat.size", title: "Text Size",
                               subtitle: settings.textSize.title)

                    HStack(spacing: 12) {
                        Button {
                            settings.makeTextSmaller()
                        } label: {
                            Image(systemName: "textformat.size.smaller")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(AppColors.primarySoft))
                        }
                        .disabled(settings.textSize == .extraSmall)
                        .accessibilityLabel("Smaller text")

                        // Drag to pick a size (6 steps)
                        Slider(value: textSizeSliderValue,
                               in: 0...Double(AppTextSize.allCases.count - 1),
                               step: 1)
                            .tint(AppColors.primary)
                            .accessibilityLabel("Text size")
                            .accessibilityValue(settings.textSize.title)

                        Button {
                            settings.makeTextBigger()
                        } label: {
                            Image(systemName: "textformat.size.larger")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(AppColors.primary)
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(AppColors.primarySoft))
                        }
                        .disabled(settings.textSize == .huge)
                        .accessibilityLabel("Bigger text")
                    }
                    .buttonStyle(.plain)
                }

                Divider()

                Toggle(isOn: $settings.hapticsEnabled) {
                    settingRow(icon: "iphone.radiowaves.left.and.right", title: "Vibration Feedback",
                               subtitle: "Haptics for shakes, seats and errors")
                }
                .tint(AppColors.success)

                Divider()

                Text("SocialEats also follows your iPhone's VoiceOver, Dynamic Type, Bold Text and Reduce Motion settings.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .cardStyle()
        }
    }

    // MARK: - Account

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            OverlineText(text: "Account & Security")
            VStack(spacing: 4) {
                Toggle(isOn: Binding(get: { settings.faceIDProtectionEnabled },
                                     set: { value in Task { await viewModel.setFaceIDProtection(value) } })) {
                    settingRow(icon: viewModel.biometricKind.systemImage,
                               title: "\(viewModel.biometricKind == .none ? "Face ID" : viewModel.biometricKind.title) Protection",
                               subtitle: "Secure seat changes & app lock")
                }
                .tint(AppColors.success)
                .padding(.vertical, 6)

                Divider()

                Button { navigation.open(.myPasses, on: navigation.selectedTab) } label: {
                    HStack {
                        settingRow(icon: "wallet.pass", title: "My Offline Passes", subtitle: "Stored on this phone with Core Data")
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(AppColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)

                Divider()

                Button { showsPrivacy = true } label: {
                    HStack {
                        settingRow(icon: "shield", title: "Privacy Policy", subtitle: nil)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(AppColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)

                Divider()

                Button { showsLogoutConfirm = true } label: {
                    HStack {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .foregroundStyle(AppColors.danger)
                            .frame(width: 34, height: 34)
                            .background(RoundedRectangle(cornerRadius: 9).fill(AppColors.dangerSoft))
                        Text("Log Out").font(AppFont.body.weight(.semibold)).foregroundStyle(AppColors.danger)
                        Spacer()
                        Text(viewModel.appVersion).font(AppFont.caption).foregroundStyle(AppColors.textTertiary)
                    }
                    .frame(minHeight: AppLayout.minTapTarget)
                }
                .buttonStyle(.plain)
            }
            .cardStyle()
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(spacing: 10) {
            if viewModel.isDemoMode {
                Label("Demo mode — add GoogleService-Info.plist to use Firebase", systemImage: "info.circle")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.amber)
            }
            Button {
                Task { await viewModel.addSampleTables() }
            } label: {
                if viewModel.isSeeding {
                    ProgressView()
                } else {
                    Label("Add sample tables near me (for demo)", systemImage: "wand.and.stars")
                }
            }
            .buttonStyle(SoftButtonStyle())
            .disabled(viewModel.isSeeding)

            Label("Crafted for Food Enthusiasts", systemImage: "heart.fill")
                .font(AppFont.caption)
                .foregroundStyle(AppColors.textSecondary)
            Text("SocialEats • NIBM iOS Coursework • Colombo")
                .font(AppFont.caption)
                .foregroundStyle(AppColors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    /// Icon + title + subtitle used by every row.
    private func settingRow(icon: String, title: String, subtitle: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(AppColors.primary)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9).fill(AppColors.primarySoft))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(AppFont.body.weight(.semibold)).foregroundStyle(AppColors.textPrimary)
                if let subtitle {
                    Text(subtitle).font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }
}

/// Plain-English privacy summary (inclusive, readable).
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    policy("Location", "Used only to show tables near you and to send arrival alerts for tables you joined. Never shared with other members — they only see the venue.")
                    policy("Face ID", "Handled entirely by iOS. SocialEats never sees or stores your face data.")
                    policy("Receipts", "Scanned on your iPhone with Apple's Vision framework. Only the restaurant name, total and time are saved — never the photo.")
                    policy("Chats", "Only confirmed members of a table can read its chat.")
                    policy("Your data", "Your profile and karma are stored in Firebase. Log out at any time; offline passes stay on your phone.")
                }
                .padding(20)
            }
            .screenBackground()
            .navigationTitle("Privacy Policy")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func policy(_ title: String, _ body: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(AppFont.headline).foregroundStyle(AppColors.textPrimary)
            Text(body).font(AppFont.body).foregroundStyle(AppColors.textSecondary)
        }
        .cardStyle()
    }
}

