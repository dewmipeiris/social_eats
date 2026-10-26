//
//  ChatViewModel.swift
//  SocialEats
//
//  Proposal MVP Feature 7 — Community Hub.
//   1. Confirmed table members get a TEMPORARY group chat attached to the meetup
//      (it closes 24 hours after the meal starts).
//   2. Members can view each other's profiles, MUTUAL INTERESTS and verified
//      badge standing (karma tier) — builds trust before meeting.
//   3. Members send quick coordination messages ("Arrived! Sitting near the patio").
//  Real-time Firestore listener on tables/{id}/messages.
//

import Foundation
import Combine

/// One person at the table, as shown in the "Tablemates" sheet.
struct TablemateProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let isHost: Bool
    let isMe: Bool
    /// nil when the person's profile couldn't be loaded
    let user: AppUser?
    /// Cuisines / vibes / dietary choices you both picked
    let mutualInterests: [String]

    /// "Verified" = they signed in with a verified phone number or email
    var isVerified: Bool {
        user?.phoneNumber != nil || user?.email != nil
    }

    var tier: KarmaCalculator.Tier? { user.map { KarmaCalculator.tier(for: $0.karma) } }
    var level: Int? { user.map { KarmaCalculator.level(for: $0.karma) } }
}

@MainActor
final class ChatViewModel: ObservableObject {

    @Published private(set) var messages: [ChatMessage] = []
    @Published private(set) var table: CommunityTable?
    @Published private(set) var tablemates: [TablemateProfile] = []
    @Published private(set) var isLoadingTablemates = false
    @Published var draft = ""
    @Published var errorMessage: String?

    /// One-tap coordination messages (from the prototype)
    let quickReplies = ["Running 2 mins behind! 🏃", "Arrived! Sitting near the outdoor patio 🌿",
                        "Just arrived 👋", "Order me a drink 🥤"]

    /// The chat is temporary: read-only this long after the meal starts
    static let chatOpenHoursAfterStart: Double = 24

    let tableId: String
    private let chat: ChatServicing
    private let tableService: TableServicing
    private let users: UserServicing
    private let session: SessionStore
    private var messageListener: ListenerToken?
    private var tableListener: ListenerToken?

    init(tableId: String, chat: ChatServicing, tableService: TableServicing,
         users: UserServicing, session: SessionStore) {
        self.tableId = tableId
        self.chat = chat
        self.tableService = tableService
        self.users = users
        self.session = session
    }

    convenience init(tableId: String, container: AppContainer) {
        self.init(tableId: tableId, chat: container.chat, tableService: container.tableService,
                  users: container.users, session: container.session)
    }

    // MARK: - Derived state

    var myUserId: String? { session.userId }

    /// Only members may see the chat (keeps strangers out — trust & safety)
    var isMember: Bool { table?.isAttending(myUserId) ?? false }

    /// True once the temporary chat has ended
    var isChatClosed: Bool {
        guard let table else { return false }
        return Date() > table.startTime.addingTimeInterval(Self.chatOpenHoursAfterStart * 3600)
    }

    var canChat: Bool { isMember && !isChatClosed }

    var canSend: Bool {
        canChat && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// "Starts in 45 min" / "Started" / "Tomorrow, 7:00 PM"
    var startsInText: String {
        guard let table else { return "" }
        let minutes = Int(table.startTime.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Started" }
        if minutes < 120 { return "Starts in \(minutes) min" }
        return table.startTime.friendlyDayTime
    }

    /// Shows the green "Zero-Flake Reminder" when every seat is taken
    var showsZeroFlakeReminder: Bool { table?.isFull ?? false }

    func isMine(_ message: ChatMessage) -> Bool { message.senderId == myUserId }

    // MARK: - Lifecycle

    func start() {
        tableListener = tableService.listenToTable(id: tableId) { [weak self] table in
            Task { @MainActor in self?.table = table }
        }
        messageListener = chat.listenToMessages(tableId: tableId) { [weak self] messages in
            Task { @MainActor in self?.messages = messages }
        }
    }

    func stop() {
        tableListener?.remove()
        messageListener?.remove()
    }

    // MARK: - Tablemate profiles

    /// Loads every member's profile and works out mutual interests.
    func loadTablemates() async {
        guard let table else { return }
        isLoadingTablemates = true
        let me = session.currentUser
        var result: [TablemateProfile] = []

        for (index, memberId) in table.attendeeIds.enumerated() {
            let name = index < table.attendeeNames.count ? table.attendeeNames[index] : "Member"
            let user = try? await users.fetchUser(id: memberId)
            let isMe = memberId == myUserId
            result.append(TablemateProfile(
                id: memberId,
                name: user?.displayName ?? name,
                isHost: table.isHost(memberId),
                isMe: isMe,
                user: user,
                mutualInterests: (isMe || user == nil) ? [] : Self.mutualInterests(me: me, them: user!)
            ))
        }
        // Host first, then everyone else, me last
        tablemates = result.sorted { ($0.isHost ? 0 : $0.isMe ? 2 : 1) < ($1.isHost ? 0 : $1.isMe ? 2 : 1) }
        isLoadingTablemates = false
    }

    /// Things both people chose in their taste profile (unit tested).
    static func mutualInterests(me: AppUser?, them: AppUser) -> [String] {
        guard let me else { return [] }
        let cuisines = them.cuisines.filter { me.cuisines.contains($0) }.map(\.title)
        let vibes = them.ambiences.filter { me.ambiences.contains($0) }.map(\.title)
        let diet = them.dietaryTags.filter { me.dietaryTags.contains($0) && !$0.isAllergy }.map(\.title)
        return cuisines + vibes + diet
    }

    // MARK: - Sending

    func send(_ text: String? = nil) async {
        let body = (text ?? draft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard canChat, !body.isEmpty, let user = session.currentUser else { return }

        let message = ChatMessage(
            id: UUID().uuidString,
            senderId: user.id,
            senderName: user.displayName,
            text: body,
            sentAt: Date(),
            isFromHost: table?.isHost(user.id) ?? false
        )
        if text == nil { draft = "" }
        Haptics.selection()

        do {
            // Offline? Firestore keeps the message on the phone (shown as
            // "Sending…") and uploads it automatically when back online.
            try await chat.sendMessage(message, tableId: tableId)
        } catch {
            errorMessage = "Message not sent: \(error.localizedDescription)"
            if text == nil { draft = body }    // give the text back so it isn't lost
        }
    }
}
