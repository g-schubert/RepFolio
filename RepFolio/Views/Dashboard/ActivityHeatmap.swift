import SwiftUI

/// Calendar grid of the last weeks: one cell per day, colored by gym / run.
struct ActivityHeatmap: View {
    let sessions: [WorkoutSession]
    let runs: [RunEntry]
    var weeks: Int = 18

    private let cal = Cal.shared

    var body: some View {
        let gymDays = Set(sessions.map { cal.startOfDay(for: $0.startedAt) })
        let runDays = Set(runs.map { cal.startOfDay(for: $0.date) })
        let today = cal.startOfDay(for: .now)
        let starts = cal.lastWeekStarts(weeks)
        let active = gymDays.union(runDays).filter { $0 >= (starts.first ?? today) }.count

        Card(title: "Aktivität", symbol: "square.grid.3x3.fill") {
            HStack(alignment: .top, spacing: 3) {
                ForEach(starts, id: \.self) { start in
                    VStack(spacing: 3) {
                        ForEach(0..<7, id: \.self) { offset in
                            let day = cal.date(byAdding: .day, value: offset, to: start) ?? start
                            cell(gym: gymDays.contains(day), run: runDays.contains(day), future: day > today)
                        }
                    }
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Aktive Tage: \(active) · letzte \(weeks) Wochen"))
            HStack(spacing: 14) {
                LegendDot(color: .chartGym, text: "Gym")
                LegendDot(color: .chartRun, text: "Laufen")
                Spacer()
                Text("Aktive Tage: \(active) · letzte \(weeks) Wochen").font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func cell(gym: Bool, run: Bool, future: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        return Group {
            if gym && run {
                VStack(spacing: 0) {
                    Color.chartGym
                    Color.chartRun
                }
                .clipShape(shape)
            } else if gym || run {
                shape.fill(gym ? Color.chartGym : Color.chartRun)
            } else {
                shape.fill(Color.secondary.opacity(future ? 0.05 : 0.14))
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }
}
