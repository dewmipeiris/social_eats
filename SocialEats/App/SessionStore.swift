//
//  SessionStore.swift
//  SocialEats
//
//  Decides WHICH part of the app is showing (the "phase") and keeps
//  the signed-in user's profile + notification feed up to date.
//
//  Flow (matches the prototype):
//   Onboarding ─ Get Started ─> Taste Profile (Step 1 of 2) ─> Sign In (Step 2 of 2) ─> Main app
//        │                                                        ▲
//        ├─ "Already part of a table? Sign In" ───────────────────┘
//        └─ Skip ─> Guest browse (read-only)
//

import Foundation
import Combine

/// The big screens the app can be on.
enum AppPhase: Equatable {
    case loading
    case onboarding
    case tasteProfile
    case signIn
    case guest
    case locked        // waiting for Face ID
    case main
}

@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var phase: AppPhase = .loading
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var activity: [ActivityItem] = []
    /// Choices from the Taste Profile screen, saved once the user signs in
    @Published var tasteDraft = TasteProfileDraft()
    /// Set when a notification is tapped -> the Home tab opens that table
    @Published var pendingTableId: String?

    private let auth: AuthServicing
    private let users: UserServicing
    private let biometrics: BiometricServicing
    private let settings: SettingsStore

    private var userListener: ListenerToken?
    private var activityListener: ListenerToken?

    init(auth: AuthServicing, users: UserServicing, biometrics: BiometricServicing, settings: SettingsStore) {
        self.auth = auth
        self.users = users
        self.biometrics = biometrics
        self.settings = settings
    }

    var userId: String? { currentUser?.id ?? auth.currentUserId }
    var unreadCount: Int { activity.filter { !$0.isRead }.count }
    var biometricKind: BiometricKind { biometrics.availableKind }

    /// True when "Login with Face ID" can be offered on the sign-in screen
    var canUseBiometricLogin: Bool {
        auth.currentUserId != nil && biometrics.availableKind != .none
    }

    // MARK: - Start up

    /// Called once when the app opens.
    func bootstrap() async {
        if !settings.hasSeenOnboarding {
            phase = .onboarding
        } else if let uid = auth.currentUserId {
            // Already signed in — lock behind Face ID if the user turned that on
            if settings.faceIDProtectionEnabled && biometrics.availableKind != .none {
                phase = .locked
            } else {
                await finishSignIn(userId: uid)
            }
        } else {
            phase = .signIn
        }
    }

    // MARK: - Onboarding navigation

    func startTasteProfile() {
        settings.hasSeenOnboarding = true
        phase = .tasteProfile
    }

    func showOnboarding() {
        phase = .onboarding
    }

    func goToSignIn() {
        settings.hasSeenOnboarding = true
        phase = .signIn
    }

    func browseAsGuest() {
        settings.hasSeenOnboarding = true
        phase = .guest
    }

    func completeTasteProfile(_ draft: TasteProfileDraft) {
        tasteDraft = draft
        // Copy dietary choices into Settings so filters work straight away
        if !draft.dietaryTags.isEmpty { settings.dietaryTags = draft.dietaryTags }
        phase = .signIn
    }

    // MARK: - Signing in / out

    /// Called by AuthViewModel after Firebase says the sign-in worked.
    func finishSignIn(userId: String) async {
        phase = .loading
        do {
            if let existing = try await users.fetchUser(id: userId) {
                currentUser = existing
            } else {
                // First time: create the profile with the starting karma score
                let name = defaultName()
                var draft = tasteDraft
                draft.dietaryTags = settings.dietaryTags
                let newUser = AppUser.newMember(id: userId, name: name,
                                                phone: auth.currentPhone, email: auth.currentEmail,
                                                draft: draft)
                try await users.saveUser(newUser)
                currentUser = newUser
            }
        } catch {
            // Offline on launch: continue with a basic profile, listeners will fill it in later
            currentUser = currentUser ?? AppUser.newMember(id: userId, name: defaultName(),
                                                           phone: auth.currentPhone, email: auth.currentEmail,
                                                           draft: tasteDraft)
        }

        if let user = currentUser, !user.dietaryTags.isEmpty, settings.dietaryTags.isEmpty {
            settings.dietaryTags = user.dietaryTags
        }

        startListeners(userId: userId)
        phase = .main
    }

    /// Name for a brand-new profile: Google name, else email name, else "Foodie 4567".
    private func defaultName() -> String {
        if let name = auth.currentDisplayName, !name.isEmpty { return name }
        if let email = auth.currentEmail, let first = email.components(separatedBy: "@").first {
            return first.capitalized
        }
        if let phone = auth.currentPhone {
            return "Foodie " + String(phone.suffix(4))
        }
        return "Foodie"
    }

    /// "Login with Face ID" / unlocking the app.
    /// Returns an error message, or nil on success.
    func unlockWithBiometrics() async -> String? {
        guard let uid = auth.currentUserId else {
            return "Please sign in with your phone number first."
        }
        let result = await biometrics.authenticate(reason: "Unlock SocialEats to see your tables and passes")
        switch result {
        case .success:
            if currentUser?.id == uid {
                phase = .main          // re-unlock after backgrounding: keep everything loaded
            } else {
                await finishSignIn(userId: uid)
            }
            return nil
        case .failure(let error):
            return error.localizedDescription
        }
    }

    func signOut() {
        try? auth.signOut()
        userListener?.remove()
        activityListener?.remove()
        currentUser = nil
        activity = []
        tasteDraft = TasteProfileDraft()
        settings.resetForSignOut()
        phase = .signIn
    }

    /// Called when the app goes to the background with Face ID Protection on.
    func lockApp() {
        guard phase == .main else { return }
        phase = .locked
    }

    /// Guest wants to create an account
    func leaveGuestMode() {
        phase = .tasteProfile
    }

    // MARK: - Profile updates

    func updateProfile(_ user: AppUser) async throws {
        try await users.saveUser(user)
        currentUser = user
    }

    func markAllActivityRead() async {
        guard let uid = userId else { return }
        let unreadIds = activity.filter { !$0.isRead }.map(\.id)
        try? await users.markActivityRead(userId: uid, itemIds: unreadIds)
    }

    // MARK: - Live listeners

    private func startListeners(userId: String) {
        userListener?.remove()
        activityListener?.remove()

        userListener = users.listenToUser(id: userId) { [weak self] user in
            Task { @MainActor in
                if let user { self?.currentUser = user }
            }
        }
        activityListener = users.listenToActivity(userId: userId) { [weak self] items in
            Task { @MainActor in
                self?.activity = items
            }
        }
    }
}
