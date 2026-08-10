import SwiftUI

@main
struct JimanmanApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    WechatLoginBridge.handleOpenURL(url)
                }
                .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                    WechatLoginBridge.handleUniversalLink(activity)
                }
        }
    }
}
