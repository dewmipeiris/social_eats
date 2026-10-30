//  CommonViews.swift

import SwiftUI
import UIKit

// card

struct CardModifier: ViewModifier {
    var padding: CGFloat = AppLayout.cardPadding

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.cardRadius)
                    .fill(AppColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.cardRadius)
                    .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 6, y: 2)
    }
}

extension View {
    func cardStyle(padding: CGFloat = AppLayout.cardPadding) -> some View {
        modifier(CardModifier(padding: padding))
    }

    func screenBackground() -> some View {
        background(AppColors.background.ignoresSafeArea())
    }
}

// chip

struct ChipView: View {
    let title: String
    var icon: String? = nil
    var isSelected: Bool = false
    var selectedColor: Color = AppColors.primary
    var action: (() -> Void)? = nil

    var body: some View {
        let label = HStack(spacing: 6) {
            if let icon {
                Text(icon)
                    .accessibilityHidden(true)
            }
            Text(title)
                .lineLimit(2)                
                .minimumScaleFactor(0.85)
            if isSelected && action != nil {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
                    .accessibilityHidden(true)
            }
        }
        .font(AppFont.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .frame(minHeight: 36)
        .foregroundStyle(isSelected ? AppColors.onPrimary : AppColors.textPrimary)
        .background(
            Capsule().fill(isSelected ? selectedColor : AppColors.surfaceMuted)
        )
        .overlay(
            Capsule().stroke(isSelected ? Color.clear : AppColors.border, lineWidth: 1)
        )

        if let action {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .accessibilityLabel(title)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        } else {
            label
                .accessibilityElement(children: .combine)
        }
    }
}

// chip grid

struct ChipGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .leading)],
                  alignment: .leading,
                  spacing: 8) {
            content
        }
    }
}

// badges

struct BadgeView: View {
    let text: String
    var foreground: Color = AppColors.success
    var background: Color = AppColors.successSoft
    var showsDot: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if showsDot {
                Circle()
                    .fill(foreground)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            }
            Text(text)
        }
        .font(AppFont.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(foreground)
        .background(Capsule().fill(background))
    }
}

struct OverlineText: View {
    let text: String
    var color: Color = AppColors.textSecondary

    var body: some View {
        Text(text.uppercased())
            .font(AppFont.overline)
            .tracking(0.8)
            .foregroundStyle(color)
            .accessibilityAddTraits(.isHeader)
    }
}

struct SectionHeader: View {
    let title: String
    var showsLiveDot: Bool = false
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if showsLiveDot {
                Circle()
                    .fill(AppColors.primary)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
            }
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 2) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.bold))
                    }
                    .font(AppFont.footnote.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                }
                .frame(minHeight: AppLayout.minTapTarget)
            }
        }
    }
}

// avatar

struct AvatarView: View {
    let name: String
    var size: CGFloat = 40
    var showsOnlineDot: Bool = false

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first }.map { String($0) }
        return letters.joined().uppercased()
    }
    
    private var tint: Color {
        let palette: [Color] = [AppColors.primary, AppColors.amber, AppColors.teal, AppColors.success]
        let index = Int(UInt(bitPattern: name.hashValueStable) % UInt(palette.count))
        return palette[index]
    }

    private var photoName: String {
        "avatar_" + (name.split(separator: " ").first.map { String($0).lowercased() } ?? "")
    }

    var body: some View {
        Circle()
            .fill(tint.opacity(0.18))
            .frame(width: size, height: size)
            .overlay(
                Group {
                    if UIImage(named: photoName) != nil {
                        Image(photoName)
                            .resizable()
                            .scaledToFill()
                            .clipShape(Circle())
                    } else {
                        Text(initials.isEmpty ? "?" : initials)
                            .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                            .foregroundStyle(tint)
                    }
                }
            )
            .overlay(alignment: .bottomTrailing) {
                if showsOnlineDot {
                    Circle()
                        .fill(AppColors.success)
                        .frame(width: size * 0.28, height: size * 0.28)
                        .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
                }
            }
            .accessibilityLabel(name)
    }
}

struct AvatarStack: View {
    let names: [String]
    var maxVisible: Int = 3
    var size: CGFloat = 28

    var body: some View {
        HStack(spacing: -size * 0.3) {
            ForEach(Array(names.prefix(maxVisible).enumerated()), id: \.offset) { _, name in
                AvatarView(name: name, size: size)
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
            }
            if names.count > maxVisible {
                Circle()
                    .fill(AppColors.surfaceMuted)
                    .frame(width: size, height: size)
                    .overlay(
                        Text("+\(names.count - maxVisible)")
                            .font(.system(size: size * 0.36, weight: .bold, design: .rounded))
                            .foregroundStyle(AppColors.textSecondary)
                    )
                    .overlay(Circle().stroke(AppColors.surface, lineWidth: 2))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(names.count) people: \(names.joined(separator: ", "))")
    }
}

struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .frame(width: 72, height: 72)
                .background(Circle().fill(AppColors.primarySoft))
                .accessibilityHidden(true)
            Text(title)
                .font(AppFont.headline)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)
            Text(message)
                .font(AppFont.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
            if let buttonTitle, let action {
                Button(buttonTitle, action: action)
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct ErrorBanner: View {
    let message: String
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppColors.danger)
                .accessibilityHidden(true)
            Text(message)
                .font(AppFont.footnote)
                .foregroundStyle(AppColors.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 32, height: 32)
                }
                .accessibilityLabel("Dismiss error")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.dangerSoft))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }
}

struct OfflineBanner: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "wifi.slash")
            Text("You're offline — showing saved tables & passes")
                .lineLimit(2)
        }
        .font(AppFont.footnote.weight(.semibold))
        .foregroundStyle(AppColors.amber)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(AppColors.amberSoft))
        .accessibilityElement(children: .combine)
    }
}

extension String {
    var hashValueStable: Int {
        var result = 5381
        for scalar in unicodeScalars {
            result = ((result << 5) &+ result) &+ Int(scalar.value)
        }
        return result
    }
}
