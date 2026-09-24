import AVFoundation
import SwiftUI
import UIKit

@main
struct KultrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Background tasks have to be registered before launch finishes.
        SyncManager.registerBackgroundTask()
        _ = AppGraph.shared
        application.beginReceivingRemoteControlEvents()
        #if DEBUG
        ScreenshotDriver.start()
        #endif
        return true
    }
}
