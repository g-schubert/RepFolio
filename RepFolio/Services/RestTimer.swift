import Foundation
import Observation
import UIKit

/// Rest timer between sets. Survives the app going to background via a local notification.
@Observable
final class RestTimer {
    private(set) var endDate: Date?
    private(set) var total: Int = 90

    var isRunning: Bool { endDate.map { $0 > .now } ?? false }

    func remaining(at date: Date = .now) -> Int {
        guard let end = endDate else { return 0 }
        return max(0, Int(end.timeIntervalSince(date).rounded(.up)))
    }

    func start(seconds: Int) {
        total = seconds
        endDate = Date.now.addingTimeInterval(TimeInterval(seconds))
        Notifications.scheduleRestEnd(after: seconds)
    }

    func add(_ seconds: Int) {
        guard let end = endDate else { return }
        let newEnd = end.addingTimeInterval(TimeInterval(seconds))
        guard newEnd > .now else { stop(); return }
        endDate = newEnd
        total = max(total + seconds, 1)
        Notifications.scheduleRestEnd(after: Int(newEnd.timeIntervalSinceNow))
    }

    func stop() {
        endDate = nil
        Notifications.cancelRest()
    }

    /// Called by the UI tick when the countdown reaches zero while visible.
    func finishIfNeeded() {
        if let end = endDate, end <= .now {
            endDate = nil
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }
}
