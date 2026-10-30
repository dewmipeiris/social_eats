//  SessionStore.swift

import Foundation
import Combine

enum AppPhase: Equatable {
    case loading
    case onboarding
    case tasteProfile
    case signIn
    case guest
    case locked
    case main
}

@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var phase: AppPhase = .loading
    @Published private(set) var currentUser: AppUser?
    @Published private(set) var activity: [ActivityItem] = []
    @Published var tasteDraft = TasteProfileDraft()
    @Published var pendingTableId: String?
    @Published var scannedPass: ScannedPass?

    private let auth: AuthServicing
    private let users: UserServicing
    private let biometrics: BiometricServicing
    private let settings: SettingsStore

    private var hasBootstrapped = false
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
    var canUseBiometricLogin: Bool {
        biometrics.availableKind != .none
    }
    var hasSavedAccount: Bool {
        auth.currentUserId != nil
    }

// start up
    
    func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        if let uid = auth.currentUserId {
            if settings.faceIDProtectionEnabled && biometrics.isSetUp {
                phase = .signIn
            } else {
                await finishSignIn(userId: uid)
            }
        } else {
            phase = .onboarding
        }
    }

// onboarding navigation

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
        if !draft.dietaryTags.isEmpty { settings.dietaryTags = draft.dietaryTags }
        phase = .signIn
    }

// signing out

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

    func unlockWithBiometrics() async -> String? {
        guard let uid = auth.currentUserId else {
            return "Sign in once with your phone number below. Next time you open SocialEats, Face ID logs you straight in."
        }
        let result = await biometrics.authenticate(reason: "Unlock SocialEats to see your tables and passes")
        switch result {
        case .success:
            if currentUser?.id == uid {
                phase = .main
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

    func lockApp() {
        guard phase == .main else { return }
        phase = .locked
    }

    func leaveGuestMode() {
        phase = .tasteProfile
    }

// profile updates

    func updateProfile(_ user: AppUser) async throws {
        try await users.saveUser(user)
        currentUser = user
    }

    func markAllActivityRead() async {
        guard let uid = userId else { return }
        let unreadIds = activity.filter { !$0.isRead }.map(\.id)
        try? await users.markActivityRead(userId: uid, itemIds: unreadIds)
    }

// live listeners

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
