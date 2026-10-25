import SwiftUI
import SwiftData

struct TrainingView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query(sort: \PlanDay.order) private var allDays: [PlanDay]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var finished: [WorkoutSession]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var open: [WorkoutSession]

    private var frequency: Int { profiles.first?.gymDaysPerWeek ?? 3 }
    private var days: [PlanDay] { allDays.filter { $0.frequency == frequency } }
    private var nextDay: PlanDay? { WorkoutFactory.nextDay(days: days, finishedSessions: finished) }

    var body: some View {
        NavigationStack {
            List {
                if let running = open.first {
                    Section {
                        Button {
                            appState.activeSession = running
                        } label: {
                            HStack {
                                Image(systemName: "play.circle.fill").font(.title).foregroundStyle(.green)
                                VStack(alignment: .leading) {
                                    Text("Training läuft: \(running.displayName)").font(.headline)
                                    Text("Gestartet \(running.startedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened).locale(Fmt.locale))) – tippen zum Fortsetzen")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section {
                    if let profile = profiles.first {
                        Picker("Trainingstage", selection: Binding(
                            get: { profile.gymDaysPerWeek },
                            set: { profile.gymDaysPerWeek = $0; try? context.save() })) {
                            Text("2× pro Woche").tag(2)
                            Text("3× pro Woche").tag(3)
                        }
                        .pickerStyle(.segmented)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                    }
                } footer: {
                    Text(frequency == 2
                         ? "Ganzkörper A/B im Wechsel: jeder Muskel wird 2× pro Woche trainiert – ideal mit 1–2 Läufen dazu."
                         : "Oberkörper / Unterkörper / Ganzkörper: jeder Muskel 2× pro Woche, Beine nicht direkt vor dem Laufen.")
                }

                if let next = nextDay {
                    Section("Als Nächstes") {
                        NextWorkoutCard(day: next) { start(next) }
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                }

                Section("Dein Plan") {
                    ForEach(days) { day in
                        NavigationLink(value: day) {
                            PlanDayRow(day: day, isNext: day.id == nextDay?.id)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        WorkoutHistoryView()
                    } label: {
                        Label("Trainingsverlauf (\(finished.count))", systemImage: "clock.arrow.circlepath")
                    }
                    ForEach(finished.prefix(3)) { s in
                        NavigationLink {
                            WorkoutDetailView(session: s)
                        } label: {
                            WorkoutRow(session: s)
                        }
                    }
                } header: {
                    Text("Verlauf")
                }
            }
            .navigationTitle("Training")
            .navigationDestination(for: PlanDay.self) { day in
                PlanDayDetailView(day: day)
            }
        }
    }

    private func start(_ day: PlanDay) {
        if let running = open.first {
            appState.activeSession = running
        } else {
            appState.activeSession = WorkoutFactory.start(day: day, in: context)
        }
    }
}

struct NextWorkoutCard: View {
    let day: PlanDay
    let onStart: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.displayName).font(.title2.weight(.bold))
                    Text(day.displaySubtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(day.exercises.count) Übungen\n~\(estimatedMinutes(day)) min")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.trailing)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(day.sortedExercises) { pe in
                        ExerciseThumb(exerciseId: pe.exerciseId, size: 54)
                    }
                }
            }
            Button(action: onStart) {
                Label("Training starten", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

func estimatedMinutes(_ day: PlanDay) -> Int {
    // ~2.5 min per set incl. rest + 5 min warm-up
    let sets = day.exercises.reduce(0) { $0 + $1.sets }
    return Int(Double(sets) * 2.5) + 5
}

struct PlanDayRow: View {
    let day: PlanDay
    let isNext: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(verbatim: "\(day.order + 1)")
                .font(.headline)
                .frame(width: 32, height: 32)
                .background(isNext ? Color.accentColor : Color.secondary.opacity(0.2), in: Circle())
                .foregroundStyle(isNext ? .white : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.displayName).font(.headline)
                Text(day.sortedExercises.map { ExerciseCatalog.shared.exercise($0.exerciseId).name }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
    }
}

struct WorkoutRow: View {
    let session: WorkoutSession

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.displayName).font(.subheadline.weight(.semibold))
            Text("\(Fmt.day(session.startedAt)) · \(Fmt.minutes(session.durationMinutes)) · \(session.doneSets.count) Sätze · \(Fmt.num(session.volume / 1000, digits: 1)) t")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
