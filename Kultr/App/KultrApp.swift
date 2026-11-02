import AVFoundation
import SwiftUI
import UIKit

@main
struct KultrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            RootView()
                // A Kultr Studio style someone shared: shown first, used only if you choose to.
                .onOpenURL { url in
                    if let style = StudioStyle.read(url.absoluteString) { AppGraph.shared.ui.incomingStyle = style }
                }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        // Background tasks have to be registered before launch finishes.
        SyncManager.registerBackgroundTask()
        PlaybackLog.shared.start(application)
        _ = AppGraph.shared
        application.beginReceivingRemoteControlEvents()
        #if DEBUG
        ScreenshotDriver.start()
        #endif
        return true
    }
}
