import SwiftUI
import SwiftData

struct RootView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppState.self) private var appState
    @Environment(RestTimer.self) private var restTimer
    @Query private var profiles: [UserProfile]

    @State private var showOnboarding = false
    @State private var offerRestore = false

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem { Label("Übersicht", systemImage: "chart.bar.xaxis") }
                .tag(AppTab.dashboard)
            TrainingView()
                .tabItem { Label("Training", systemImage: "dumbbell.fill") }
                .tag(AppTab.training)
            RunListView()
                .tabItem { Label("Laufen", systemImage: "figure.run") }
                .tag(AppTab.running)
            ExerciseLibraryView()
                .tabItem { Label("Übungen", systemImage: "list.bullet.rectangle.portrait") }
                .tag(AppTab.exercises)
            SettingsView()
                .tabItem { Label("Profil", systemImage: "person.crop.circle") }
                .tag(AppTab.settings)
        }
        .fullScreenCover(item: $appState.activeSession) { session in
            ActiveWorkoutView(session: session)
                .environment(appState)
                .environment(restTimer)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView()
                .interactiveDismissDisabled()
        }
        .alert("Backup gefunden", isPresented: $offerRestore) {
            Button("Wiederherstellen") { restoreLatest() }
            Button("Neu starten", role: .cancel) { showOnboarding = true }
        } message: {
            Text("Die Datenbank ist leer, aber es gibt ein automatisches Backup vom \(BackupService.latestBackupDate.map(Fmt.dayLong) ?? "–"). Daten daraus wiederherstellen?")
        }
        .task { bootstrap() }
        .onChange(of: profiles.first?.persistentModelID) { _, _ in
            // e.g. after "Alle Daten löschen" a fresh profile appears → run onboarding again
            if let p = profiles.first, !p.onboardingDone, !offerRestore { showOnboarding = true }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                BackupService.autoBackup(context)
            }
            if phase == .active {
                Notifications.scheduleExpiryReminders(enabled: profiles.first?.expiryRemindersEnabled ?? true)
            }
        }
    }

    private func bootstrap() {
        let profile: UserProfile
        if let existing = profiles.first {
            profile = existing
        } else {
            profile = UserProfile()
            context.insert(profile)
        }
        PlanTemplates.seedIfNeeded(context)
        try? context.save()

        if !profile.onboardingDone {
            let hasBackup = FileManager.default.fileExists(atPath: BackupService.latestURL.path)
            if hasBackup { offerRestore = true } else { showOnboarding = true }
        }
        Notifications.requestAuthorization()
        Notifications.scheduleExpiryReminders(enabled: profile.expiryRemindersEnabled)
    }

    private func restoreLatest() {
        do {
            let data = try Data(contentsOf: BackupService.latestURL)
            try BackupService.restore(BackupService.decode(data), into: context)
        } catch {
            showOnboarding = true
        }
    }
}
