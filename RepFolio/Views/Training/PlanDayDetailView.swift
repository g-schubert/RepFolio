import SwiftUI
import SwiftData

struct PlanDayDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Bindable var day: PlanDay
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt == nil }) private var open: [WorkoutSession]

    @State private var editing: PlanExercise?
    @State private var swapping: PlanExercise?
    @State private var adding = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var detailExercise: Exercise?

    var body: some View {
        List {
            Section {
                ForEach(day.sortedExercises) { pe in
                    let ex = ExerciseCatalog.shared.exercise(pe.exerciseId)
                    HStack(spacing: 12) {
                        Button {
                            detailExercise = ex
                        } label: {
                            HStack(spacing: 12) {
                                ExerciseThumb(exerciseId: pe.exerciseId, size: 60)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(ex.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                                    Text("\(pe.sets) × \(pe.repMin)–\(pe.repMax) Wdh. · \(ex.equipmentName)")
                                        .font(.caption).foregroundStyle(.secondary)
                                    LastTopSetText(exerciseId: pe.exerciseId)
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.borderless)

                        Menu {
                            Button("Sätze & Wiederholungen", systemImage: "slider.horizontal.3") { editing = pe }
                            Button("Übung tauschen", systemImage: "arrow.triangle.2.circlepath") { swapping = pe }
                            Button("Entfernen", systemImage: "trash", role: .destructive) { remove(pe) }
                        } label: {
                            Image(systemName: "ellipsis.circle").font(.title3).padding(.vertical, 8)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Übungsoptionen")
                    }
                }
                .onDelete { idx in
                    let items = day.sortedExercises
                    idx.map { items[$0] }.forEach(remove)
                }
                .onMove(perform: move)

                Button {
                    adding = true
                } label: {
                    Label("Übung hinzufügen", systemImage: "plus.circle.fill")
                }
            } header: {
                Text(day.displaySubtitle)
            } footer: {
                Text("Tippe auf eine Übung für Bild & Ausführung. Über ••• kannst du Sätze ändern oder die Übung gegen ein anderes Gerät tauschen (z. B. wenn es besetzt ist).")
            }
        }
        .navigationTitle(day.displayName)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Umbenennen", systemImage: "pencil") { newName = day.displayName; renaming = true }
                    EditButton()
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Mehr")
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button {
                if let running = open.first {
                    appState.activeSession = running
                } else {
                    appState.activeSession = WorkoutFactory.start(day: day, in: context)
                }
            } label: {
                Label(open.isEmpty ? "\(day.displayName) starten" : "Laufendes Training öffnen", systemImage: "play.fill")
                    .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding()
            .background(.bar)
        }
        .sheet(item: $editing) { pe in
            PlanExerciseEditor(planExercise: pe)
                .presentationDetents([.medium])
        }
        .sheet(item: $swapping) { pe in
            ExercisePickerView(title: "Übung tauschen", suggestions: ExerciseCatalog.shared.alternatives(for: pe.exerciseId)) { ex in
                pe.exerciseId = ex.id
                try? context.save()
            }
        }
        .sheet(isPresented: $adding) {
            ExercisePickerView(title: "Übung hinzufügen") { ex in
                let pe = PlanExercise(exerciseId: ex.id, order: (day.exercises.map(\.order).max() ?? -1) + 1,
                                      sets: 3, repMin: 8, repMax: 12)
                context.insert(pe)
                pe.day = day
                try? context.save()
            }
        }
        .sheet(item: $detailExercise) { ex in
            NavigationStack { ExerciseDetailView(exercise: ex, isSheet: true) }
        }
        .alert("Trainingstag umbenennen", isPresented: $renaming) {
            TextField("Name", text: $newName)
            Button("Speichern") {
                // Unchanged → keep the stored (German) default name, which links sessions to this day.
                if !newName.trimmingCharacters(in: .whitespaces).isEmpty, newName != day.displayName {
                    day.name = newName
                    try? context.save()
                }
            }
            Button("Abbrechen", role: .cancel) {}
        }
    }

    private func remove(_ pe: PlanExercise) {
        context.delete(pe)
        try? context.save()
        renumber()
    }

    private func move(from source: IndexSet, to destination: Int) {
        var items = day.sortedExercises
        items.move(fromOffsets: source, toOffset: destination)
        for (i, pe) in items.enumerated() { pe.order = i }
        try? context.save()
    }

    private func renumber() {
        for (i, pe) in day.sortedExercises.enumerated() { pe.order = i }
    }
}

/// "Zuletzt: 60 kg × 10" for an exercise.
struct LastTopSetText: View {
    let exerciseId: String
    @Environment(\.modelContext) private var context
    @State private var text: String?

    var body: some View {
        Group {
            if let text {
                Text(text).font(.caption2.weight(.medium)).foregroundStyle(Color.accentColor)
            }
        }
        .task(id: exerciseId) {
            let last = History.lastSessionSets(for: exerciseId, in: context)
            if let top = last.max(by: { $0.weightKg < $1.weightKg }) {
                text = L("Zuletzt: \(Fmt.kg(top.weightKg)) × \(top.reps)")
            } else {
                text = nil
            }
        }
    }
}

struct PlanExerciseEditor: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Bindable var planExercise: PlanExercise

    var body: some View {
        NavigationStack {
            Form {
                Section(ExerciseCatalog.shared.exercise(planExercise.exerciseId).name) {
                    Stepper("Sätze: \(planExercise.sets)", value: $planExercise.sets, in: 1...10)
                    Stepper("Min. Wiederholungen: \(planExercise.repMin)", value: $planExercise.repMin, in: 1...50)
                    Stepper("Max. Wiederholungen: \(planExercise.repMax)", value: $planExercise.repMax, in: planExercise.repMin...60)
                }
                Section {
                    Text("Doppelte Progression: Schaffst du in allen Sätzen die max. Wiederholungen, schlägt die App beim nächsten Mal mehr Gewicht vor. Kommst du 3 Trainings lang nicht weiter, schlägt sie einen Deload (ca. −10 %) vor.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sätze & Wdh.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") {
                        planExercise.repMax = max(planExercise.repMax, planExercise.repMin)
                        try? context.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss
    let title: LocalizedStringKey
    var suggestions: [Exercise] = []
    let onPick: (Exercise) -> Void
    @State private var search = ""
    @State private var equipment: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    EquipmentFilter(selection: $equipment)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                if search.isEmpty && equipment == nil && !suggestions.isEmpty {
                    Section("Passende Alternativen") {
                        ForEach(suggestions) { ex in row(ex) }
                    }
                }
                ForEach(ExerciseCatalog.shared.grouped(matching: search, equipment: equipment)) { group in
                    Section(CatalogText.group(group.group)) {
                        ForEach(group.items) { ex in row(ex) }
                    }
                }
            }
            .searchable(text: $search, prompt: "Übung oder Gerät suchen")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
            }
        }
    }

    private func row(_ ex: Exercise) -> some View {
        Button {
            onPick(ex)
            dismiss()
        } label: {
            HStack(spacing: 12) {
                ExerciseThumb(exerciseId: ex.id, size: 48)
                VStack(alignment: .leading) {
                    Text(ex.name).foregroundStyle(.primary)
                    Text(verbatim: "\(ex.equipmentName) · \(ex.primaryMusclesText)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}
