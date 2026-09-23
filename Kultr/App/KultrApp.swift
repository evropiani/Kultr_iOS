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
        return true
    }
}

/**
 * The navigation bar is hidden on every screen (Kultr draws its own), which
 * would also switch off the swipe-from-the-edge back gesture. Keep it.
 */
extension UINavigationController: UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        viewControllers.count > 1
    }
}
