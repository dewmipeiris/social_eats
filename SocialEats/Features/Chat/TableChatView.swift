//  TableChatView.swift

import SwiftUI
import MapKit

struct TableChatView: View {
    @StateObject private var viewModel: ChatViewModel
    @FocusState private var inputFocused: Bool
    @State private var showsTablemates = false

    init(tableId: String, container: AppContainer) {
        _viewModel = StateObject(wrappedValue: ChatViewModel(tableId: tableId, container: container))
    }

    var body: some View {
        VStack(spacing: 0) {
            if let table = viewModel.table {
                tableHeader(table)
            }

            if viewModel.table != nil && !viewModel.isMember {
                EmptyStateView(systemImage: "lock.fill",
                               title: "Members only",
                               message: "Join this table to chat with your tablemates.")
                Spacer()
            } else {
                messagesList
                if viewModel.isChatClosed {
                    Label("This temporary chat closed 24 hours after the meal. Messages are read-only.",
                          systemImage: "lock.clock")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(AppLayout.screenPadding)
                        .frame(maxWidth: .infinity)
                        .background(AppColors.surface)
                } else {
                    inputArea
                }
            }
        }
        .screenBackground()
        .navigationTitle("Table Group Chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { viewModel.start() }
        .onDisappear { viewModel.stop() }
        .sheet(isPresented: $showsTablemates) {
            TablematesSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private func tableHeader(_ table: CommunityTable) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "fork.knife")
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(AppColors.primarySoft))
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(table.venueName).font(AppFont.headline).lineLimit(1)
                        Circle().fill(AppColors.success).frame(width: 7, height: 7)
                    }
                    Text("Table #\(table.tableNumber) • \(table.seatsFilled) Confirmed")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
                BadgeView(text: "🕖 \(viewModel.startsInText)", foreground: AppColors.amber, background: AppColors.amberSoft)
            }
            HStack {
                Button {
                    showsTablemates = true
                } label: {
                    HStack(spacing: 6) {
                        AvatarStack(names: table.attendeeNames, maxVisible: 4, size: 28)
                        Text("Tablemates")
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.textPrimary)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(AppColors.textTertiary)
                    }
                }
                .buttonStyle(.plain)
                .disabled(!viewModel.isMember)
                .accessibilityLabel("View tablemates' profiles")
                Spacer()
                Button {
                    let item = MKMapItem(placemark: MKPlacemark(coordinate: table.coordinate))
                    item.name = table.venueName
                    item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
                } label: {
                    Label("Get Directions", systemImage: "location.north.line")
                        .font(AppFont.footnote.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                        .padding(.horizontal, 12)
                        .frame(minHeight: 34)
                        .background(Capsule().fill(AppColors.primarySoft))
                }
            }
        }
        .cardStyle(padding: 12)
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.top, 8)
    }

    private var messagesList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    if viewModel.messages.isEmpty {
                        EmptyStateView(systemImage: "bubble.left.and.bubble.right",
                                       title: "Say hi to your tablemates 👋",
                                       message: "Share when you're arriving or what you're craving.")
                    }
                    ForEach(viewModel.messages) { message in
                        MessageBubble(message: message, isMine: viewModel.isMine(message))
                            .id(message.id)
                    }
                    if viewModel.showsZeroFlakeReminder {
                        zeroFlakeCard
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(AppLayout.screenPadding)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
        }
    }

    private var zeroFlakeCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .foregroundStyle(AppColors.success)
                .frame(width: 34, height: 34)
                .background(Circle().fill(AppColors.successSoft))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Zero-Flake Reminder").font(AppFont.subheadline.weight(.semibold))
                    BadgeView(text: "ALL CONFIRMED")
                }
                Text("Every seat is confirmed with Face ID. Please let the table know if your plans change.")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14).fill(AppColors.surfaceMuted))
        .accessibilityElement(children: .combine)
    }

    private var inputArea: some View {
        VStack(spacing: 8) {
            if let error = viewModel.errorMessage {
                ErrorBanner(message: error) { viewModel.errorMessage = nil }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(viewModel.quickReplies, id: \.self) { reply in
                        Button(reply) { Task { await viewModel.send(reply) } }
                            .font(AppFont.footnote)
                            .foregroundStyle(AppColors.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(Capsule().fill(AppColors.surfaceMuted))
                            .overlay(Capsule().stroke(AppColors.border, lineWidth: 1))
                            .accessibilityHint("Sends this quick message")
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Message tablemates...", text: $viewModel.draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Capsule().fill(AppColors.surfaceMuted))
                    .submitLabel(.send)
                    .onSubmit { Task { await viewModel.send() } }

                Button {
                    Task { await viewModel.send() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(AppColors.onPrimary)
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(viewModel.canSend ? AppColors.primary : AppColors.textTertiary))
                }
                .disabled(!viewModel.canSend)
                .accessibilityLabel("Send message")
            }
        }
        .padding(.horizontal, AppLayout.screenPadding)
        .padding(.vertical, 8)
        .background(AppColors.surface)
    }
}

struct MessageBubble: View {
    let message: ChatMessage
    let isMine: Bool

    var body: some View {
        VStack(alignment: isMine ? .trailing : .leading, spacing: 4) {
            HStack(spacing: 6) {
                if !isMine {
                    Text(message.senderName).font(AppFont.caption.weight(.semibold))
                    if message.isFromHost {
                        Text("HOST")
                            .font(.system(size: 9, weight: .heavy, design: .rounded))
                            .foregroundStyle(AppColors.onPrimary)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(AppColors.amber))
                    }
                }
                Text(message.sentAt.shortTime)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textTertiary)
                if isMine { Text("You").font(AppFont.caption.weight(.semibold)) }
            }
            .foregroundStyle(AppColors.textPrimary)

            HStack(alignment: .bottom, spacing: 8) {
                if !isMine { AvatarView(name: message.senderName, size: 30) }
                Text(message.text)
                    .font(AppFont.body)
                    .foregroundStyle(isMine ? AppColors.myBubbleText : AppColors.textPrimary)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isMine ? AppColors.myBubble : AppColors.surface)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(isMine ? Color.clear : AppColors.border, lineWidth: 1)
                    )
                    .frame(maxWidth: 300, alignment: isMine ? .trailing : .leading)
            }

            // Sync status for my messages (offline -> "Sending…", uploaded -> "Delivered ✓")
            if isMine {
                Label(message.isPending ? "Sending…" : "Delivered",
                      systemImage: message.isPending ? "clock" : "checkmark")
                    .font(AppFont.caption)
                    .foregroundStyle(message.isPending ? AppColors.amber : AppColors.success)
            }
        }
        .frame(maxWidth: .infinity, alignment: isMine ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isMine ? "You" : message.senderName)\(message.isFromHost ? ", host" : ""), \(message.sentAt.shortTime): \(message.text)\(isMine ? (message.isPending ? ", sending" : ", delivered") : "")")
    }
}

struct TablematesSheet: View {
    @ObservedObject var viewModel: ChatViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if viewModel.isLoadingTablemates && viewModel.tablemates.isEmpty {
                        ProgressView("Loading profiles…").padding(30)
                    }
                    ForEach(viewModel.tablemates) { mate in
                        TablemateCard(mate: mate)
                    }
                }
                .padding(AppLayout.screenPadding)
            }
            .screenBackground()
            .navigationTitle("Your Tablemates")
            .navigationBarTitleDisplayMode(.inline)
            .task { await viewModel.loadTablemates() }
        }
    }
}

private struct TablemateCard: View {
    let mate: TablemateProfile

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                AvatarView(name: mate.name, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(mate.isMe ? "\(mate.name) (You)" : mate.name)
                            .font(AppFont.headline)
                            .foregroundStyle(AppColors.textPrimary)
                        if mate.isHost {
                            Text("HOST")
                                .font(.system(size: 9, weight: .heavy, design: .rounded))
                                .foregroundStyle(AppColors.onPrimary)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Capsule().fill(AppColors.amber))
                        }
                    }
                    if mate.isVerified {
                        Label("Verified Foodie", systemImage: "checkmark.seal.fill")
                            .font(AppFont.caption.weight(.semibold))
                            .foregroundStyle(AppColors.success)
                    } else {
                        Label("Not verified yet", systemImage: "questionmark.circle")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer()
                if let tier = mate.tier, let level = mate.level {
                    VStack(alignment: .trailing, spacing: 2) {
                        BadgeView(text: "🏅 \(tier.rawValue)", foreground: AppColors.amber, background: AppColors.amberSoft)
                        Text("Level \(level)").font(AppFont.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }

            if let user = mate.user {
                Text("\(user.mealsShared) shared meals • \(user.karma.formatted()) karma")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                Text("Profile details aren't available for this member.")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
            }

            if !mate.isMe && !mate.mutualInterests.isEmpty {
                Text("You both like").font(AppFont.overline).foregroundStyle(AppColors.textSecondary)
                ChipGrid {
                    ForEach(mate.mutualInterests, id: \.self) { interest in
                        BadgeView(text: interest, foreground: AppColors.primary, background: AppColors.primarySoft)
                    }
                }
            } else if !mate.isMe && mate.user != nil {
                Text("No shared interests yet — a great conversation starter!")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
