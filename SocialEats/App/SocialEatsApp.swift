//  SocialEatsApp.swift

import SwiftUI
import UIKit
import FirebaseCore
import FirebaseAuth
import GoogleSignIn

@main
struct SocialEatsApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        let container = appDelegate.container

        return WindowGroup {
            RootView()
                .environmentObject(container)
                .environmentObject(container.session)
                .environmentObject(container.settings)
                .environmentObject(container.tablesStore)
                .environmentObject(container.location)
                .environmentObject(container.network)
                .onOpenURL { url in
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

final class AppDelegate: NSObject, UIApplicationDelegate {

    lazy var container: AppContainer = AppContainer.live()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // 1. Build the services now (sets the notification delegate + geofence monitor)
        _ = self.container

        // 2. Needed so Firebase can verify the phone silently with a push (real devices)
        application.registerForRemoteNotifications()
        return true
    }

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
