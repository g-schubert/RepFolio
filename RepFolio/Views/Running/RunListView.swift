import SwiftUI
import SwiftData
import Charts

struct RunListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \RunEntry.date, order: .reverse) private var runs: [RunEntry]
    @Query private var weights: [BodyWeightEntry]
    @Query private var profiles: [UserProfile]

    @State private var editing: RunEntry?
    @State private var adding = false

    private let cal = Cal.shared

    private var weekRuns: [RunEntry] {
        let start = cal.startOfWeek(.now)
        return runs.filter { $0.date >= start }
    }

    private var monthKm: Double {
        let start = cal.dateInterval(of: .month, for: .now)?.start ?? .now
        return runs.filter { $0.date >= start }.reduce(0) { $0 + $1.distanceKm }
    }

    private struct WeekKm: Identifiable { let week: Date; let km: Double; var id: Date { week } }

    private var weeklyKm: [WeekKm] {
        cal.lastWeekStarts(10).map { start in
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return WeekKm(week: start, km: runs.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.distanceKm })
        }
    }

    private var bestPaceRun: RunEntry? {
        runs.filter { $0.distanceKm >= 3 && $0.paceSecondsPerKm > 0 }.min { $0.paceSecondsPerKm < $1.paceSecondsPerKm }
    }

    private var longestRun: RunEntry? { runs.max { $0.distanceKm < $1.distanceKm } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        StatTile(title: "Diese Woche",
                                 value: Fmt.km(weekRuns.reduce(0) { $0 + $1.distanceKm }),
                                 detail: L("\(weekRuns.count) / \(profiles.first?.runsPerWeekGoal ?? 2) Läufe"),
                                 symbol: "calendar", tint: .chartRun)
                        StatTile(title: "Dieser Monat", value: Fmt.km(monthKm), symbol: "calendar.badge.clock", tint: .chartRun)
                        StatTile(title: "Schnellste Pace", value: bestPaceRun.map { Fmt.pace($0.paceSecondsPerKm) } ?? "–",
                                 detail: bestPaceRun.map { L("\(Fmt.km($0.distanceKm)) am \(Fmt.day($0.date))") } ?? L("ab 3 km"),
                                 symbol: "bolt.fill", tint: .orange)
                        StatTile(title: "Längster Lauf", value: longestRun.map { Fmt.km($0.distanceKm) } ?? "–",
                                 detail: longestRun.map { Fmt.day($0.date) }, symbol: "road.lanes", tint: .blue)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                if !runs.isEmpty {
                    Section("Kilometer pro Woche") {
                        Chart(weeklyKm) { w in
                            BarMark(x: .value("Woche", w.week, unit: .weekOfYear), y: .value("km", w.km))
                                .foregroundStyle(Color.chartRun)
                                .cornerRadius(4)
                        }
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .weekOfYear, count: 2)) { _ in
                                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            }
                        }
                        .frame(height: 160)
                        .padding(.vertical, 6)
                    }
                }

                Section("Läufe") {
                    if runs.isEmpty {
                        ContentUnavailableView("Noch keine Läufe", systemImage: "figure.run",
                                               description: Text("Tippe auf +, um deinen ersten Lauf einzutragen."))
                    }
                    ForEach(runs) { run in
                        Button { editing = run } label: { RunRow(run: run, weightKg: Energy.weight(on: run.date, entries: weights)) }
                            .buttonStyle(.plain)
                    }
                    .onDelete { idx in
                        idx.map { runs[$0] }.forEach { context.delete($0) }
                        try? context.save()
                    }
                }
            }
            .navigationTitle("Laufen")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { adding = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                        .accessibilityLabel("Lauf hinzufügen")
                }
            }
            .sheet(isPresented: $adding) { RunEditorView(run: nil) }
            .sheet(item: $editing) { run in RunEditorView(run: run) }
        }
    }
}

struct RunRow: View {
    let run: RunEntry
    let weightKg: Double

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: run.type.symbol)
                .font(.title3)
                .frame(width: 40, height: 40)
                .background(Color.chartRun.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
                .foregroundStyle(Color.chartRun)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(Fmt.km(run.distanceKm)).font(.headline)
                    Text(run.type.label).font(.caption).foregroundStyle(.secondary)
                }
                Text(verbatim: "\(Fmt.day(run.date)) · \(Fmt.duration(run.durationSeconds)) · \(Fmt.pace(run.paceSecondsPerKm))")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.kcal(Energy.runKcal(run, weightKg: weightKg)))
                .font(.caption.weight(.semibold)).foregroundStyle(.orange)
        }
        .contentShape(Rectangle())
    }
}

struct RunEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var weights: [BodyWeightEntry]
    let run: RunEntry?

    @State private var date = Date.now
    @State private var distance: Double = 5
    @State private var hours = 0
    @State private var minutes = 30
    @State private var seconds = 0
    @State private var type: RunType = .easy
    @State private var feeling = 3
    @State private var heartRate: Double = 0
    @State private var notes = ""

    private var totalSeconds: Int { hours * 3600 + minutes * 60 + seconds }
    private var pace: Double { distance > 0 ? Double(totalSeconds) / distance : 0 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker("Datum", selection: $date)
                    Picker("Art", selection: $type) {
                        ForEach(RunType.allCases) { t in Label(t.label, systemImage: t.symbol).tag(t) }
                    }
                }
                Section("Distanz (km)") {
                    HStack {
                        NumberField(placeholder: "5,0", value: $distance)
                            .font(.title2.weight(.semibold))
                        Text("km").foregroundStyle(.secondary)
                    }
                    HStack {
                        ForEach([3.0, 5.0, 7.5, 10.0], id: \.self) { km in
                            Button(Fmt.num(km)) { distance = km }
                                .buttonStyle(.bordered)
                        }
                    }
                }
                Section("Dauer") {
                    HStack(spacing: 6) {
                        durationField("Std", value: $hours)
                        Text(":").font(.title2.weight(.semibold))
                        durationField("Min", value: $minutes)
                        Text(":").font(.title2.weight(.semibold))
                        durationField("Sek", value: $seconds)
                    }
                    LabeledContent("Pace", value: Fmt.pace(pace))
                    LabeledContent("Kalorien (geschätzt)", value: Fmt.kcal(estimatedKcal))
                }
                Section("Optional") {
                    HStack {
                        Text("Ø Puls")
                        Spacer()
                        NumberField(placeholder: "–", value: $heartRate, decimals: false)
                            .frame(width: 80)
                        Text("bpm").foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading) {
                        Text("Gefühl")
                        Picker("Gefühl", selection: $feeling) {
                            Text("Zäh").tag(1)
                            Text("Mäßig").tag(2)
                            Text("Okay").tag(3)
                            Text("Gut").tag(4)
                            Text("Super").tag(5)
                        }
                        .pickerStyle(.segmented)
                    }
                    TextField("Notiz (Strecke, Wetter …)", text: $notes, axis: .vertical)
                }
                if let run {
                    Section {
                        Button("Lauf löschen", role: .destructive) {
                            context.delete(run)
                            try? context.save()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(run == nil ? "Neuer Lauf" : "Lauf bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save).disabled(distance <= 0 || totalSeconds <= 0)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { hideKeyboard() }
                }
            }
            .onAppear(perform: load)
        }
    }

    private var estimatedKcal: Double {
        Energy.runKcal(distanceKm: distance, durationSeconds: totalSeconds,
                       weightKg: Energy.weight(on: date, entries: weights))
    }

    private func durationField(_ label: LocalizedStringKey, value: Binding<Int>) -> some View {
        VStack(spacing: 2) {
            NumberField(placeholder: "0", value: value.asDouble, decimals: false)
                .font(.title2.weight(.semibold))
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func load() {
        guard let run else { return }
        date = run.date
        distance = run.distanceKm
        hours = run.durationSeconds / 3600
        minutes = (run.durationSeconds % 3600) / 60
        seconds = run.durationSeconds % 60
        type = run.type
        feeling = run.feeling
        heartRate = Double(run.avgHeartRate ?? 0)
        notes = run.notes
    }

    private func save() {
        let target = run ?? RunEntry(date: date, distanceKm: distance, durationSeconds: totalSeconds)
        if run == nil { context.insert(target) }
        target.date = date
        target.distanceKm = distance
        target.durationSeconds = totalSeconds
        target.type = type
        target.feeling = feeling
        target.avgHeartRate = heartRate > 0 ? Int(heartRate) : nil
        target.notes = notes
        try? context.save()
        BackupService.autoBackup(context)
        dismiss()
    }
}
