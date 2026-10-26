//
//  AppLockView.swift
//  SocialEats
//
//  Shown when "Face ID Protection" is on and the app is opened again.
//  Face ID runs automatically; the user can retry or sign out.
//

import SwiftUI

struct AppLockView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var errorMessage: String?
    @State private var isChecking = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            AppLogoBadge(size: 72)
            Text("SocialEats is locked")
                .font(AppFont.title)
                .foregroundStyle(AppColors.textPrimary)
            Text("Your tables, chats and passes are protected with \(session.biometricKind.title).")
                .font(AppFont.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)

            if let errorMessage {
                ErrorBanner(message: errorMessage)
            }

            Button {
                Task { await unlock() }
            } label: {
                Label("Unlock with \(session.biometricKind.title)", systemImage: session.biometricKind.systemImage)
                    .font(AppFont.headline)
                    .foregroundStyle(AppColors.faceIDButtonText)
                    .frame(maxWidth: .infinity, minHeight: AppLayout.buttonHeight)
                    .background(RoundedRectangle(cornerRadius: AppLayout.buttonRadius).fill(AppColors.faceIDButton))
            }
            .disabled(isChecking)

            Spacer()

            Button("Sign out") { session.signOut() }
                .font(AppFont.subheadline)
                .foregroundStyle(AppColors.danger)
                .frame(minHeight: AppLayout.minTapTarget)
        }
        .padding(24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .task { await unlock() }      // try straight away
    }

    private func unlock() async {
        isChecking = true
        errorMessage = await session.unlockWithBiometrics()
        isChecking = false
    }
}
