import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var profiles: [UserProfile]

    @State private var name = ""
    @State private var sex: Sex = .male
    @State private var birthYear = 1998
    @State private var height: Double = 180
    @State private var weight: Double = 78
    @State private var gymDays = 3
    @State private var runs = 2

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "dumbbell.fill").font(.largeTitle).foregroundStyle(Color.accentColor)
                        Text("Willkommen bei RepFolio").font(.title2.weight(.bold))
                        Text("Ein paar Angaben für deinen Plan und die Kalorienschätzung. Alles bleibt lokal auf deinem iPhone.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section("Über dich") {
                    TextField("Vorname", text: $name)
                    Picker("Geschlecht", selection: $sex) {
                        ForEach(Sex.allCases) { Text($0.label).tag($0) }
                    }
                    Stepper("Geburtsjahr: \(String(birthYear))", value: $birthYear, in: 1940...2015)
                    Stepper("Größe: \(Int(height)) cm", value: $height, in: 120...230)
                    HStack {
                        Text("Gewicht")
                        Spacer()
                        NumberField(placeholder: "78", value: $weight).frame(width: 80)
                        Text("kg").foregroundStyle(.secondary)
                    }
                }
                Section {
                    Picker("Gym pro Woche", selection: $gymDays) {
                        Text("2×").tag(2)
                        Text("3×").tag(3)
                    }
                    .pickerStyle(.segmented)
                    Stepper("Läufe pro Woche: \(runs)", value: $runs, in: 0...7)
                } header: {
                    Text("Dein Wochenziel")
                } footer: {
                    Text("Kannst du jederzeit im Training-Tab umstellen.")
                }
            }
            .navigationTitle("Los geht's")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig", action: save).disabled(weight < 30)
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Fertig") { hideKeyboard() }
                }
            }
        }
    }

    private func save() {
        let profile = profiles.first ?? {
            let p = UserProfile()
            context.insert(p)
            return p
        }()
        profile.name = name.trimmingCharacters(in: .whitespaces)
        profile.sex = sex
        profile.birthYear = birthYear
        profile.heightCm = height
        profile.gymDaysPerWeek = gymDays
        profile.runsPerWeekGoal = runs
        profile.onboardingDone = true
        context.insert(BodyWeightEntry(date: .now, kg: weight))
        try? context.save()
        BackupService.autoBackup(context)
        dismiss()
    }
}
