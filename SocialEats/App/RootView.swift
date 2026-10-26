//
//  RootView.swift
//  SocialEats
//
//  Shows the right screen for the current AppPhase and applies the
//  Light / Dark / System theme chosen in Settings to the WHOLE app.
//

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            switch session.phase {
            case .loading:
                LaunchView()
            case .onboarding:
                OnboardingView()
            case .tasteProfile:
                ProfileSetupView(mode: .onboarding)
            case .signIn:
                SignInView(container: container)
            case .guest:
                GuestBrowseView()
            case .locked where session.currentUser == nil:
                AppLockView()
            case .main, .locked:
                // Keep the main app alive underneath so navigation isn't lost
                AdaptiveMainView()
                if session.phase == .locked {
                    AppLockView()
                        .transition(.opacity)
                        .zIndex(1)
                }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: session.phase)
        .preferredColorScheme(settings.theme.colorScheme)
        // Settings > Accessibility > Larger Text
        .dynamicTypeSize(settings.largerTextEnabled
                          ? DynamicTypeSize.xxLarge ... DynamicTypeSize.accessibility5
                          : DynamicTypeSize.xSmall ... DynamicTypeSize.accessibility5)
        .tint(AppColors.primary)
        .task {
            await session.bootstrap()
            container.location.requestPermission()
        }
        .onChange(of: session.phase) { _, newPhase in
            if newPhase == .main || newPhase == .guest {
                container.tablesStore.start()
            }
            if newPhase == .main {
                Task { _ = await container.notifications.requestPermission() }
            }
        }
        // Lock again with Face ID when the app goes to the background
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background,
               session.phase == .main,
               settings.faceIDProtectionEnabled,
               container.biometrics.availableKind != .none {
                session.lockApp()
            }
        }
    }
}

/// Simple splash while we check who is signed in.
struct LaunchView: View {
    var body: some View {
        VStack(spacing: 16) {
            AppLogoBadge(size: 72)
            Text("SocialEats")
                .font(AppFont.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            ProgressView()
                .tint(AppColors.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .screenBackground()
        .accessibilityElement(children: .combine)
        .accessibilityLabel("SocialEats is loading")
    }
}
