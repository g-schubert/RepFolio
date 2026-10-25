import Foundation
import SwiftData

/// Double progression: work inside a rep range; once every working set hits the top, add weight.
/// Three sessions at the same weight without more reps count as a stall → deload by ~10 %.
enum Progression {
    struct Suggestion {
        let weight: Double?
        let text: String
        let isIncrease: Bool
        var isDeload: Bool = false
    }

    /// Sessions at one weight without progress before a deload is suggested.
    static let stallSessions = 3

    static func oneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    /// - Parameter earlier: sets of the sessions before `lastSets`, newest first (for stall detection).
    static func suggest(lastSets: [SetEntry], earlier: [[SetEntry]] = [], repMin: Int, repMax: Int, increment: Double) -> Suggestion {
        guard !lastSets.isEmpty else {
            return Suggestion(weight: nil,
                              text: L("Erstes Mal: wähle ein Gewicht für ca. \(max(repMin, repMax - 2)) saubere Wiederholungen."),
                              isIncrease: false)
        }
        let top = lastSets.map(\.weightKg).max() ?? 0
        let working = lastSets.filter { $0.weightKg == top }
        if increment > 0, working.allSatisfy({ $0.reps >= repMax }) {
            return Suggestion(weight: top + increment,
                              text: L("Alle Sätze ≥ \(repMax) Wdh. geschafft – heute \(Fmt.kg(top + increment)) probieren!"),
                              isIncrease: true)
        }
        if let deload = deloadWeight(sessions: [lastSets] + earlier, top: top, repMax: repMax, increment: increment) {
            return Suggestion(weight: deload,
                              text: L("\(stallSessions) Trainings ohne Fortschritt bei \(Fmt.kg(top)) – Deload: heute \(Fmt.kg(deload)) mit sauberen \(repMax) Wdh., danach wieder steigern."),
                              isIncrease: false, isDeload: true)
        }
        if working.contains(where: { $0.reps < repMin }) {
            return Suggestion(weight: top,
                              text: L("Gewicht halten (\(Fmt.kg(top))) – Ziel: jeder Satz mind. \(repMin) Wdh."),
                              isIncrease: false)
        }
        return Suggestion(weight: top,
                          text: L("Gleiches Gewicht (\(Fmt.kg(top))) – versuche je Satz +1 Wdh. bis \(repMax)."),
                          isIncrease: false)
    }

    /// The last `stallSessions` sessions all used `top` and the working reps did not go up → ~90 %, on the increment grid.
    static func deloadWeight(sessions: [[SetEntry]], top: Double, repMax: Int, increment: Double) -> Double? {
        let recent = sessions.prefix(stallSessions)
        guard recent.count == stallSessions, top > 0,
              recent.allSatisfy({ ($0.map(\.weightKg).max() ?? 0) == top }) else { return nil }
        func workingReps(_ sets: [SetEntry]) -> Int { sets.filter { $0.weightKg == top }.reduce(0) { $0 + $1.reps } }
        guard let newest = recent.first, let oldest = recent.last,
              workingReps(newest) <= workingReps(oldest) else { return nil }
        let step = increment > 0 ? increment : 2.5
        let target = ((top * 0.9) / step).rounded(.down) * step
        return target > 0 && target < top ? target : nil
    }
}

struct SessionSets: Identifiable {
    let date: Date
    let sets: [SetEntry]
    var id: Date { date }
}

/// History look-ups for an exercise.
enum History {
    /// All completed sets of finished sessions, newest first.
    static func doneSets(for exerciseId: String, in context: ModelContext) -> [SetEntry] {
        let id = exerciseId
        let descriptor = FetchDescriptor<SetEntry>(
            predicate: #Predicate { $0.exerciseId == id && $0.isDone == true },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        return ((try? context.fetch(descriptor)) ?? []).filter(\.belongsToFinishedSession)
    }

    /// Sets grouped per session date, newest first.
    static func sessions(for exerciseId: String, in context: ModelContext) -> [SessionSets] {
        let sets = doneSets(for: exerciseId, in: context)
        let grouped = Dictionary(grouping: sets, by: { $0.date })
        return grouped.keys.sorted(by: >).map { d in
            SessionSets(date: d, sets: (grouped[d] ?? []).sorted { $0.order < $1.order })
        }
    }

    static func lastSessionSets(for exerciseId: String, in context: ModelContext) -> [SetEntry] {
        sessions(for: exerciseId, in: context).first?.sets ?? []
    }

    static func bestOneRepMax(for exerciseId: String, before date: Date, in context: ModelContext) -> Double {
        doneSets(for: exerciseId, in: context)
            .filter { $0.date < date }
            .map(\.estimatedOneRepMax)
            .max() ?? 0
    }
}

/// Creates a workout session from a plan day, pre-filled with suggested weights.
enum WorkoutFactory {
    @discardableResult
    static func start(day: PlanDay, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(startedAt: .now, planDayName: day.name)
        context.insert(session)
        for (idx, pe) in day.sortedExercises.enumerated() {
            addExercise(pe.exerciseId, sets: pe.sets, repMin: pe.repMin, repMax: pe.repMax,
                        order: idx, to: session, in: context)
        }
        try? context.save()
        return session
    }

    /// - Parameter done: true when logging a workout after the fact – the sets count as completed.
    static func addExercise(_ exerciseId: String, sets: Int, repMin: Int, repMax: Int,
                            order: Int, to session: WorkoutSession, done: Bool = false, in context: ModelContext) {
        let se = SessionExercise(exerciseId: exerciseId, order: order, repMin: repMin, repMax: repMax)
        context.insert(se)
        se.session = session

        let history = History.sessions(for: exerciseId, in: context)
        let last = history.first?.sets ?? []
        let ex = ExerciseCatalog.shared.exercise(exerciseId)
        let suggestion = Progression.suggest(lastSets: last, earlier: history.dropFirst().map(\.sets),
                                             repMin: repMin, repMax: repMax, increment: ex.increment)
        let weight = suggestion.weight ?? 0
        for s in 0..<max(1, sets) {
            let reps: Int
            if suggestion.isIncrease { reps = repMin }
            else if suggestion.isDeload { reps = repMax }
            else if s < last.count { reps = min(repMax, max(repMin, last[s].reps + 1)) }
            else { reps = repMin }
            let entry = SetEntry(exerciseId: exerciseId, date: session.startedAt, order: s, weightKg: weight, reps: reps, isDone: done)
            context.insert(entry)
            entry.sessionExercise = se
        }
    }

    /// Stored name of a workout without plan day (German key, translated via `PlanTemplates.display`).
    static let freeWorkoutName = "Freies Training"

    /// A finished workout entered afterwards (e.g. you forgot the phone), pre-filled like a normal start.
    static func logPast(day: PlanDay?, at start: Date, in context: ModelContext) -> WorkoutSession {
        let session = WorkoutSession(startedAt: start, planDayName: day?.name ?? freeWorkoutName)
        session.endedAt = start.addingTimeInterval(Double(day.map(estimatedMinutes) ?? 60) * 60)
        context.insert(session)
        for (idx, pe) in (day?.sortedExercises ?? []).enumerated() {
            addExercise(pe.exerciseId, sets: pe.sets, repMin: pe.repMin, repMax: pe.repMax,
                        order: idx, to: session, done: true, in: context)
        }
        try? context.save()
        return session
    }

    /// Replaces the exercise of a logged or running entry (keeps weights and reps).
    static func swap(_ sessionExercise: SessionExercise, to exerciseId: String, in context: ModelContext) {
        sessionExercise.exerciseId = exerciseId
        for set in sessionExercise.sets { set.exerciseId = exerciseId }
        try? context.save()
    }

    /// The next plan day in rotation after the last finished workout.
    static func nextDay(days: [PlanDay], finishedSessions: [WorkoutSession]) -> PlanDay? {
        let sortedDays = days.sorted { $0.order < $1.order }
        guard !sortedDays.isEmpty else { return nil }
        let names = sortedDays.map(\.name)
        guard let last = finishedSessions
            .sorted(by: { $0.startedAt > $1.startedAt })
            .first(where: { names.contains($0.planDayName) }),
              let idx = names.firstIndex(of: last.planDayName) else {
            return sortedDays.first
        }
        return sortedDays[(idx + 1) % sortedDays.count]
    }
}
