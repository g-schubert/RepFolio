import SwiftUI
import SwiftData

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState
    @Environment(RestTimer.self) private var restTimer
    @Query private var profiles: [UserProfile]
    @Bindable var session: WorkoutSession

    @State private var confirmFinish = false
    @State private var showSummary = false
    @State private var adding = false
    @State private var detailExercise: Exercise?

    private var restSeconds: Int { profiles.first?.defaultRestSeconds ?? 90 }
    private var allSets: [SetEntry] { session.exercises.flatMap(\.sets) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    ForEach(session.sortedExercises) { se in
                        ExerciseLogCard(sessionExercise: se, sessionDate: session.startedAt, restSeconds: restSeconds) {
                            detailExercise = ExerciseCatalog.shared.exercise(se.exerciseId)
                        } onRemove: {
                            context.delete(se)
                            try? context.save()
                        }
                    }
                    Button {
                        adding = true
                    } label: {
                        Label("Übung hinzufügen", systemImage: "plus")
                            .frame(maxWidth: .infinity).padding(.vertical, 6)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        confirmFinish = true
                    } label: {
                        Label("Training beenden", systemImage: "flag.checkered")
                            .font(.headline).frame(maxWidth: .infinity).padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
                .padding()
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(session.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        try? context.save()
                        appState.activeSession = nil
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .accessibilityLabel("Minimieren")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Beenden") { confirmFinish = true }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { hideKeyboard() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if restTimer.isRunning { RestTimerBar() }
            }
            .confirmationDialog("Training beenden?", isPresented: $confirmFinish, titleVisibility: .visible) {
                Button("Speichern & beenden") { finish() }
                Button("Training verwerfen", role: .destructive) { discard() }
                Button("Weiter trainieren", role: .cancel) {}
            } message: {
                let open = allSets.filter { !$0.isDone }.count
                Text(open > 0 ? "\(open) Sätze sind noch nicht abgehakt – nur abgehakte Sätze werden gespeichert." : "Starke Leistung!")
            }
            .sheet(isPresented: $adding) {
                ExercisePickerView(title: "Übung hinzufügen") { ex in
                    WorkoutFactory.addExercise(ex.id, sets: 3, repMin: 8, repMax: 12,
                                               order: (session.exercises.map(\.order).max() ?? -1) + 1,
                                               to: session, in: context)
                    try? context.save()
                }
            }
            .sheet(item: $detailExercise) { ex in
                NavigationStack { ExerciseDetailView(exercise: ex, isSheet: true) }
            }
            .sheet(isPresented: $showSummary, onDismiss: {
                appState.activeSession = nil
            }) {
                WorkoutSummaryView(session: session)
            }
        }
    }

    private var header: some View {
        let done = allSets.filter(\.isDone).count
        let total = max(allSets.count, 1)
        return VStack(spacing: 10) {
            HStack {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    Label(Fmt.duration(Int(ctx.date.timeIntervalSince(session.startedAt))), systemImage: "stopwatch")
                        .monospacedDigit()
                }
                Spacer()
                Text("\(done) / \(allSets.count) Sätze").monospacedDigit()
            }
            .font(.subheadline.weight(.semibold))
            ProgressView(value: Double(done), total: Double(total))
                .tint(.green)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func finish() {
        restTimer.stop()
        // Drop sets that were never checked off.
        for set in allSets where !set.isDone { context.delete(set) }
        for se in session.exercises where se.sets.allSatisfy({ !$0.isDone }) { context.delete(se) }
        session.endedAt = .now
        try? context.save()
        BackupService.autoBackup(context)
        showSummary = true
    }

    private func discard() {
        restTimer.stop()
        context.delete(session)
        try? context.save()
        appState.activeSession = nil
    }
}

// MARK: - Exercise card

struct ExerciseLogCard: View {
    @Environment(\.modelContext) private var context
    @Environment(RestTimer.self) private var restTimer
    @Bindable var sessionExercise: SessionExercise
    let sessionDate: Date
    let restSeconds: Int
    let onInfo: () -> Void
    let onRemove: () -> Void

    @Query private var notes: [ExerciseNote]
    @State private var suggestion: Progression.Suggestion?
    @State private var lastText: String?
    @State private var bestBefore: Double = 0
    @State private var swapping = false

    init(sessionExercise: SessionExercise, sessionDate: Date, restSeconds: Int,
         onInfo: @escaping () -> Void, onRemove: @escaping () -> Void) {
        _sessionExercise = Bindable(sessionExercise)
        self.sessionDate = sessionDate
        self.restSeconds = restSeconds
        self.onInfo = onInfo
        self.onRemove = onRemove
        let id = sessionExercise.exerciseId
        _notes = Query(filter: #Predicate<ExerciseNote> { $0.exerciseId == id })
    }

    private var exercise: Exercise { ExerciseCatalog.shared.exercise(sessionExercise.exerciseId) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Button(action: onInfo) {
                    ExerciseImageView(exercise: exercise, customPhoto: notes.first?.customPhoto, cornerRadius: 10)
                        .frame(width: 110, height: 78)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "info.circle.fill")
                                .font(.caption).padding(4)
                                .foregroundStyle(.white).shadow(radius: 2)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ausführung: \(exercise.name)")
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.headline)
                    Text("\(sessionExercise.sets.count) × \(sessionExercise.repMin)–\(sessionExercise.repMax) Wdh. · \(exercise.equipmentName)")
                        .font(.caption).foregroundStyle(.secondary)
                    if let settings = notes.first?.machineSettings, !settings.isEmpty {
                        Label(settings, systemImage: "gearshape").font(.caption).foregroundStyle(.orange)
                    }
                }
                Spacer(minLength: 0)
                Menu {
                    Button("Ausführung ansehen", systemImage: "info.circle", action: onInfo)
                    Button("Übung tauschen", systemImage: "arrow.triangle.2.circlepath") { swapping = true }
                    Button("Übung entfernen", systemImage: "trash", role: .destructive, action: onRemove)
                } label: {
                    Image(systemName: "ellipsis")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Übungsoptionen")
            }

            if let suggestion {
                Label(suggestion.text, systemImage: suggestion.isIncrease ? "arrow.up.circle.fill"
                      : suggestion.isDeload ? "arrow.down.circle.fill" : "lightbulb")
                    .font(.caption)
                    .foregroundStyle(suggestion.isIncrease ? Color.green : suggestion.isDeload ? Color.orange : Color.secondary)
            }
            if let lastText {
                Text(lastText).font(.caption2).foregroundStyle(.secondary)
            }

            VStack(spacing: 6) {
                HStack {
                    Text("Satz").frame(width: 36)
                    Text("kg").frame(maxWidth: .infinity)
                    Text("Wdh.").frame(maxWidth: .infinity)
                    Image(systemName: "checkmark").frame(width: 44).accessibilityLabel("Erledigt")
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                ForEach(sessionExercise.sortedSets) { set in
                    SetRow(set: set, isPR: set.isDone && bestBefore > 0 && set.estimatedOneRepMax > bestBefore) {
                        toggle(set)
                    }
                    .contextMenu {
                        Button("Satz löschen", systemImage: "trash", role: .destructive) {
                            context.delete(set)
                            try? context.save()
                        }
                    }
                }
            }

            if Plates.applies(to: exercise), let weight = plateWeight {
                PlateLoadView(weight: weight)
            }

            HStack {
                Button {
                    addSet()
                } label: {
                    Label("Satz", systemImage: "plus").font(.subheadline)
                }
                .buttonStyle(.bordered)
                Spacer()
                if let last = sessionExercise.sortedSets.last, sessionExercise.sets.count > 1 {
                    Button(role: .destructive) {
                        context.delete(last)
                        try? context.save()
                    } label: {
                        Label("Satz", systemImage: "minus").font(.subheadline)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task(id: sessionExercise.exerciseId) { loadHistory() }
        .sheet(isPresented: $swapping) {
            ExercisePickerView(title: "Übung tauschen",
                               suggestions: ExerciseCatalog.shared.alternatives(for: sessionExercise.exerciseId)) { ex in
                WorkoutFactory.swap(sessionExercise, to: ex.id, in: context)
            }
        }
    }

    /// Weight of the next open set (or the last one) – the bar you are about to load.
    private var plateWeight: Double? {
        let sets = sessionExercise.sortedSets
        return (sets.first { !$0.isDone } ?? sets.last)?.weightKg
    }

    private func loadHistory() {
        let history = History.sessions(for: sessionExercise.exerciseId, in: context)
        let last = history.first?.sets ?? []
        suggestion = Progression.suggest(lastSets: last, earlier: history.dropFirst().map(\.sets),
                                         repMin: sessionExercise.repMin, repMax: sessionExercise.repMax,
                                         increment: exercise.increment)
        if let first = last.first {
            let list = last.map { "\(Fmt.num($0.weightKg, digits: 2))×\($0.reps)" }.joined(separator: " · ")
            lastText = L("Letztes Mal (\(first.date.formatted(.dateTime.day().month(.abbreviated).locale(Fmt.locale)))): \(list)")
        }
        bestBefore = History.bestOneRepMax(for: sessionExercise.exerciseId, before: sessionDate, in: context)
    }

    private func toggle(_ set: SetEntry) {
        set.isDone.toggle()
        try? context.save()
        if set.isDone {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            restTimer.start(seconds: restSeconds)
        }
    }

    private func addSet() {
        let last = sessionExercise.sortedSets.last
        let entry = SetEntry(exerciseId: sessionExercise.exerciseId, date: sessionDate,
                             order: (last?.order ?? -1) + 1,
                             weightKg: last?.weightKg ?? 0, reps: last?.reps ?? sessionExercise.repMin)
        context.insert(entry)
        entry.sessionExercise = sessionExercise
        try? context.save()
    }
}

struct SetRow: View {
    @Bindable var set: SetEntry
    let isPR: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            ZStack {
                Text(verbatim: "\(set.order + 1)").font(.subheadline.weight(.semibold)).monospacedDigit()
                if isPR {
                    Image(systemName: "trophy.fill").font(.caption2).foregroundStyle(.yellow).offset(x: 13, y: -10)
                }
            }
            .frame(width: 36)
            NumberField(placeholder: "0", value: $set.weightKg)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            NumberField(placeholder: "0", value: $set.reps.asDouble, decimals: false)
                .padding(.vertical, 8)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Button(action: onToggle) {
                Image(systemName: set.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(set.isDone ? .green : .secondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(set.isDone ? "Satz erledigt" : "Satz abhaken")
        }
        .opacity(set.isDone ? 0.75 : 1)
    }
}

// MARK: - Rest timer

struct RestTimerBar: View {
    @Environment(RestTimer.self) private var restTimer

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
            let remaining = restTimer.remaining(at: ctx.date)
            HStack(spacing: 14) {
                Image(systemName: "timer").font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Pause").font(.caption).foregroundStyle(.secondary)
                    Text(Fmt.duration(remaining)).font(.title2.weight(.bold)).monospacedDigit()
                }
                Spacer()
                Button("−15") { restTimer.add(-15) }.buttonStyle(.bordered)
                Button("+15") { restTimer.add(15) }.buttonStyle(.bordered)
                Button {
                    restTimer.stop()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Pause beenden")
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial)
            .onChange(of: remaining) { _, new in
                if new == 0 { restTimer.finishIfNeeded() }
            }
        }
    }
}
