import Foundation
import SwiftData

// MARK: - Profile

enum Sex: String, CaseIterable, Identifiable, Codable {
    case male, female
    var id: String { rawValue }
    var label: String { self == .male ? L("Männlich") : L("Weiblich") }
}

/// Single-row table holding the user's personal settings.
@Model
final class UserProfile {
    var name: String = ""
    var sexRaw: String = Sex.male.rawValue
    var birthYear: Int = 1998
    var heightCm: Double = 180
    /// 2 or 3 gym sessions per week – decides which plan is shown.
    var gymDaysPerWeek: Int = 3
    var runsPerWeekGoal: Int = 2
    /// Multiplier on BMR for everyday (non-exercise) activity.
    var activityFactor: Double = 1.2
    var defaultRestSeconds: Int = 90
    var onboardingDone: Bool = false
    var expiryRemindersEnabled: Bool = true

    init() {}

    var sex: Sex {
        get { Sex(rawValue: sexRaw) ?? .male }
        set { sexRaw = newValue.rawValue }
    }

    var age: Int {
        let year = Calendar.current.component(.year, from: .now)
        return max(10, year - birthYear)
    }
}

@Model
final class BodyWeightEntry {
    var date: Date = Date.now
    var kg: Double = 75

    init(date: Date = .now, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

// MARK: - Plan

@Model
final class PlanDay {
    var name: String = ""
    var subtitle: String = ""
    /// Which weekly frequency this day belongs to (2 or 3).
    var frequency: Int = 3
    var order: Int = 0
    @Relationship(deleteRule: .cascade, inverse: \PlanExercise.day)
    var exercises: [PlanExercise] = []

    init(name: String, subtitle: String, frequency: Int, order: Int) {
        self.name = name
        self.subtitle = subtitle
        self.frequency = frequency
        self.order = order
    }

    var sortedExercises: [PlanExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

@Model
final class PlanExercise {
    var exerciseId: String = ""
    var order: Int = 0
    var sets: Int = 3
    var repMin: Int = 8
    var repMax: Int = 12
    var day: PlanDay?

    init(exerciseId: String, order: Int, sets: Int, repMin: Int, repMax: Int) {
        self.exerciseId = exerciseId
        self.order = order
        self.sets = sets
        self.repMin = repMin
        self.repMax = repMax
    }
}

// MARK: - Workouts

@Model
final class WorkoutSession {
    var startedAt: Date = Date.now
    var endedAt: Date?
    var planDayName: String = ""
    var notes: String = ""
    @Relationship(deleteRule: .cascade, inverse: \SessionExercise.session)
    var exercises: [SessionExercise] = []

    init(startedAt: Date = .now, planDayName: String) {
        self.startedAt = startedAt
        self.planDayName = planDayName
    }

    var isFinished: Bool { endedAt != nil }

    var sortedExercises: [SessionExercise] {
        exercises.sorted { $0.order < $1.order }
    }

    var durationMinutes: Double {
        let end = endedAt ?? .now
        return max(0, end.timeIntervalSince(startedAt) / 60)
    }

    var doneSets: [SetEntry] {
        exercises.flatMap { $0.sets }.filter { $0.isDone }
    }

    /// Total volume (kg × reps) of all completed sets.
    var volume: Double {
        doneSets.reduce(0) { $0 + $1.weightKg * Double($1.reps) }
    }
}

@Model
final class SessionExercise {
    var exerciseId: String = ""
    var order: Int = 0
    var repMin: Int = 8
    var repMax: Int = 12
    var session: WorkoutSession?
    @Relationship(deleteRule: .cascade, inverse: \SetEntry.sessionExercise)
    var sets: [SetEntry] = []

    init(exerciseId: String, order: Int, repMin: Int, repMax: Int) {
        self.exerciseId = exerciseId
        self.order = order
        self.repMin = repMin
        self.repMax = repMax
    }

    var sortedSets: [SetEntry] {
        sets.sorted { $0.order < $1.order }
    }
}

@Model
final class SetEntry {
    var exerciseId: String = ""
    /// Copy of the session start date – makes history queries cheap.
    var date: Date = Date.now
    var order: Int = 0
    var weightKg: Double = 0
    var reps: Int = 0
    var isDone: Bool = false
    var sessionExercise: SessionExercise?

    init(exerciseId: String, date: Date, order: Int, weightKg: Double, reps: Int, isDone: Bool = false) {
        self.exerciseId = exerciseId
        self.date = date
        self.order = order
        self.weightKg = weightKg
        self.reps = reps
        self.isDone = isDone
    }

    /// Estimated one-rep max (Epley).
    var estimatedOneRepMax: Double {
        Progression.oneRepMax(weight: weightKg, reps: reps)
    }

    var belongsToFinishedSession: Bool {
        sessionExercise?.session?.endedAt != nil
    }
}

// MARK: - Running

enum RunType: String, CaseIterable, Identifiable, Codable {
    case easy, tempo, interval, long, race, treadmill
    var id: String { rawValue }
    var label: String {
        switch self {
        case .easy: L("Locker")
        case .tempo: L("Tempo")
        case .interval: L("Intervalle")
        case .long: L("Langer Lauf")
        case .race: L("Wettkampf")
        case .treadmill: L("Laufband")
        }
    }
    var symbol: String {
        switch self {
        case .easy: "figure.run"
        case .tempo: "speedometer"
        case .interval: "timer"
        case .long: "road.lanes"
        case .race: "flag.checkered"
        case .treadmill: "figure.run.treadmill"
        }
    }
}

@Model
final class RunEntry {
    var date: Date = Date.now
    var distanceKm: Double = 5
    var durationSeconds: Int = 1800
    var typeRaw: String = RunType.easy.rawValue
    /// 1 (hart/schlecht) … 5 (super)
    var feeling: Int = 3
    var avgHeartRate: Int?
    var notes: String = ""

    init(date: Date = .now, distanceKm: Double, durationSeconds: Int, type: RunType = .easy) {
        self.date = date
        self.distanceKm = distanceKm
        self.durationSeconds = durationSeconds
        self.typeRaw = type.rawValue
    }

    var type: RunType {
        get { RunType(rawValue: typeRaw) ?? .easy }
        set { typeRaw = newValue.rawValue }
    }

    /// Seconds per km.
    var paceSecondsPerKm: Double {
        distanceKm > 0 ? Double(durationSeconds) / distanceKm : 0
    }

    var speedKmh: Double {
        durationSeconds > 0 ? distanceKm / (Double(durationSeconds) / 3600) : 0
    }
}

// MARK: - Per-exercise personal notes

/// Personal notes for an exercise: machine settings ("Sitz 4") and an own photo of the machine in your gym.
@Model
final class ExerciseNote {
    var exerciseId: String = ""
    var machineSettings: String = ""
    @Attribute(.externalStorage) var customPhoto: Data?

    init(exerciseId: String) {
        self.exerciseId = exerciseId
    }
}

enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        UserProfile.self, BodyWeightEntry.self, PlanDay.self, PlanExercise.self,
        WorkoutSession.self, SessionExercise.self, SetEntry.self, RunEntry.self, ExerciseNote.self,
    ]
}
