import Foundation
import SwiftData

/// JSON backup of *all* user data.
///
/// Why: With a free Apple developer account the app must be re-installed from Xcode every 7 days.
/// Re-installing over the existing app keeps all data (same bundle id → same container), but if the app is
/// ever deleted or the bundle id changes, the database is gone. So RepFolio additionally writes automatic
/// backups to `Documents/Backups` (visible in the Files app under "Auf meinem iPhone › RepFolio"),
/// and you can export a backup anywhere (iCloud Drive, AirDrop to your Mac, …) and import it again.
enum BackupService {
    static let currentVersion = 1

    struct Backup: Codable {
        var version: Int
        var exportedAt: Date
        var profile: Profile?
        var bodyWeights: [Weight]
        var planDays: [Day]
        var sessions: [Session]
        var runs: [Run]
        var notes: [Note]
    }

    struct Profile: Codable {
        var name: String; var sexRaw: String; var birthYear: Int; var heightCm: Double
        var gymDaysPerWeek: Int; var runsPerWeekGoal: Int; var activityFactor: Double
        var defaultRestSeconds: Int; var onboardingDone: Bool; var expiryRemindersEnabled: Bool
    }
    struct Weight: Codable { var date: Date; var kg: Double }
    struct Day: Codable { var name: String; var subtitle: String; var frequency: Int; var order: Int; var exercises: [DayExercise] }
    struct DayExercise: Codable { var exerciseId: String; var order: Int; var sets: Int; var repMin: Int; var repMax: Int }
    struct Session: Codable { var startedAt: Date; var endedAt: Date?; var planDayName: String; var notes: String; var exercises: [SessionEx] }
    struct SessionEx: Codable { var exerciseId: String; var order: Int; var repMin: Int; var repMax: Int; var sets: [SetDTO] }
    struct SetDTO: Codable { var order: Int; var weightKg: Double; var reps: Int; var isDone: Bool }
    struct Run: Codable {
        var date: Date; var distanceKm: Double; var durationSeconds: Int; var typeRaw: String
        var feeling: Int; var avgHeartRate: Int?; var notes: String
    }
    struct Note: Codable { var exerciseId: String; var machineSettings: String; var customPhoto: Data? }

    // MARK: Locations

    static var backupDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let dir = docs.appendingPathComponent("Backups", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var latestURL: URL { backupDirectory.appendingPathComponent("RepFolio-latest.json") }

    static var latestBackupDate: Date? {
        (try? FileManager.default.attributesOfItem(atPath: latestURL.path))?[.modificationDate] as? Date
    }

    // MARK: Export

    static func makeBackup(_ context: ModelContext) throws -> Backup {
        let profile = try context.fetch(FetchDescriptor<UserProfile>()).first.map {
            Profile(name: $0.name, sexRaw: $0.sexRaw, birthYear: $0.birthYear, heightCm: $0.heightCm,
                    gymDaysPerWeek: $0.gymDaysPerWeek, runsPerWeekGoal: $0.runsPerWeekGoal,
                    activityFactor: $0.activityFactor, defaultRestSeconds: $0.defaultRestSeconds,
                    onboardingDone: $0.onboardingDone, expiryRemindersEnabled: $0.expiryRemindersEnabled)
        }
        let weights = try context.fetch(FetchDescriptor<BodyWeightEntry>()).map { Weight(date: $0.date, kg: $0.kg) }
        let days = try context.fetch(FetchDescriptor<PlanDay>()).map { d in
            Day(name: d.name, subtitle: d.subtitle, frequency: d.frequency, order: d.order,
                exercises: d.sortedExercises.map {
                    DayExercise(exerciseId: $0.exerciseId, order: $0.order, sets: $0.sets, repMin: $0.repMin, repMax: $0.repMax)
                })
        }
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>()).map { s in
            Session(startedAt: s.startedAt, endedAt: s.endedAt, planDayName: s.planDayName, notes: s.notes,
                    exercises: s.sortedExercises.map { e in
                        SessionEx(exerciseId: e.exerciseId, order: e.order, repMin: e.repMin, repMax: e.repMax,
                                  sets: e.sortedSets.map { SetDTO(order: $0.order, weightKg: $0.weightKg, reps: $0.reps, isDone: $0.isDone) })
                    })
        }
        let runs = try context.fetch(FetchDescriptor<RunEntry>()).map {
            Run(date: $0.date, distanceKm: $0.distanceKm, durationSeconds: $0.durationSeconds, typeRaw: $0.typeRaw,
                feeling: $0.feeling, avgHeartRate: $0.avgHeartRate, notes: $0.notes)
        }
        let notes = try context.fetch(FetchDescriptor<ExerciseNote>()).map {
            Note(exerciseId: $0.exerciseId, machineSettings: $0.machineSettings, customPhoto: $0.customPhoto)
        }
        return Backup(version: currentVersion, exportedAt: .now, profile: profile, bodyWeights: weights,
                      planDays: days, sessions: sessions, runs: runs, notes: notes)
    }

    static func encode(_ backup: Backup) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try enc.encode(backup)
    }

    /// Writes `RepFolio-latest.json` plus one file per day; keeps the 14 newest daily files.
    @discardableResult
    static func autoBackup(_ context: ModelContext) -> Bool {
        do {
            try context.save()
            // Never overwrite a good backup with an empty, not-yet-set-up database.
            guard let profile = try context.fetch(FetchDescriptor<UserProfile>()).first, profile.onboardingDone else {
                return false
            }
            let data = try encode(makeBackup(context))
            try data.write(to: latestURL, options: .atomic)
            let stamp = dayStamp
            try data.write(to: backupDirectory.appendingPathComponent("RepFolio-\(stamp).json"), options: .atomic)
            pruneDailyBackups(keep: 14)
            return true
        } catch {
            print("Auto-backup failed: \(error)")
            return false
        }
    }

    /// Writes a fresh export to a temp file (for the share sheet).
    static func exportFile(_ context: ModelContext) throws -> URL {
        let data = try encode(makeBackup(context))
        let stamp = dayStamp
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RepFolio-Backup-\(stamp).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private static func pruneDailyBackups(keep: Int) {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil) else { return }
        let daily = files.filter { $0.lastPathComponent.hasPrefix("RepFolio-20") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        daily.dropFirst(keep).forEach { try? fm.removeItem(at: $0) }
    }

    // MARK: Import

    static func decode(_ data: Data) throws -> Backup {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try dec.decode(Backup.self, from: data)
    }

    /// Replaces ALL data with the backup's content.
    static func restore(_ backup: Backup, into context: ModelContext) throws {
        try wipe(context)

        let p = UserProfile()
        if let b = backup.profile {
            p.name = b.name; p.sexRaw = b.sexRaw; p.birthYear = b.birthYear; p.heightCm = b.heightCm
            p.gymDaysPerWeek = b.gymDaysPerWeek; p.runsPerWeekGoal = b.runsPerWeekGoal
            p.activityFactor = b.activityFactor; p.defaultRestSeconds = b.defaultRestSeconds
            p.onboardingDone = b.onboardingDone; p.expiryRemindersEnabled = b.expiryRemindersEnabled
        }
        context.insert(p)

        for w in backup.bodyWeights { context.insert(BodyWeightEntry(date: w.date, kg: w.kg)) }

        for d in backup.planDays {
            let day = PlanDay(name: d.name, subtitle: d.subtitle, frequency: d.frequency, order: d.order)
            context.insert(day)
            for e in d.exercises {
                let pe = PlanExercise(exerciseId: e.exerciseId, order: e.order, sets: e.sets, repMin: e.repMin, repMax: e.repMax)
                context.insert(pe)
                pe.day = day
            }
        }

        for s in backup.sessions {
            let session = WorkoutSession(startedAt: s.startedAt, planDayName: s.planDayName)
            session.endedAt = s.endedAt
            session.notes = s.notes
            context.insert(session)
            for e in s.exercises {
                let se = SessionExercise(exerciseId: e.exerciseId, order: e.order, repMin: e.repMin, repMax: e.repMax)
                context.insert(se)
                se.session = session
                for st in e.sets {
                    let entry = SetEntry(exerciseId: e.exerciseId, date: s.startedAt, order: st.order,
                                         weightKg: st.weightKg, reps: st.reps, isDone: st.isDone)
                    context.insert(entry)
                    entry.sessionExercise = se
                }
            }
        }

        for r in backup.runs {
            let run = RunEntry(date: r.date, distanceKm: r.distanceKm, durationSeconds: r.durationSeconds)
            run.typeRaw = r.typeRaw; run.feeling = r.feeling; run.avgHeartRate = r.avgHeartRate; run.notes = r.notes
            context.insert(run)
        }

        for n in backup.notes {
            let note = ExerciseNote(exerciseId: n.exerciseId)
            note.machineSettings = n.machineSettings
            note.customPhoto = n.customPhoto
            context.insert(note)
        }

        try context.save()
        PlanTemplates.seedIfNeeded(context)
    }

    // MARK: CSV

    static func csvExport(_ context: ModelContext) throws -> [URL] {
        let tmp = FileManager.default.temporaryDirectory
        var setsCSV = "datum;plan;uebung_id;uebung;satz;gewicht_kg;wdh;e1rm_kg\n"
        let sessions = try context.fetch(FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.startedAt)]))
        let iso = ISO8601DateFormatter()
        for s in sessions where s.isFinished {
            for e in s.sortedExercises {
                let name = ExerciseCatalog.shared.exercise(e.exerciseId).nameDE
                for st in e.sortedSets where st.isDone {
                    setsCSV += "\(iso.string(from: s.startedAt));\(s.planDayName);\(e.exerciseId);\(name);\(st.order + 1);\(st.weightKg);\(st.reps);\(String(format: "%.1f", st.estimatedOneRepMax))\n"
                }
            }
        }
        var runsCSV = "datum;typ;distanz_km;dauer_s;pace_s_pro_km;puls;gefuehl;notiz\n"
        for r in try context.fetch(FetchDescriptor<RunEntry>(sortBy: [SortDescriptor(\.date)])) {
            let note = r.notes.replacingOccurrences(of: ";", with: ",").replacingOccurrences(of: "\n", with: " ")
            runsCSV += "\(iso.string(from: r.date));\(r.type.label);\(r.distanceKm);\(r.durationSeconds);\(Int(r.paceSecondsPerKm));\(r.avgHeartRate.map(String.init) ?? "");\(r.feeling);\(note)\n"
        }
        let u1 = tmp.appendingPathComponent("RepFolio-Saetze.csv")
        let u2 = tmp.appendingPathComponent("RepFolio-Laeufe.csv")
        try setsCSV.write(to: u1, atomically: true, encoding: .utf8)
        try runsCSV.write(to: u2, atomically: true, encoding: .utf8)
        return [u1, u2]
    }

    // MARK: Wipe

    static func deleteAll(_ context: ModelContext) throws {
        try wipe(context)
    }

    /// Deletes every object one by one (more reliable than batch deletes with relationships).
    private static func wipe(_ context: ModelContext) throws {
        try deleteEach(SetEntry.self, context)
        try deleteEach(SessionExercise.self, context)
        try deleteEach(WorkoutSession.self, context)
        try deleteEach(PlanExercise.self, context)
        try deleteEach(PlanDay.self, context)
        try deleteEach(RunEntry.self, context)
        try deleteEach(BodyWeightEntry.self, context)
        try deleteEach(ExerciseNote.self, context)
        try deleteEach(UserProfile.self, context)
        try context.save()
    }

    private static func deleteEach<T: PersistentModel>(_ type: T.Type, _ context: ModelContext) throws {
        for object in try context.fetch(FetchDescriptor<T>()) {
            context.delete(object)
        }
    }

    private static var dayStamp: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: .now)
    }
}
