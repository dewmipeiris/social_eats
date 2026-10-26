//
//  AppHeader.swift
//  SocialEats
//
//  The top bar used on most screens in the prototype:
//  [🍴 logo] Title ............ [search] [bell] [avatar]
//

import SwiftUI

/// Rounded square with the fork & knife logo.
struct AppLogoBadge: View {
    var size: CGFloat = 36

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.3)
            .stroke(AppColors.primary, lineWidth: 1.5)
            .background(
                RoundedRectangle(cornerRadius: size * 0.3).fill(AppColors.primarySoft.opacity(0.5))
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "fork.knife")
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(AppColors.primary)
            )
            .accessibilityHidden(true)
    }
}

/// Custom header bar that matches the Figma design.
struct AppHeader: View {
    let title: String
    var showsBack: Bool = false
    var onBack: (() -> Void)? = nil
    var onSearch: (() -> Void)? = nil
    var onBell: (() -> Void)? = nil
    var hasUnread: Bool = false
    var avatarName: String? = nil
    var onAvatar: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if showsBack, let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .frame(width: AppLayout.minTapTarget, height: AppLayout.minTapTarget)
                }
                .accessibilityLabel("Back")
            }

            AppLogoBadge()

            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColors.textPrimary)
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            if let onSearch {
                CircleIconButton(systemImage: "magnifyingglass", accessibilityText: "Search", action: onSearch)
            }
            if let onBell {
                CircleIconButton(
                    systemImage: "bell",
                    accessibilityText: hasUnread ? "Notifications, unread items" : "Notifications",
                    showsBadge: hasUnread,
                    action: onBell
                )
            }
            if let avatarName {
                Button {
                    onAvatar?()
                } label: {
                    AvatarView(name: avatarName, size: 34)
                }
                .accessibilityLabel("Your profile")
                .disabled(onAvatar == nil)
            }
        }
        .padding(.horizontal, AppLayout.screenPadding - 4)
        .padding(.vertical, 6)
        .background(AppColors.background)
    }
}
