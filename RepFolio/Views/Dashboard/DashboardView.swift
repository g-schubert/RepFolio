import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Environment(AppState.self) private var appState
    @Query private var profiles: [UserProfile]
    @Query(filter: #Predicate<WorkoutSession> { $0.endedAt != nil }, sort: \WorkoutSession.startedAt, order: .reverse)
    private var sessions: [WorkoutSession]
    @Query(sort: \RunEntry.date, order: .reverse) private var runs: [RunEntry]
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @Query(sort: \PlanDay.order) private var allDays: [PlanDay]

    @State private var selectedDay: Date?
    @State private var addingWeight = false

    private let cal = Cal.shared

    var body: some View {
        NavigationStack {
            ScrollView {
                if let profile = profiles.first {
                    content(profile)
                        .padding()
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(greeting)
            .sheet(isPresented: $addingWeight) { AddWeightSheet() }
        }
    }

    private var greeting: String {
        let name = profiles.first?.name ?? ""
        return name.isEmpty ? L("Übersicht") : L("Hi \(name)")
    }

    @ViewBuilder
    private func content(_ profile: UserProfile) -> some View {
        let weekStart = cal.startOfWeek(.now)
        let gymWeek = sessions.filter { $0.startedAt >= weekStart }
        let runWeek = runs.filter { $0.date >= weekStart }

        VStack(spacing: 16) {
            ExpiryBanner()

            // Weekly goals
            Card(title: "Diese Woche (KW \(cal.component(.weekOfYear, from: .now)))", symbol: "target") {
                HStack {
                    GoalRing(value: gymWeek.count, goal: profile.gymDaysPerWeek, title: "Gym", tint: .chartGym)
                    Spacer()
                    GoalRing(value: runWeek.count, goal: profile.runsPerWeekGoal, title: "Laufen", tint: .chartRun)
                    Spacer()
                    VStack(alignment: .leading, spacing: 6) {
                        Label("\(streakWeeks(goal: profile.gymDaysPerWeek)) Wo. Serie", systemImage: "flame.fill")
                            .foregroundStyle(.orange)
                        Label(Fmt.km(runWeek.reduce(0) { $0 + $1.distanceKm }), systemImage: "figure.run")
                        Label("\(Fmt.num(gymWeek.reduce(0) { $0 + $1.volume } / 1000, digits: 1)) t bewegt", systemImage: "scalemass")
                    }
                    .font(.subheadline.weight(.medium))
                }
            }

            nextWorkout(profile)

            energySection(profile)

            muscleSection(gymWeek: gymWeek)

            weightSection

            totalsSection

            PreferencesCard()
        }
    }

    // MARK: Next workout

    @ViewBuilder
    private func nextWorkout(_ profile: UserProfile) -> some View {
        let days = allDays.filter { $0.frequency == profile.gymDaysPerWeek }
        if let next = WorkoutFactory.nextDay(days: days, finishedSessions: sessions) {
            Button {
                appState.selectedTab = .training
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "dumbbell.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(Color.chartGym.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
                        .foregroundStyle(Color.chartGym)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nächstes Training").font(.caption).foregroundStyle(.secondary)
                        Text(next.displayName).font(.headline).foregroundStyle(.primary)
                        Text(lastWorkoutText).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
                .padding(16)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var lastWorkoutText: String {
        guard let last = sessions.first else { return L("Noch kein Training eingetragen") }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: last.startedAt), to: cal.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return L("Letztes Training: heute")
        case 1: return L("Letztes Training: gestern")
        default: return L("Letztes Training: vor \(days) Tagen")
        }
    }

    // MARK: Energy

    private struct EnergyPoint: Identifiable {
        let date: Date; let kind: String; let kcal: Double
        var id: String { "\(kind)-\(date.timeIntervalSince1970)" }
    }

    @ViewBuilder
    private func energySection(_ profile: UserProfile) -> some View {
        let days = Energy.days(cal.lastDays(7), profile: profile, weights: weights, sessions: sessions, runs: runs)
        let today = days.last
        let weekDays = Energy.days(daysOfCurrentWeek(), profile: profile, weights: weights, sessions: sessions, runs: runs)
        let weekTotal = weekDays.reduce(0) { $0 + $1.total }
        let weekActive = weekDays.reduce(0) { $0 + $1.active }
        let baseKind = L("Grundumsatz"), gymKind = L("Gym"), runKind = L("Laufen")
        let points = days.flatMap { d in [
            EnergyPoint(date: d.date, kind: baseKind, kcal: d.base),
            EnergyPoint(date: d.date, kind: gymKind, kcal: d.gym),
            EnergyPoint(date: d.date, kind: runKind, kcal: d.run),
        ] }
        let selected = selectedDay.flatMap { s in days.first { cal.isDate($0.date, inSameDayAs: s) } }

        Card(title: "Kalorienverbrauch (geschätzt)", symbol: "flame") {
            HStack {
                StatTile(title: "Heute", value: Fmt.kcal(today?.total ?? 0),
                         detail: L("davon aktiv \(Fmt.kcal(today?.active ?? 0))"), symbol: "sun.max", tint: .chartBase)
                StatTile(title: "Diese Woche", value: Fmt.kcal(weekTotal),
                         detail: L("aktiv \(Fmt.kcal(weekActive)) · Ø \(Fmt.kcal(weekTotal / Double(max(weekDays.count, 1))))/Tag"),
                         symbol: "calendar", tint: .chartGym)
            }

            Text(selected.map { L("\(Fmt.day($0.date)): \(Fmt.kcal($0.total)) – Gym \(Fmt.kcal($0.gym)), Laufen \(Fmt.kcal($0.run))") }
                 ?? L("Letzte 7 Tage · tippe auf einen Balken"))
                .font(.caption).foregroundStyle(.secondary)

            Chart(points) { p in
                BarMark(x: .value("Tag", p.date, unit: .day), y: .value("kcal", p.kcal))
                    .foregroundStyle(by: .value("Art", p.kind))
                    .cornerRadius(4)
                    .opacity(selected == nil || cal.isDate(p.date, inSameDayAs: selected!.date) ? 1 : 0.4)
            }
            .chartForegroundStyleScale([baseKind: Color.chartBase, gymKind: Color.chartGym, runKind: Color.chartRun])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow), centered: true)
                }
            }
            .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine(); AxisValueLabel() } }
            .chartLegend(position: .bottom)
            .chartXSelection(value: $selectedDay)
            .frame(height: 200)

            Text("Grundumsatz nach Mifflin-St Jeor × Alltagsfaktor \(Fmt.num(profile.activityFactor, digits: 2)); Training über MET-Werte. Nur eine grobe Schätzung.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
    }

    private func daysOfCurrentWeek() -> [Date] {
        let start = cal.startOfWeek(.now)
        let today = cal.startOfDay(for: .now)
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.filter { $0 <= today }
    }

    // MARK: Muscles

    private struct MuscleSets: Identifiable { let group: String; let sets: Int; var id: String { group } }

    @ViewBuilder
    private func muscleSection(gymWeek: [WorkoutSession]) -> some View {
        let catalog = ExerciseCatalog.shared
        let counts = Dictionary(grouping: gymWeek.flatMap(\.doneSets), by: { catalog.exercise($0.exerciseId).group })
            .mapValues(\.count)
        let data = ExerciseCatalog.groupOrder.filter { $0 != "Sonstiges" }
            .map { MuscleSets(group: CatalogText.group($0), sets: counts[$0] ?? 0) }

        Card(title: "Sätze pro Muskelgruppe (Woche)", symbol: "figure.strengthtraining.traditional") {
            if gymWeek.isEmpty {
                Text("Diese Woche noch kein Gym-Training.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Chart(data) { m in
                    BarMark(x: .value("Sätze", m.sets), y: .value("Gruppe", m.group))
                        .foregroundStyle(Color.chartGym)
                        .cornerRadius(4)
                        .annotation(position: .trailing) {
                            Text("\(m.sets)").font(.caption2).foregroundStyle(.secondary)
                        }
                }
                .chartXAxis(.hidden)
                .frame(height: CGFloat(data.count) * 28)
                Text("Richtwert für Muskelaufbau: ca. 10–20 Sätze pro Muskelgruppe und Woche.")
                    .font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: Body weight

    private struct WeightPoint: Identifiable { let date: Date; let kg: Double; var id: Date { date } }

    @ViewBuilder
    private var weightSection: some View {
        let since = cal.date(byAdding: .day, value: -120, to: .now) ?? .now
        let recent = weights.filter { $0.date >= since }.map { WeightPoint(date: $0.date, kg: $0.kg) }
        let current = weights.last?.kg
        let monthAgo = cal.date(byAdding: .day, value: -30, to: .now) ?? .now
        let reference = weights.last(where: { $0.date <= monthAgo })?.kg ?? weights.first?.kg

        Card(title: "Körpergewicht", symbol: "scalemass") {
            HStack(alignment: .firstTextBaseline) {
                Text(current.map(Fmt.kg) ?? "–").font(.title.weight(.bold)).monospacedDigit()
                if let current, let reference, weights.count > 1 {
                    let diff = current - reference
                    Text("\(diff >= 0 ? "+" : "−")\(Fmt.num(abs(diff), digits: 1)) kg in 30 Tagen")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    addingWeight = true
                } label: {
                    Label("Eintragen", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            if recent.count >= 2 {
                let minKg = (recent.map(\.kg).min() ?? 0) - 1
                let maxKg = (recent.map(\.kg).max() ?? 0) + 1
                Chart(recent) { p in
                    LineMark(x: .value("Datum", p.date), y: .value("kg", p.kg))
                        .foregroundStyle(Color.chartGym)
                        .lineStyle(StrokeStyle(lineWidth: 2))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Datum", p.date), y: .value("kg", p.kg))
                        .foregroundStyle(Color.chartGym)
                        .symbolSize(30)
                }
                .chartYScale(domain: minKg...maxKg)
                .frame(height: 150)
            }
            NavigationLink {
                BodyWeightListView()
            } label: {
                Text("Alle Einträge").font(.caption)
            }
        }
    }

    // MARK: Totals & records

    private struct PR: Identifiable { let exerciseId: String; let date: Date; let oneRM: Double; var id: String { exerciseId } }

    @ViewBuilder
    private var totalsSection: some View {
        let totalVolume = sessions.reduce(0) { $0 + $1.volume }
        let totalKm = runs.reduce(0) { $0 + $1.distanceKm }
        let prs = recentRecords(days: 30)

        Card(title: "Gesamt", symbol: "sum") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                StatTile(title: "Trainings", value: "\(sessions.count)", symbol: "dumbbell", tint: .chartGym)
                StatTile(title: "Läufe", value: "\(runs.count)", detail: Fmt.km(totalKm), symbol: "figure.run", tint: .chartRun)
                StatTile(title: "Volumen", value: "\(Fmt.num(totalVolume / 1000, digits: 1)) t", symbol: "scalemass", tint: .chartGym)
                StatTile(title: "Rekorde (30 T.)", value: "\(prs.count)", symbol: "trophy", tint: .orange)
            }
            if !prs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(prs.prefix(5)) { pr in
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text(ExerciseCatalog.shared.exercise(pr.exerciseId).name).font(.subheadline)
                            Spacer()
                            Text("1RM \(Fmt.kg(pr.oneRM))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    /// Exercises whose best estimated 1RM was set within the last `days` days (and improved on an older best).
    private func recentRecords(days: Int) -> [PR] {
        let cutoff = cal.date(byAdding: .day, value: -days, to: .now) ?? .now
        var byExercise: [String: [(Date, Double)]] = [:]
        for s in sessions {
            for set in s.doneSets {
                byExercise[set.exerciseId, default: []].append((s.startedAt, set.estimatedOneRepMax))
            }
        }
        var result: [PR] = []
        for (id, entries) in byExercise {
            let old = entries.filter { $0.0 < cutoff }.map(\.1).max() ?? 0
            guard old > 0, let best = entries.filter({ $0.0 >= cutoff }).max(by: { $0.1 < $1.1 }), best.1 > old else { continue }
            result.append(PR(exerciseId: id, date: best.0, oneRM: best.1))
        }
        return result.sorted { $0.date > $1.date }
    }

    /// Consecutive weeks (ending this week if already reached, else last week) with gym sessions ≥ goal.
    private func streakWeeks(goal: Int) -> Int {
        guard goal > 0 else { return 0 }
        var streak = 0
        var weekStart = cal.startOfWeek(.now)
        func count(_ start: Date) -> Int {
            let end = cal.date(byAdding: .weekOfYear, value: 1, to: start) ?? start
            return sessions.filter { $0.startedAt >= start && $0.startedAt < end }.count
        }
        if count(weekStart) >= goal { streak += 1 }
        weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        while count(weekStart) >= goal {
            streak += 1
            weekStart = cal.date(byAdding: .weekOfYear, value: -1, to: weekStart) ?? weekStart
        }
        return streak
    }
}

// MARK: - Expiry banner

struct ExpiryBanner: View {
    var body: some View {
        if let exp = ProvisioningInfo.expirationDate, let hours = ProvisioningInfo.hoursLeft {
            let urgent = hours < 48
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: urgent ? "exclamationmark.triangle.fill" : "checkmark.shield")
                    .font(.title3)
                    .foregroundStyle(urgent ? .orange : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(urgent ? "App läuft bald ab" : "App-Signatur gültig")
                        .font(.subheadline.weight(.semibold))
                    Group {
                        if !urgent {
                            Text("Bis \(Fmt.dateTime(exp)). Du wirst rechtzeitig erinnert.")
                        } else if hours < 24 {
                            Text("Noch \(Int(max(hours, 0))) Std. – bis \(Fmt.dateTime(exp)). iPhone an den Mac, in Xcode ▶︎ drücken. Deine Daten bleiben erhalten.")
                        } else {
                            Text("Noch \(Int(hours / 24)) Tag(e) – bis \(Fmt.dateTime(exp)). iPhone an den Mac, in Xcode ▶︎ drücken. Deine Daten bleiben erhalten.")
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(urgent ? Color.orange.opacity(0.15) : Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
