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
    @Query private var profiles: [UserProfile]
    @Query(sort: \PlanDay.order) private var allDays: [PlanDay]

    @State private var choosingDay = false
    @State private var logged: WorkoutSession?

    private var planDays: [PlanDay] {
        let frequency = profiles.first?.gymDaysPerWeek ?? 3
        return allDays.filter { $0.frequency == frequency }
    }

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
                .swipeActions(edge: .trailing) {
                    Button("Löschen", systemImage: "trash", role: .destructive) {
                        context.delete(s)
                        try? context.save()
                        BackupService.autoBackup(context)
                    }
                }
            }
        }
        .navigationTitle("Verlauf")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { choosingDay = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Training nachtragen")
            }
        }
        .confirmationDialog("Training nachtragen", isPresented: $choosingDay, titleVisibility: .visible) {
            ForEach(planDays) { day in
                Button(day.displayName) { log(day) }
            }
            Button("Freies Training") { log(nil) }
        } message: {
            Text("Für ein Training ohne Handy: Es wird mit den Vorschlägen vorausgefüllt – Datum, Gewichte und Wiederholungen kannst du danach anpassen.")
        }
        .navigationDestination(item: $logged) { session in
            WorkoutDetailView(session: session)
        }
    }

    private func log(_ day: PlanDay?) {
        // Default: today, one hour ago, on the full hour.
        let hourAgo = Date.now.addingTimeInterval(-3600)
        let start = Cal.shared.dateInterval(of: .hour, for: hourAgo)?.start ?? hourAgo
        logged = WorkoutFactory.logPast(day: day, at: start, in: context)
    }
}

/// A finished workout – every value can be corrected afterwards: date, duration, sets, exercises, note.
struct WorkoutDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: WorkoutSession
    @State private var confirmDelete = false
    @State private var adding = false
    @State private var swapping: SessionExercise?
    @State private var detailExercise: Exercise?

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
                Section {
                    HStack {
                        Text("Satz").frame(width: 44, alignment: .leading)
                        Text("kg").frame(maxWidth: .infinity)
                        Text("Wdh.").frame(maxWidth: .infinity)
                    }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(se.sortedSets.filter(\.isDone)) { st in
                        EditableSetRow(set: st)
                            .swipeActions(edge: .trailing) {
                                Button("Löschen", systemImage: "trash", role: .destructive) { deleteSet(st, of: se) }
                            }
                    }
                    Button {
                        addSet(to: se)
                    } label: {
                        Label("Satz hinzufügen", systemImage: "plus")
                    }
                } header: {
                    exerciseHeader(se)
                }
            }
            Section {
                Button {
                    adding = true
                } label: {
                    Label("Übung hinzufügen", systemImage: "plus.circle.fill")
                }
            }
            Section("Notiz") {
                TextField("Wie lief's? (optional)", text: $session.notes, axis: .vertical)
                    .lineLimit(2...5)
            }
            Section {
                Button("Training löschen", role: .destructive) { confirmDelete = true }
            } footer: {
                Text("Änderungen werden sofort gespeichert. Rekorde und Vorschläge rechnen mit den korrigierten Werten.")
            }
        }
        .navigationTitle(session.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Fertig") { hideKeyboard() }
            }
        }
        .onDisappear {
            try? context.save()
            BackupService.autoBackup(context)
        }
        .confirmationDialog("Training wirklich löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Löschen", role: .destructive) {
                context.delete(session)
                try? context.save()
                dismiss()
            }
        }
        .sheet(isPresented: $adding) {
            ExercisePickerView(title: "Übung hinzufügen") { ex in
                WorkoutFactory.addExercise(ex.id, sets: 3, repMin: 8, repMax: 12,
                                           order: (session.exercises.map(\.order).max() ?? -1) + 1,
                                           to: session, done: true, in: context)
                try? context.save()
            }
        }
        .sheet(item: $swapping) { se in
            ExercisePickerView(title: "Übung tauschen", suggestions: ExerciseCatalog.shared.alternatives(for: se.exerciseId)) { ex in
                WorkoutFactory.swap(se, to: ex.id, in: context)
            }
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack { ExerciseDetailView(exercise: ex, isSheet: true) }
        }
    }

    private func exerciseHeader(_ se: SessionExercise) -> some View {
        let ex = ExerciseCatalog.shared.exercise(se.exerciseId)
        return HStack {
            Text(ex.name)
            Spacer()
            Menu {
                Button("Ausführung ansehen", systemImage: "info.circle") { detailExercise = ex }
                Button("Übung tauschen", systemImage: "arrow.triangle.2.circlepath") { swapping = se }
                Button("Übung entfernen", systemImage: "trash", role: .destructive) {
                    context.delete(se)
                    try? context.save()
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.body)
                    .frame(width: 44, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Übungsoptionen")
        }
    }

    private func addSet(to se: SessionExercise) {
        let last = se.sortedSets.last
        let entry = SetEntry(exerciseId: se.exerciseId, date: session.startedAt, order: (last?.order ?? -1) + 1,
                             weightKg: last?.weightKg ?? 0, reps: last?.reps ?? se.repMin, isDone: true)
        context.insert(entry)
        entry.sessionExercise = se
        try? context.save()
    }

    private func deleteSet(_ set: SetEntry, of se: SessionExercise) {
        context.delete(set)
        // An exercise without sets would only be an empty heading.
        if se.sets.allSatisfy({ $0 === set }) { context.delete(se) }
        try? context.save()
    }
}

/// Weight & reps of a logged set, editable in place.
struct EditableSetRow: View {
    @Bindable var set: SetEntry

    var body: some View {
        HStack {
            Text(verbatim: "\(set.order + 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
                .frame(width: 44, alignment: .leading)
            NumberField(placeholder: "0", value: $set.weightKg)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            NumberField(placeholder: "0", value: $set.reps.asDouble, decimals: false)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}
