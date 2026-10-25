import Foundation
import UserNotifications

/// Reads the expiry date of the provisioning profile embedded by Xcode.
/// With a free Apple ID ("Personal Team") apps expire after 7 days and must be re-run from Xcode.
enum ProvisioningInfo {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>") else { return nil }
        let plistText = String(text[start.lowerBound..<end.upperBound])
        guard let plistData = plistText.data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    static var daysLeft: Int? {
        guard let exp = expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: exp).day
    }

    static var hoursLeft: Double? {
        expirationDate.map { $0.timeIntervalSinceNow / 3600 }
    }
}

enum Notifications {
    static let expiryIds = ["expiry-24h", "expiry-3h"]
    static let restId = "rest-timer"

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    /// Schedules reminders 24 h and 3 h before the app signature expires.
    static func scheduleExpiryReminders(enabled: Bool) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: expiryIds)
        guard enabled, let exp = ProvisioningInfo.expirationDate else { return }

        let plan: [(String, TimeInterval, String)] = [
            ("expiry-24h", 24 * 3600, L("RepFolio läuft morgen ab")),
            ("expiry-3h", 3 * 3600, L("RepFolio läuft in 3 Stunden ab")),
        ]
        for (id, before, title) in plan {
            let fire = exp.addingTimeInterval(-before)
            guard fire > .now else { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = L("iPhone an den Mac anschließen und in Xcode auf ▶︎ drücken. Deine Daten bleiben erhalten.")
            content.sound = .default
            let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fire)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    static func scheduleRestEnd(after seconds: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [restId])
        let content = UNMutableNotificationContent()
        content.title = L("Pause vorbei 💪")
        content.body = L("Weiter geht's mit dem nächsten Satz.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, seconds)), repeats: false)
        center.add(UNNotificationRequest(identifier: restId, content: content, trigger: trigger))
    }

    static func cancelRest() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [restId])
    }
}
