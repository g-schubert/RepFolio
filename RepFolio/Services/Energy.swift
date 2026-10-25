import Foundation

/// Rough calorie estimates. These are estimates, not medical measurements:
/// - Base: Mifflin-St Jeor BMR × everyday activity factor
/// - Running: MET from speed (Compendium of Physical Activities), net of resting (MET − 1)
/// - Gym: MET 5.0 (vigorous resistance training), net of resting
enum Energy {
    static let gymMET = 5.0

    static func bmr(profile: UserProfile, weightKg: Double) -> Double {
        let base = 10 * weightKg + 6.25 * profile.heightCm - 5 * Double(profile.age)
        return profile.sex == .male ? base + 5 : base - 161
    }

    static func baseDaily(profile: UserProfile, weightKg: Double) -> Double {
        bmr(profile: profile, weightKg: weightKg) * profile.activityFactor
    }

    /// Running MET by speed (km/h), linear interpolation.
    static func runMET(speedKmh: Double) -> Double {
        let table: [(Double, Double)] = [
            (6.4, 6.0), (8.0, 8.3), (9.7, 9.8), (10.8, 10.5), (11.3, 11.0),
            (12.1, 11.8), (12.9, 12.3), (13.8, 12.8), (14.5, 14.5), (16.1, 16.0), (17.7, 19.0), (19.3, 19.8),
        ]
        guard speedKmh > 0 else { return 0 }
        if speedKmh <= table.first!.0 { return table.first!.1 }
        if speedKmh >= table.last!.0 { return table.last!.1 }
        for k in 1..<table.count where speedKmh <= table[k].0 {
            let (x0, y0) = table[k - 1], (x1, y1) = table[k]
            return y0 + (y1 - y0) * (speedKmh - x0) / (x1 - x0)
        }
        return table.last!.1
    }

    static func runKcal(_ run: RunEntry, weightKg: Double) -> Double {
        runKcal(distanceKm: run.distanceKm, durationSeconds: run.durationSeconds, weightKg: weightKg)
    }

    static func runKcal(distanceKm: Double, durationSeconds: Int, weightKg: Double) -> Double {
        guard durationSeconds > 0, distanceKm > 0 else { return 0 }
        let hours = Double(durationSeconds) / 3600
        let speed = distanceKm / hours
        return max(0, runMET(speedKmh: speed) - 1) * weightKg * hours
    }

    static func gymKcal(minutes: Double, weightKg: Double) -> Double {
        // Cap unrealistic durations (e.g. forgot to stop the workout) at 2.5 h.
        let h = min(minutes, 150) / 60
        return (gymMET - 1) * weightKg * h
    }

    /// Body weight valid on a date: latest entry on/before date, else earliest, else 75 kg.
    static func weight(on date: Date, entries: [BodyWeightEntry]) -> Double {
        let sorted = entries.sorted { $0.date < $1.date }
        return sorted.last(where: { $0.date <= date })?.kg ?? sorted.first?.kg ?? 75
    }

    struct Day: Identifiable {
        let date: Date
        let base: Double
        let gym: Double
        let run: Double
        var id: Date { date }
        var total: Double { base + gym + run }
        var active: Double { gym + run }
    }

    static func days(_ dates: [Date], profile: UserProfile, weights: [BodyWeightEntry],
                     sessions: [WorkoutSession], runs: [RunEntry]) -> [Day] {
        let cal = Cal.shared
        return dates.map { d in
            let w = weight(on: cal.endOfDay(d), entries: weights)
            let gym = sessions.filter { $0.isFinished && cal.isDate($0.startedAt, inSameDayAs: d) }
                .reduce(0) { $0 + gymKcal(minutes: $1.durationMinutes, weightKg: w) }
            let run = runs.filter { cal.isDate($0.date, inSameDayAs: d) }
                .reduce(0) { $0 + runKcal($1, weightKg: w) }
            return Day(date: d, base: baseDaily(profile: profile, weightKg: w), gym: gym, run: run)
        }
    }
}

// MARK: - Calendar & formatting helpers

enum Cal {
    /// Gregorian calendar with Monday as first weekday (ISO weeks).
    static let shared: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 2
        c.minimumDaysInFirstWeek = 4
        c.locale = Locale(identifier: "de_DE")
        return c
    }()
}

extension Calendar {
    func startOfWeek(_ date: Date) -> Date {
        dateInterval(of: .weekOfYear, for: date)?.start ?? startOfDay(for: date)
    }

    func endOfDay(_ date: Date) -> Date {
        self.date(byAdding: DateComponents(day: 1, second: -1), to: startOfDay(for: date)) ?? date
    }

    /// Last `count` days including today, oldest first.
    func lastDays(_ count: Int, from date: Date = .now) -> [Date] {
        let today = startOfDay(for: date)
        return (0..<count).reversed().compactMap { self.date(byAdding: .day, value: -$0, to: today) }
    }

    /// Start dates of the last `count` weeks including the current, oldest first.
    func lastWeekStarts(_ count: Int, from date: Date = .now) -> [Date] {
        let start = startOfWeek(date)
        return (0..<count).reversed().compactMap { self.date(byAdding: .weekOfYear, value: -$0, to: start) }
    }
}

enum Fmt {
    /// Formatting locale – follows the in-app language.
    static var locale: Locale { AppLanguage.current.locale }

    static func num(_ v: Double, digits: Int = 1) -> String {
        v.formatted(.number.precision(.fractionLength(0...digits)).locale(locale))
    }

    static func kg(_ v: Double) -> String { "\(num(v, digits: 2)) kg" }

    static func kcal(_ v: Double) -> String {
        "\(v.formatted(.number.precision(.fractionLength(0)).locale(locale))) kcal"
    }

    static func km(_ v: Double) -> String { "\(num(v, digits: 2)) km" }

    static func pace(_ secondsPerKm: Double) -> String {
        guard secondsPerKm.isFinite, secondsPerKm > 0 else { return "–" }
        let s = Int(secondsPerKm.rounded())
        return String(format: "%d:%02d /km", s / 60, s % 60)
    }

    static func duration(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    static func minutes(_ m: Double) -> String {
        let total = Int(m.rounded())
        return total >= 60 ? "\(total / 60) h \(total % 60) min" : "\(total) min"
    }

    static func day(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).locale(locale))
    }

    static func dayLong(_ d: Date) -> String {
        d.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(locale))
    }

    static func dateTime(_ d: Date) -> String {
        d.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened).locale(locale))
    }

    /// Parses "62,5" or "62.5".
    static func parse(_ text: String) -> Double? {
        guard let v = Double(text.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)),
              v.isFinite, v >= 0, v < 100_000 else { return nil }
        return v
    }
}
