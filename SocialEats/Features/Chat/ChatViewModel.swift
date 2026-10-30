//  ChatViewModel.swift

import Foundation
import Combine

struct TablemateProfile: Identifiable, Equatable {
    let id: String
    let name: String
    let isHost: Bool
    let isMe: Bool
    let user: AppUser?
    let mutualInterests: [String]

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
    
    let quickReplies = ["Running 2 mins behind! 🏃", "Arrived! Sitting near the outdoor patio 🌿",
                        "Just arrived 👋", "Order me a drink 🥤"]

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

    var startsInText: String {
        guard let table else { return "" }
        let minutes = Int(table.startTime.timeIntervalSinceNow / 60)
        if minutes <= 0 { return "Started" }
        if minutes < 120 { return "Starts in \(minutes) min" }
        return table.startTime.friendlyDayTime
    }

    var showsZeroFlakeReminder: Bool { table?.isFull ?? false }

    func isMine(_ message: ChatMessage) -> Bool { message.senderId == myUserId }

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
       
        tablemates = result.sorted { ($0.isHost ? 0 : $0.isMe ? 2 : 1) < ($1.isHost ? 0 : $1.isMe ? 2 : 1) }
        isLoadingTablemates = false
    }

    static func mutualInterests(me: AppUser?, them: AppUser) -> [String] {
        guard let me else { return [] }
        let cuisines = them.cuisines.filter { me.cuisines.contains($0) }.map(\.title)
        let vibes = them.ambiences.filter { me.ambiences.contains($0) }.map(\.title)
        let diet = them.dietaryTags.filter { me.dietaryTags.contains($0) && !$0.isAllergy }.map(\.title)
        return cuisines + vibes + diet
    }

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
            try await chat.sendMessage(message, tableId: tableId)
        } catch {
            errorMessage = "Message not sent: \(error.localizedDescription)"
            if text == nil { draft = body }    // give the text back so it isn't lost
        }
    }
}
