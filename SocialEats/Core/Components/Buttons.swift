//  Buttons.swift

import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    var isEnabled: Bool = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline)
            .foregroundStyle(AppColors.onPrimary)
            .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeight)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.buttonRadius)
                    .fill(AppColors.primary.opacity(isEnabled ? 1 : 0.45))
            )
            .shadow(color: AppColors.primary.opacity(isEnabled ? 0.25 : 0), radius: 8, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.headline)
            .foregroundStyle(AppColors.textPrimary)
            .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeight - 4)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.buttonRadius)
                    .fill(AppColors.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.buttonRadius)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SoftButtonStyle: ButtonStyle {
    var tint: Color = AppColors.primary

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(AppFont.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: AppLayout.minTapTarget)
            .background(
                RoundedRectangle(cornerRadius: AppLayout.buttonRadius)
                    .fill(AppColors.surfaceMuted)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppLayout.buttonRadius)
                    .stroke(AppColors.border, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct LoadingButton: View {
    let title: String
    var systemImage: String? = nil
    var isLoading: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .tint(AppColors.onPrimary)
                } else {
                    if let systemImage {
                        Image(systemName: systemImage)
                    }
                    Text(title)
                }
            }
        }
        .buttonStyle(PrimaryButtonStyle(isEnabled: isEnabled && !isLoading))
        .disabled(!isEnabled || isLoading)
        .accessibilityLabel(isLoading ? "\(title), loading" : title)
    }
}

struct CircleIconButton: View {
    let systemImage: String
    let accessibilityText: String
    var showsBadge: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .frame(width: AppLayout.minTapTarget, height: AppLayout.minTapTarget)
                .overlay(alignment: .topTrailing) {
                    // Little red dot for unread notifications
                    if showsBadge {
                        Circle()
                            .fill(AppColors.primary)
                            .frame(width: 9, height: 9)
                            .offset(x: -9, y: 9)
                    }
                }
        }
        .accessibilityLabel(accessibilityText)
    }
}
