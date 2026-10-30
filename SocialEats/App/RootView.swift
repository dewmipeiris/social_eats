//  RootView.swift

import SwiftUI

struct RootView: View {
    @EnvironmentObject private var container: AppContainer
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var tablesStore: TablesStore
    @Environment(\.scenePhase) private var scenePhase

    private var scannedPassWhenReady: Binding<ScannedPass?> {
        Binding(
            get: {
                session.phase == .main && !tablesStore.isLoading ? session.scannedPass : nil
            },
            set: { session.scannedPass = $0 }
        )
    }

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
        // Settings > Accessibility > Text Size slider (applies to every screen)
        .dynamicTypeSize(settings.textSize.dynamicTypeSize)
        .tint(AppColors.primary)
        .sheet(item: scannedPassWhenReady) { pass in
            CheckInResultView(scannedText: pass.id)
                .environmentObject(container.tablesStore)
        }
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
               container.biometrics.isSetUp {
                session.lockApp()
            }
        }
    }
}

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
