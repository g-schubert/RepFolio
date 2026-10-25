import SwiftUI
import SwiftData
import UserNotifications

@main
struct RepFolioApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var appState = AppState()
    @State private var restTimer = RestTimer()

    /// The SwiftData store lives in the app container (Application Support). Re-running the app from Xcode
    /// installs *over* the existing app, so this store – and all your data – survives the weekly re-install.
    let container: ModelContainer = {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration("RepFolio", schema: schema)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState)
                .environment(restTimer)
                .modifier(AppPreferencesModifier())
        }
        .modelContainer(container)
    }
}

/// Shows notifications (rest timer, expiry) even while the app is in the foreground.
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}

enum AppTab: Hashable {
    case dashboard, training, running, exercises, settings
}

@Observable
final class AppState {
    var selectedTab: AppTab = .dashboard
    var activeSession: WorkoutSession?
}
