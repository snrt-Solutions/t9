import SwiftUI
import UIKit

@main
struct AeSMSApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
                .preferredColorScheme(.light)
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        if appState.phase == .mailbox {
                            appState.startPushIfNeeded()
                            if appState.unlocked {
                                Task { await appState.fetchInboxQuiet() }
                            }
                        }
                    case .background:
                        if appState.phase == .mailbox {
                            appState.lockMailbox()
                            appState.stopPush()
                            appState.syncAppBadge()
                        }
                    case .inactive:
                        break
                    @unknown default:
                        break
                    }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushService.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        // Simulator / unsigned builds: SSE still delivers while the app is foregrounded.
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        PushService.handleRemoteNotification(userInfo: userInfo, fetchCompletionHandler: completionHandler)
    }
}
