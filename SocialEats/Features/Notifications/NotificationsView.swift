//  NotificationsView.swift

import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var navigation: NavigationModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        OverlineText(text: "Activity", color: AppColors.amber)
                        Text("Notifications").font(AppFont.title).foregroundStyle(AppColors.textPrimary)
                    }
                    Spacer()
                    if session.unreadCount > 0 {
                        Button {
                            Task { await session.markAllActivityRead() }
                        } label: {
                            Label("Mark read", systemImage: "checkmark.circle")
                                .font(AppFont.footnote.weight(.semibold))
                                .foregroundStyle(AppColors.teal)
                                .padding(.horizontal, 12)
                                .frame(minHeight: 36)
                                .background(Capsule().fill(AppColors.surfaceMuted))
                        }
                    }
                }

                if session.activity.isEmpty {
                    EmptyStateView(systemImage: "bell.slash",
                                   title: "No activity yet",
                                   message: "Seat confirmations, karma rewards and invites will show up here.")
                        .cardStyle()
                } else {
                    ForEach(session.activity) { item in
                        ActivityRow(item: item) {
                            if let tableId = item.tableId {
                                navigation.open(.table(tableId), on: navigation.selectedTab)
                            }
                        }
                    }
                    Label("You are all caught up for today", systemImage: "checkmark.circle")
                        .font(AppFont.footnote)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .padding(AppLayout.screenPadding)
            .frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
        }
        .screenBackground()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct ActivityRow: View {
    let item: ActivityItem
    let onOpen: () -> Void

    private var tint: Color {
        switch item.kind {
        case .seatConfirmed: return AppColors.success
        case .karmaUnlocked: return AppColors.amber
        case .tableInvite: return AppColors.teal
        case .meetupReminder: return AppColors.textSecondary
        case .newTableNearby: return AppColors.primary
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .foregroundStyle(tint)
                .frame(width: 46, height: 46)
                .background(Circle().fill(tint.opacity(0.15)))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    Spacer()
                    if !item.isRead {
                        Circle().fill(AppColors.primary).frame(width: 8, height: 8)
                            .accessibilityLabel("Unread")
                    } else {
                        Text(item.createdAt.relativeText)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                if let points = item.points {
                    BadgeView(text: "+\(points) pts", foreground: AppColors.amber, background: AppColors.amberSoft)
                }
                Text(item.body)
                    .font(AppFont.subheadline)
                    .foregroundStyle(AppColors.textSecondary)
                if item.tableId != nil {
                    Button(action: onOpen) {
                        Text(item.kind == .tableInvite ? "Join Table" : "View Table")
                            .font(AppFont.footnote.weight(.semibold))
                            .foregroundStyle(AppColors.onPrimary)
                            .padding(.horizontal, 16)
                            .frame(minHeight: 36)
                            .background(Capsule().fill(AppColors.primary))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .cardStyle()
        .accessibilityElement(children: .combine)
    }
}
