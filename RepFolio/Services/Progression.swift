import Foundation
import SwiftData

/// Double progression: work inside a rep range; once every working set hits the top, add weight.
enum Progression {
    struct Suggestion {
        let weight: Double?
        let text: String
        let isIncrease: Bool
    }

    static func oneRepMax(weight: Double, reps: Int) -> Double {
        guard reps > 0, weight > 0 else { return 0 }
        if reps == 1 { return weight }
        return weight * (1 + Double(reps) / 30.0)
    }

    static func suggest(lastSets: [SetEntry], repMin: Int, repMax: Int, increment: Double) -> Suggestion {
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
        if working.contains(where: { $0.reps < repMin }) {
            return Suggestion(weight: top,
                              text: L("Gewicht halten (\(Fmt.kg(top))) – Ziel: jeder Satz mind. \(repMin) Wdh."),
                              isIncrease: false)
        }
        return Suggestion(weight: top,
                          text: L("Gleiches Gewicht (\(Fmt.kg(top))) – versuche je Satz +1 Wdh. bis \(repMax)."),
                          isIncrease: false)
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

    static func addExercise(_ exerciseId: String, sets: Int, repMin: Int, repMax: Int,
                            order: Int, to session: WorkoutSession, in context: ModelContext) {
        let se = SessionExercise(exerciseId: exerciseId, order: order, repMin: repMin, repMax: repMax)
        context.insert(se)
        se.session = session

        let last = History.lastSessionSets(for: exerciseId, in: context)
        let ex = ExerciseCatalog.shared.exercise(exerciseId)
        let suggestion = Progression.suggest(lastSets: last, repMin: repMin, repMax: repMax, increment: ex.increment)
        let weight = suggestion.weight ?? 0
        for s in 0..<max(1, sets) {
            let reps: Int
            if suggestion.isIncrease { reps = repMin }
            else if s < last.count { reps = min(repMax, max(repMin, last[s].reps + 1)) }
            else { reps = repMin }
            let entry = SetEntry(exerciseId: exerciseId, date: session.startedAt, order: s, weightKg: weight, reps: reps)
            context.insert(entry)
            entry.sessionExercise = se
        }
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
