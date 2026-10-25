import Foundation
import SwiftData

/// Default training plans. Machine-heavy so they work in almost any commercial gym.
/// Every exercise can be swapped / edited in the app afterwards.
enum PlanTemplates {
    struct Item { let id: String; let sets: Int; let min: Int; let max: Int }
    struct Day { let name: String; let subtitle: String; let items: [Item] }

    private static func i(_ id: String, _ sets: Int, _ min: Int, _ max: Int) -> Item {
        Item(id: id, sets: sets, min: min, max: max)
    }

    /// 2× pro Woche: Ganzkörper A/B (jeder Muskel 2× pro Woche).
    static let twoDays: [Day] = [
        Day(name: "Ganzkörper A", subtitle: "Beinpresse · Brust · Latzug", items: [
            i("Leg_Press", 3, 8, 12),
            i("Leverage_Chest_Press", 3, 8, 12),
            i("Wide-Grip_Lat_Pulldown", 3, 8, 12),
            i("Lying_Leg_Curls", 3, 10, 12),
            i("Leverage_Shoulder_Press", 3, 8, 12),
            i("Triceps_Pushdown_-_Rope_Attachment", 2, 10, 15),
            i("Ab_Crunch_Machine", 2, 12, 15),
        ]),
        Day(name: "Ganzkörper B", subtitle: "Hack Squat · Rudern · Schrägbank", items: [
            i("Hack_Squat", 3, 8, 12),
            i("Romanian_Deadlift", 3, 8, 10),
            i("Leverage_Incline_Chest_Press", 3, 8, 12),
            i("Seated_Cable_Rows", 3, 8, 12),
            i("Cable_Seated_Lateral_Raise", 3, 12, 15),
            i("Machine_Bicep_Curl", 2, 10, 12),
            i("Seated_Calf_Raise", 3, 12, 15),
        ]),
    ]

    /// 3× pro Woche: Oberkörper / Unterkörper / Ganzkörper.
    static let threeDays: [Day] = [
        Day(name: "Oberkörper", subtitle: "Drücken & Ziehen", items: [
            i("Leverage_Chest_Press", 3, 6, 10),
            i("Wide-Grip_Lat_Pulldown", 3, 8, 12),
            i("Incline_Dumbbell_Press", 3, 8, 12),
            i("Leverage_Iso_Row", 3, 8, 12),
            i("Side_Lateral_Raise", 3, 12, 15),
            i("Triceps_Pushdown_-_Rope_Attachment", 2, 10, 15),
            i("Machine_Bicep_Curl", 2, 10, 12),
        ]),
        Day(name: "Unterkörper", subtitle: "Beine, Gesäß & Bauch", items: [
            i("Leg_Press", 4, 8, 12),
            i("Romanian_Deadlift", 3, 8, 10),
            i("Leg_Extensions", 3, 10, 15),
            i("Seated_Leg_Curl", 3, 10, 15),
            i("Standing_Calf_Raises", 3, 10, 15),
            i("Hanging_Leg_Raise", 3, 10, 15),
        ]),
        Day(name: "Ganzkörper", subtitle: "Alles einmal, andere Winkel", items: [
            i("Hack_Squat", 3, 8, 12),
            i("Dumbbell_Bench_Press", 3, 8, 12),
            i("Close-Grip_Front_Lat_Pulldown", 3, 8, 12),
            i("Barbell_Hip_Thrust", 3, 8, 12),
            i("Reverse_Machine_Flyes", 3, 12, 15),
            i("Face_Pull", 2, 12, 15),
            i("Cable_Crunch", 3, 12, 15),
        ]),
    ]

    /// Inserts both plan variants (2× and 3×) if none exist yet.
    static func seedIfNeeded(_ context: ModelContext) {
        let count = (try? context.fetchCount(FetchDescriptor<PlanDay>())) ?? 0
        guard count == 0 else { return }
        insert(twoDays, frequency: 2, into: context)
        insert(threeDays, frequency: 3, into: context)
        try? context.save()
    }

    /// Deletes the plan for one frequency and re-creates the default.
    static func reset(frequency: Int, in context: ModelContext) {
        let f = frequency
        let existing = (try? context.fetch(FetchDescriptor<PlanDay>(predicate: #Predicate { $0.frequency == f }))) ?? []
        existing.forEach { context.delete($0) }
        insert(frequency == 2 ? twoDays : threeDays, frequency: frequency, into: context)
        try? context.save()
    }

    /// Plan names are stored in German (they also link sessions to plan days), so the default
    /// names/subtitles are translated for display only. Names the user typed are shown as-is.
    static func display(_ stored: String) -> String {
        switch stored {
        case "Ganzkörper A": L("Ganzkörper A")
        case "Ganzkörper B": L("Ganzkörper B")
        case "Ganzkörper": L("Ganzkörper")
        case "Oberkörper": L("Oberkörper")
        case "Unterkörper": L("Unterkörper")
        case "Beinpresse · Brust · Latzug": L("Beinpresse · Brust · Latzug")
        case "Hack Squat · Rudern · Schrägbank": L("Hack Squat · Rudern · Schrägbank")
        case "Drücken & Ziehen": L("Drücken & Ziehen")
        case "Beine, Gesäß & Bauch": L("Beine, Gesäß & Bauch")
        case "Alles einmal, andere Winkel": L("Alles einmal, andere Winkel")
        default: stored
        }
    }

    private static func insert(_ days: [Day], frequency: Int, into context: ModelContext) {
        for (dIdx, d) in days.enumerated() {
            let day = PlanDay(name: d.name, subtitle: d.subtitle, frequency: frequency, order: dIdx)
            context.insert(day)
            for (eIdx, it) in d.items.enumerated() {
                let pe = PlanExercise(exerciseId: it.id, order: eIdx, sets: it.sets, repMin: it.min, repMax: it.max)
                context.insert(pe)
                pe.day = day
            }
        }
    }
}

extension PlanDay {
    var displayName: String { PlanTemplates.display(name) }
    var displaySubtitle: String { PlanTemplates.display(subtitle) }
}

extension WorkoutSession {
    var displayName: String { PlanTemplates.display(planDayName) }
}
