import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]

    @State private var exportURL: URL?
    @State private var csvURLs: [URL] = []
    @State private var importing = false
    @State private var pendingRestore: BackupService.Backup?
    @State private var message: String?
    @State private var confirmReset: Int?
    @State private var confirmWipe = false
    @State private var lastBackup = BackupService.latestBackupDate

    var body: some View {
        NavigationStack {
            if let profile = profiles.first {
                form(profile)
            } else {
                ProgressView()
            }
        }
    }

    private func form(_ profile: UserProfile) -> some View {
        @Bindable var profile = profile
        return Form {
            Section("Profil") {
                TextField("Name", text: $profile.name)
                Picker("Geschlecht", selection: Binding(get: { profile.sex }, set: { profile.sex = $0 })) {
                    ForEach(Sex.allCases) { Text($0.label).tag($0) }
                }
                Stepper("Geburtsjahr: \(String(profile.birthYear))", value: $profile.birthYear, in: 1940...2015)
                Stepper("Größe: \(Int(profile.heightCm)) cm", value: $profile.heightCm, in: 120...230, step: 1)
                NavigationLink {
                    BodyWeightListView()
                } label: {
                    LabeledContent("Körpergewicht", value: weights.last.map { Fmt.kg($0.kg) } ?? "–")
                }
            }

            Section {
                Picker("Gym pro Woche", selection: $profile.gymDaysPerWeek) {
                    Text("2×").tag(2)
                    Text("3×").tag(3)
                }
                Stepper("Läufe pro Woche: \(profile.runsPerWeekGoal)", value: $profile.runsPerWeekGoal, in: 0...7)
                Picker("Alltag", selection: $profile.activityFactor) {
                    Text("Sitzend (Büro)").tag(1.2)
                    Text("Leicht aktiv").tag(1.35)
                    Text("Aktiv (viel auf den Beinen)").tag(1.5)
                }
                Stepper("Satzpause: \(Fmt.duration(profile.defaultRestSeconds)) min", value: $profile.defaultRestSeconds, in: 30...300, step: 15)
            } header: {
                Text("Training & Ziele")
            } footer: {
                Text("„Alltag“ beschreibt deine Aktivität ohne Sport – Training und Läufe werden separat dazugerechnet.")
            }

            Section {
                Button("Plan 2× auf Standard zurücksetzen") { confirmReset = 2 }
                Button("Plan 3× auf Standard zurücksetzen") { confirmReset = 3 }
            } header: {
                Text("Trainingsplan")
            }

            Section {
                if let exp = ProvisioningInfo.expirationDate {
                    LabeledContent("Gültig bis", value: Fmt.dateTime(exp))
                } else {
                    LabeledContent("Gültig bis", value: L("unbekannt (Simulator)"))
                }
                Toggle("Erinnerung vor Ablauf", isOn: $profile.expiryRemindersEnabled)
                    .onChange(of: profile.expiryRemindersEnabled) { _, on in
                        Notifications.scheduleExpiryReminders(enabled: on)
                    }
            } header: {
                Text("App-Signatur (Xcode)")
            } footer: {
                Text("Mit einem kostenlosen Apple-Account läuft die App nach 7 Tagen ab. Einfach in Xcode erneut ▶︎ drücken – alle Daten bleiben erhalten, solange du die App nicht löschst.")
            }

            Section {
                LabeledContent("Letztes Auto-Backup", value: lastBackup.map(Fmt.dateTime) ?? L("noch keins"))
                Button("Jetzt sichern", systemImage: "externaldrive.badge.checkmark") {
                    BackupService.autoBackup(context)
                    lastBackup = BackupService.latestBackupDate
                    message = L("Backup gespeichert (Dateien-App › Auf meinem iPhone › RepFolio › Backups).")
                }
                Button("Backup exportieren …", systemImage: "square.and.arrow.up") {
                    do { exportURL = try BackupService.exportFile(context) }
                    catch { message = L("Export fehlgeschlagen: \(error.localizedDescription)") }
                }
                Button("Backup importieren …", systemImage: "square.and.arrow.down") { importing = true }
                Button("Als CSV exportieren …", systemImage: "tablecells") {
                    do { csvURLs = try BackupService.csvExport(context) }
                    catch { message = L("CSV-Export fehlgeschlagen: \(error.localizedDescription)") }
                }
            } header: {
                Text("Daten & Backup")
            } footer: {
                Text("Deine Daten liegen nur auf diesem iPhone. Exportiere ab und zu ein Backup in iCloud Drive oder auf deinen Mac – dann ist nichts verloren, selbst wenn die App gelöscht wird.")
            }

            Section {
                Button("Alle Daten löschen", role: .destructive) { confirmWipe = true }
            }

            Section("Über") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Link("Übungsbilder: Free Exercise DB (Public Domain)",
                     destination: URL(string: "https://github.com/yuhonas/free-exercise-db")!)
                Text("Kalorienwerte sind Schätzungen und ersetzen keine medizinische Beratung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Profil")
        .onChange(of: profile.gymDaysPerWeek) { _, _ in try? context.save() }
        .onDisappear { try? context.save() }
        .sheet(item: Binding(get: { exportURL.map { ShareItem(url: $0) } }, set: { exportURL = $0?.urls.first })) { item in
            ShareSheet(items: item.urls)
        }
        .sheet(item: Binding(get: { csvURLs.isEmpty ? nil : ShareItem(urls: csvURLs) }, set: { csvURLs = $0?.urls ?? [] })) { item in
            ShareSheet(items: item.urls)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                do {
                    pendingRestore = try BackupService.decode(Data(contentsOf: url))
                } catch {
                    message = L("Datei konnte nicht gelesen werden: \(error.localizedDescription)")
                }
            case .failure(let error):
                message = error.localizedDescription
            }
        }
        .alert("Backup wiederherstellen?", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button("Ersetzen", role: .destructive) {
                if let backup = pendingRestore {
                    BackupService.autoBackup(context) // safety copy of current state first
                    do {
                        try BackupService.restore(backup, into: context)
                        message = L("Backup wiederhergestellt: \(backup.sessions.count) Trainings, \(backup.runs.count) Läufe.")
                    } catch {
                        message = L("Wiederherstellen fehlgeschlagen: \(error.localizedDescription)")
                    }
                }
                pendingRestore = nil
            }
            Button("Abbrechen", role: .cancel) { pendingRestore = nil }
        } message: {
            Text("Alle aktuellen Daten werden durch das Backup vom \(pendingRestore.map { Fmt.dayLong($0.exportedAt) } ?? "") ersetzt.")
        }
        .alert("Plan zurücksetzen?", isPresented: Binding(get: { confirmReset != nil }, set: { if !$0 { confirmReset = nil } })) {
            Button("Zurücksetzen", role: .destructive) {
                if let f = confirmReset { PlanTemplates.reset(frequency: f, in: context) }
                confirmReset = nil
            }
            Button("Abbrechen", role: .cancel) { confirmReset = nil }
        } message: {
            Text("Deine Änderungen am Plan gehen verloren. Trainingsverlauf und Gewichte bleiben erhalten.")
        }
        .alert("Wirklich ALLE Daten löschen?", isPresented: $confirmWipe) {
            Button("Löschen", role: .destructive) {
                // Last safety net: never wipe if the backup could not be written.
                guard BackupService.autoBackup(context) else {
                    message = L("Backup fehlgeschlagen – es wurden keine Daten gelöscht.")
                    return
                }
                do {
                    try BackupService.deleteAll(context)
                } catch {
                    message = L("Löschen fehlgeschlagen: \(error.localizedDescription)")
                    return
                }
                let p = UserProfile()
                context.insert(p)
                PlanTemplates.seedIfNeeded(context)
                try? context.save()
            }
            Button("Abbrechen", role: .cancel) {}
        } message: {
            Text("Trainings, Läufe, Gewicht und Profil werden gelöscht. Ein letztes Backup wird vorher noch gespeichert.")
        }
        .alert("Hinweis", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(verbatim: message ?? "")
        }
    }
}

struct ShareItem: Identifiable {
    let urls: [URL]
    var id: String { urls.map(\.path).joined() }
    init(urls: [URL]) { self.urls = urls }
    init(url: URL) { self.urls = [url] }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
