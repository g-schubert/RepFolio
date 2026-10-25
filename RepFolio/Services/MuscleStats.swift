import SwiftUI

/// Per-muscle numbers for the body map: weekly volume and recovery.
enum MuscleStats {
    /// Working sets per muscle: a primary muscle counts the full set, a secondary one half.
    static func sets(in sessions: [WorkoutSession]) -> [String: Double] {
        var result: [String: Double] = [:]
        let catalog = ExerciseCatalog.shared
        for set in sessions.flatMap(\.doneSets) {
            let ex = catalog.exercise(set.exerciseId)
            for m in ex.primaryMuscles { result[m, default: 0] += 1 }
            for m in ex.secondaryMuscles { result[m, default: 0] += 0.5 }
        }
        return result
    }

    enum Recovery {
        /// Trained within the last 48 h.
        case recovering
        /// Trained 2–7 days ago – ready for the next session.
        case ready
        /// Not trained for more than a week (or never).
        case untrained

        var color: Color {
            switch self {
            case .recovering: .chartRun
            case .ready: .chartBase
            case .untrained: Color.secondary.opacity(0.22)
            }
        }
    }

    /// Recovery state per muscle, based on the last session that hit it as primary muscle.
    static func recovery(sessions: [WorkoutSession], now: Date = .now) -> [String: Recovery] {
        var last: [String: Date] = [:]
        let catalog = ExerciseCatalog.shared
        for s in sessions {
            for set in s.doneSets {
                for m in catalog.exercise(set.exerciseId).primaryMuscles where (last[m] ?? .distantPast) < s.startedAt {
                    last[m] = s.startedAt
                }
            }
        }
        var result: [String: Recovery] = [:]
        for muscle in BodyGeometry.muscles {
            guard let date = last[muscle] else { result[muscle] = .untrained; continue }
            let hours = now.timeIntervalSince(date) / 3600
            result[muscle] = hours < 48 ? .recovering : hours < 24 * 7 ? .ready : .untrained
        }
        return result
    }

    /// Weekly sets → tint. 10 sets (lower end of the 10–20 guideline) is full color.
    static func volumeColor(_ sets: Double) -> Color {
        guard sets > 0 else { return Color.secondary.opacity(0.22) }
        return Color.chartGym.opacity(0.3 + 0.7 * min(1, sets / 10))
    }
}
