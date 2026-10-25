import Foundation
import UIKit

/// A catalog exercise (bundled, read-only). Source: Free Exercise DB (public domain), curated + translated.
struct Exercise: Codable, Identifiable, Hashable {
    let id: String
    let nameDE: String
    let nameEN: String
    let group: String
    let equipment: String
    let primaryMuscles: [String]
    let secondaryMuscles: [String]
    /// Suggested weight jump in kg when progressing.
    let increment: Double
    let cues: [String]
    let instructionsEN: [String]
    let images: [String]

    private var isEnglish: Bool { AppLanguage.current == .en }

    /// Display name in the in-app language.
    var name: String { isEnglish ? nameEN : nameDE }
    var groupName: String { CatalogText.group(group) }
    var equipmentName: String { CatalogText.equipment(equipment) }
    var primaryMusclesText: String { primaryMuscles.map(Muscle.name).joined(separator: ", ") }
    var secondaryMusclesText: String { secondaryMuscles.map(Muscle.name).joined(separator: ", ") }
    /// Step-by-step instructions: curated German cues, or the original English instructions.
    var howTo: [String] { isEnglish ? instructionsEN : cues }

    static func placeholder(id: String) -> Exercise {
        Exercise(id: id, nameDE: id.replacingOccurrences(of: "_", with: " "), nameEN: id,
                 group: "Sonstiges", equipment: "–", primaryMuscles: [], secondaryMuscles: [],
                 increment: 2.5, cues: [], instructionsEN: [], images: [])
    }
}

struct ExerciseGroup: Identifiable {
    let group: String
    let items: [Exercise]
    var id: String { group }
}

enum Muscle {
    /// Localized display name for a Free Exercise DB muscle key.
    static func name(_ key: String) -> String {
        switch key {
        case "quadriceps": L("Quadrizeps (Oberschenkel vorne)")
        case "hamstrings": L("Beinbeuger (Oberschenkel hinten)")
        case "glutes": L("Gesäß")
        case "calves": L("Waden")
        case "chest": L("Brust")
        case "lats": L("Latissimus (breiter Rücken)")
        case "middle back": L("Mittlerer Rücken")
        case "lower back": L("Unterer Rücken")
        case "shoulders": L("Schultern")
        case "biceps": L("Bizeps")
        case "triceps": L("Trizeps")
        case "abdominals": L("Bauch")
        case "forearms": L("Unterarme")
        case "traps": L("Trapez (Nacken)")
        case "abductors": L("Abduktoren (Hüfte außen)")
        case "adductors": L("Adduktoren (Oberschenkel innen)")
        case "neck": L("Nacken")
        default: key.capitalized
        }
    }
}

/// Localized names for the German group/equipment values stored in exercises.json.
/// The German values stay the internal keys (grouping, symbols).
enum CatalogText {
    static func group(_ key: String) -> String {
        switch key {
        case "Beine": L("Beine")
        case "Waden": L("Waden")
        case "Brust": L("Brust")
        case "Rücken": L("Rücken")
        case "Schultern": L("Schultern")
        case "Arme": L("Arme")
        case "Bauch": L("Bauch")
        case "Sonstiges": L("Sonstiges")
        default: key
        }
    }

    static func equipment(_ key: String) -> String {
        switch key {
        case "Kabelzug": L("Kabelzug")
        case "Kurzhantel": L("Kurzhantel")
        case "Körpergewicht": L("Körpergewicht")
        case "Langhantel": L("Langhantel")
        case "Maschine": L("Maschine")
        case "Sonstiges": L("Sonstiges")
        default: key
        }
    }
}

final class ExerciseCatalog {
    static let shared = ExerciseCatalog()

    let all: [Exercise]
    private let byId: [String: Exercise]

    /// Display order of muscle groups in the library.
    static let groupOrder = ["Beine", "Waden", "Brust", "Rücken", "Schultern", "Arme", "Bauch", "Sonstiges"]

    static let groupSymbols: [String: String] = [
        "Beine": "figure.strengthtraining.functional",
        "Waden": "figure.step.training",
        "Brust": "figure.strengthtraining.traditional",
        "Rücken": "figure.rower",
        "Schultern": "figure.arms.open",
        "Arme": "dumbbell",
        "Bauch": "figure.core.training",
        "Sonstiges": "questionmark.circle",
    ]

    static let equipmentSymbols: [String: String] = [
        "Maschine": "gearshape.2",
        "Kabelzug": "cable.connector",
        "Kurzhantel": "dumbbell",
        "Langhantel": "figure.strengthtraining.traditional",
        "Körpergewicht": "figure.core.training",
        "Sonstiges": "ellipsis.circle",
    ]

    private init() {
        guard let url = Bundle.main.url(forResource: "exercises", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Exercise].self, from: data) else {
            assertionFailure("exercises.json missing or invalid")
            all = []
            byId = [:]
            return
        }
        all = list
        byId = Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0) })
    }

    func exercise(_ id: String) -> Exercise {
        byId[id] ?? .placeholder(id: id)
    }

    /// Equipment values in the catalog, most common first.
    var equipmentKinds: [String] {
        let counts = Dictionary(grouping: all, by: \.equipment).mapValues(\.count)
        return counts.keys.sorted { (counts[$0] ?? 0, $1) > (counts[$1] ?? 0, $0) }
    }

    func grouped(matching search: String = "", equipment: String? = nil) -> [ExerciseGroup] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let pool = equipment.map { eq in all.filter { $0.equipment == eq } } ?? all
        let filtered = q.isEmpty ? pool : pool.filter {
            $0.nameDE.lowercased().contains(q) || $0.nameEN.lowercased().contains(q)
                || $0.group.lowercased().contains(q) || $0.equipment.lowercased().contains(q)
                || $0.groupName.lowercased().contains(q) || $0.equipmentName.lowercased().contains(q)
        }
        let dict = Dictionary(grouping: filtered, by: \.group)
        return Self.groupOrder.compactMap { g in
            guard let items = dict[g], !items.isEmpty else { return nil }
            return ExerciseGroup(group: g, items: items.sorted { $0.name < $1.name })
        }
    }

    /// Exercises that train the same primary muscle – used for "Übung tauschen".
    func alternatives(for id: String) -> [Exercise] {
        let ex = exercise(id)
        return all.filter { $0.id != id && ($0.group == ex.group || !Set($0.primaryMuscles).isDisjoint(with: ex.primaryMuscles)) }
            .sorted { $0.name < $1.name }
    }
}

/// Loads bundled exercise photos (cached).
enum ExerciseImageStore {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(named name: String) -> UIImage? {
        if let cached = cache.object(forKey: name as NSString) { return cached }
        guard let path = Bundle.main.path(forResource: name, ofType: "jpg"),
              let img = UIImage(contentsOfFile: path) else { return nil }
        cache.setObject(img, forKey: name as NSString)
        return img
    }
}
