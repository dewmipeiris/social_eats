//
//  SocialEatsApp.swift
//  SocialEats
//
//  "Connect over food. Never eat alone."
//  App entry point. The AppContainer is created in the AppDelegate (at launch)
//  and shared with every screen through the SwiftUI environment.
//

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@main
struct SocialEatsApp: App {

    /// UIKit app delegate — owns the AppContainer (see below)
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // All services and shared state (created once, at launch, by the delegate)
        let container = appDelegate.container

        return WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.session)
                .environmentObject(container.settings)
                .environmentObject(container.tablesStore)
                .environmentObject(container.location)
                .environmentObject(container.network)
                // Google Sign-In and Phone Auth reCAPTCHA come back through URLs
                .onOpenURL { url in
                    // A pass QR scanned with the iPhone Camera app (socialeats://checkin?t=...)
                    if url.scheme == "socialeats" {
                        container.session.scannedPass = ScannedPass(id: url.absoluteString)
                        return
                    }
                    if FirebaseApp.app() != nil, Auth.auth().canHandle(url) { return }
                    _ = GIDSignIn.sharedInstance.handle(url)
                }
        }
    }
}

/// Classic UIKit delegate.
///
/// Why the container lives HERE and not in the SwiftUI App:
/// when the app is closed and iOS launches it because the user tapped a
/// notification, entered a venue geofence, or because the user moved,
/// those events arrive before any SwiftUI screen exists. Creating everything
/// in didFinishLaunching means the notification delegate and the location
/// monitor are ready in time.
final class AppDelegate: NSObject, UIApplicationDelegate {

    /// All services and shared state for the whole app (created once)
    lazy var container: AppContainer = AppContainer.live()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 1. Build the services now (sets the notification delegate + geofence monitor)
        _ = self.container

        // 2. Needed so Firebase can verify the phone silently with a push (real devices)
        application.registerForRemoteNotifications()
        return true
    }

    /// Gives the APNs token to Firebase Auth (silent phone verification).
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard FirebaseApp.app() != nil else { return }
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }

    func application(_ application: UIApplication,
                     didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if FirebaseApp.app() != nil, Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.newData)
    }

    func application(_ app: UIApplication, open url: URL,
                     options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        if FirebaseApp.app() != nil, Auth.auth().canHandle(url) { return true }
        return GIDSignIn.sharedInstance.handle(url)
    }
}
