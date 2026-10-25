import SwiftUI
import SwiftData

struct Record: Identifiable {
    let name: String
    let oneRepMax: Double
    var id: String { name }
}

struct WorkoutSummaryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]
    @Query private var weights: [BodyWeightEntry]
    @Bindable var session: WorkoutSession
    @State private var records: [Record] = []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.seal.fill").font(.system(size: 56)).foregroundStyle(.green)
                        Text("Training gespeichert").font(.title2.weight(.bold))
                        Text(session.displayName).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
                Section {
                    LabeledContent("Dauer", value: Fmt.minutes(session.durationMinutes))
                    LabeledContent("Sätze", value: String(session.doneSets.count))
                    LabeledContent("Volumen", value: "\(Fmt.num(session.volume, digits: 0)) kg")
                    LabeledContent("Kalorien (geschätzt)",
                                   value: Fmt.kcal(Energy.gymKcal(minutes: session.durationMinutes,
                                                                 weightKg: Energy.weight(on: session.startedAt, entries: weights))))
                }
                if !records.isEmpty {
                    Section("Neue Rekorde 🏆") {
                        ForEach(records) { record in
                            LabeledContent(record.name, value: "e1RM \(Fmt.kg(record.oneRepMax))")
                        }
                    }
                }
                Section("Notiz") {
                    TextField("Wie lief's? (optional)", text: $session.notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("Zusammenfassung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        try? context.save()
                        BackupService.autoBackup(context)
                        dismiss()
                    }
                }
            }
            .task { computeRecords() }
        }
    }

    private func computeRecords() {
        var result: [Record] = []
        for se in session.sortedExercises {
            let best = se.sets.filter(\.isDone).map(\.estimatedOneRepMax).max() ?? 0
            let before = History.bestOneRepMax(for: se.exerciseId, before: session.startedAt, in: context)
            if before > 0, best > before {
                result.append(Record(name: ExerciseCatalog.shared.exercise(se.exerciseId).name, oneRepMax: best))
            }
        }
        records = result
    }
}

struct WorkoutHistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]

    var body: some View {
        List {
            if sessions.isEmpty {
                ContentUnavailableView("Noch keine Trainings", systemImage: "dumbbell",
                                       description: Text("Starte dein erstes Training im Tab „Training“."))
            }
            ForEach(sessions) { s in
                NavigationLink {
                    WorkoutDetailView(session: s)
                } label: {
                    WorkoutRow(session: s)
                }
            }
            .onDelete { idx in
                idx.map { sessions[$0] }.forEach { context.delete($0) }
                try? context.save()
            }
        }
        .navigationTitle("Verlauf")
    }
}

struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Zeit") {
                DatePicker("Start", selection: Binding(get: { session.startedAt }, set: { new in
                    let duration = session.durationMinutes
                    session.startedAt = new
                    session.endedAt = new.addingTimeInterval(duration * 60)
                    for se in session.exercises { for st in se.sets { st.date = new } }
                    try? context.save()
                }))
                Stepper("Dauer: \(Fmt.minutes(session.durationMinutes))", value: Binding(
                    get: { Int(session.durationMinutes.rounded()) },
                    set: { session.endedAt = session.startedAt.addingTimeInterval(Double($0) * 60); try? context.save() }
                ), in: 5...300, step: 5)
            }
            ForEach(session.sortedExercises) { se in
                Section(ExerciseCatalog.shared.exercise(se.exerciseId).name) {
                    ForEach(se.sortedSets.filter(\.isDone)) { st in
                        HStack {
                            Text("Satz \(st.order + 1)").foregroundStyle(.secondary)
                            Spacer()
                            Text("\(Fmt.kg(st.weightKg)) × \(st.reps)").monospacedDigit()
                        }
                    }
                }
            }
            if !session.notes.isEmpty {
                Section("Notiz") { Text(session.notes) }
            }
            Section {
                Button("Training löschen", role: .destructive) { confirmDelete = true }
            }
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Training wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
        }
    }
}
