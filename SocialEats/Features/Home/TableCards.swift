//
//  TableCards.swift
//  SocialEats
//
//  The table cards used on the Dashboard, Guest feed, Search and Map.
//
//  FOOD PHOTOS live in Assets.xcassets (food_pizza, food_sushi, guest_pizza ...).
//  Which photo each category uses is decided in DiningOptions.swift (photoName).
//  If a photo is missing, a coloured tile with the food emoji is shown instead.
//

import SwiftUI
import UIKit

/// Shows the food photo for a category, or a coloured emoji tile if there is no photo.
/// Used for big pictures (guest feed, search) — fills its frame.
struct FoodPhoto: View {
    let category: TableCategory
    var emojiSize: CGFloat = 70
    /// true = use the bigger Guest feed photo (guest_pizza ...)
    var forGuestFeed: Bool = false

    /// Picks which photo name to use
    private var imageName: String {
        if forGuestFeed && UIImage(named: category.guestPhotoName) != nil {
            return category.guestPhotoName
        }
        return category.photoName
    }

    var body: some View {
        if UIImage(named: imageName) != nil {
            // Real photo from Assets.xcassets
            Image(imageName)
                .resizable()
                .scaledToFill()
                // The photo is bigger than its box (it's cut off with .clipped()),
                // but the hidden part would still catch taps and block buttons
                // like "Preview Table". So the photo ignores taps.
                .allowsHitTesting(false)
        } else {
            // No photo yet -> coloured tile with the emoji
            Rectangle()
                .fill(LinearGradient(colors: [AppColors.primary.opacity(0.35), AppColors.amber.opacity(0.25)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(Text(category.emoji).font(.system(size: emojiSize)))
        }
    }
}

/// Small square food picture for a table (cards, lists, map sheet).
struct TableThumbnail: View {
    let category: TableCategory
    var size: CGFloat = 76
    var cornerRadius: CGFloat = 14

    /// Each category gets its own warm colour
    private var tint: Color {
        switch category {
        case .pizza, .student: return AppColors.primary
        case .sushi, .asian: return AppColors.danger
        case .cafe, .coWork: return AppColors.amber
        case .tacos, .burgers: return AppColors.primaryDeep
        case .ramen: return AppColors.teal
        }
    }

    var body: some View {
        Group {
            if UIImage(named: category.photoName) != nil {
                // Real photo from Assets.xcassets
                Image(category.photoName)
                    .resizable()
                    .scaledToFill()
                    .allowsHitTesting(false)   // hidden overflow must not block taps
            } else {
                // No photo yet -> coloured tile with the emoji
                Rectangle()
                    .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.12)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Text(category.emoji).font(.system(size: size * 0.48)))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .accessibilityHidden(true)
    }
}

/// Dashboard row card (prototype Figure 6):
/// [🍕 TODAY] Taco Tuesday Meetup / Chili's Cafe • 400m away / ● 3/4 Seats Filled   [bookmark]
struct TableRowCard: View {
    let table: CommunityTable
    let distanceText: String
    var isSaved: Bool = false
    var onToggleSave: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            TableThumbnail(category: table.category)
                .overlay(alignment: .topLeading) {
                    Text(table.startTime.cardBadgeText)
                        .font(.system(size: 9, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppColors.onPrimary)
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(Capsule().fill(AppColors.amber))
                        .offset(x: -4, y: 6)
                }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .top) {
                    Text(table.title)
                        .font(AppFont.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    if let onToggleSave {
                        Button(action: onToggleSave) {
                            Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                                .foregroundStyle(isSaved ? AppColors.primary : AppColors.textSecondary)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(isSaved ? "Remove bookmark" : "Bookmark table")
                    }
                }
                Text("\(table.venueName) • \(distanceText)")
                    .font(AppFont.footnote)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)

                HStack {
                    BadgeView(text: table.isFull ? "Table Full" : table.seatSummary,
                              foreground: table.isFull ? AppColors.danger : AppColors.success,
                              background: table.isFull ? AppColors.dangerSoft : AppColors.successSoft,
                              showsDot: true)
                    Spacer()
                    // Host rating (proposal Feature 3: "host rating" on every feed item)
                    Label(String(format: "%.1f", table.hostRating), systemImage: "star.fill")
                        .font(AppFont.caption.weight(.semibold))
                        .foregroundStyle(AppColors.amber)
                        .labelStyle(.titleAndIcon)
                    if let perk = table.perk {
                        Text(perk)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    } else {
                        Text("Host: \(table.hostName.split(separator: " ").first.map(String.init) ?? table.hostName)")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .cardStyle(padding: 12)
        .contentShape(Rectangle())
        // VoiceOver reads the whole card as one sentence
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(table.title) at \(table.venueName), \(distanceText), \(table.startTime.friendlyDayTime), \(table.seatsFilled) of \(table.capacity) seats filled, hosted by \(table.hostName), rated \(String(format: "%.1f", table.hostRating)) stars")
        .accessibilityHint("Opens table details")
        // Bookmark is available from the VoiceOver actions rotor
        .accessibilityActions {
            if let onToggleSave {
                Button(isSaved ? "Remove bookmark" : "Bookmark table", action: onToggleSave)
            }
        }
    }
}

/// Big photo-style card used on the Guest feed (prototype Figure 5).
struct TableFeatureCard: View {
    let table: CommunityTable
    let distanceText: String
    var onPreview: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top "image" area
            ZStack(alignment: .bottomLeading) {
                FoodPhoto(category: table.category, emojiSize: 70, forGuestFeed: true)
                    .frame(height: 140)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 2) {
                    Text(table.venueName.uppercased())
                        .font(AppFont.overline)
                        .foregroundStyle(.white.opacity(0.85))
                    Text(table.title)
                        .font(AppFont.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                }
                .padding(12)
            }
            .overlay(alignment: .top) {
                HStack {
                    BadgeView(text: table.isFull ? "FULL" : "\(table.seatsLeft) OPEN SEAT\(table.seatsLeft == 1 ? "" : "S")",
                              foreground: .white, background: table.isFull ? AppColors.danger : AppColors.success,
                              showsDot: true)
                    Spacer()
                    BadgeView(text: distanceText, foreground: AppColors.textPrimary, background: AppColors.surface)
                }
                .padding(10)
            }
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: AppLayout.cardRadius, topTrailingRadius: AppLayout.cardRadius))

            // Host row + button
            VStack(spacing: 10) {
                HStack(spacing: 10) {
                    AvatarView(name: table.hostName, size: 36)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(table.hostName).font(AppFont.subheadline.weight(.semibold))
                            Text("★\(String(format: "%.1f", table.hostRating))")
                                .font(AppFont.caption)
                                .foregroundStyle(AppColors.amber)
                        }
                        Text(table.about)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColors.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    AvatarStack(names: table.attendeeNames, maxVisible: 2, size: 24)
                }
                Button(action: onPreview) {
                    Label("Preview Table", systemImage: "eye")
                }
                .buttonStyle(SoftButtonStyle(tint: AppColors.textPrimary))
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: AppLayout.cardRadius).fill(AppColors.surface))
        .overlay(RoundedRectangle(cornerRadius: AppLayout.cardRadius).stroke(AppColors.border.opacity(0.6), lineWidth: 1))
        // Tapping ANYWHERE on the card opens the preview (not only the small button)
        .contentShape(RoundedRectangle(cornerRadius: AppLayout.cardRadius))
        .onTapGesture { onPreview() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(table.title) at \(table.venueName), \(distanceText), \(table.seatsLeft) seats open")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Opens a preview of this table")
    }
}
