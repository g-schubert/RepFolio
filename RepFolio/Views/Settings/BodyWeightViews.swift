import SwiftUI
import SwiftData

struct AddWeightSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @State private var kg: Double = 0
    @State private var date = Date.now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        NumberField(placeholder: "75,0", value: $kg)
                            .font(.largeTitle.weight(.bold))
                        Text("kg").font(.title2).foregroundStyle(.secondary)
                    }
                    DatePicker("Datum", selection: $date, displayedComponents: .date)
                }
                Section {
                    Text("Tipp: Am besten morgens nach dem Aufstehen wiegen – dann sind die Werte vergleichbar.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Gewicht eintragen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        context.insert(BodyWeightEntry(date: date, kg: kg))
                        try? context.save()
                        BackupService.autoBackup(context)
                        dismiss()
                    }
                    .disabled(kg < 30 || kg > 300)
                }
            }
            .onAppear { if kg == 0 { kg = weights.last?.kg ?? 75 } }
        }
        .presentationDetents([.medium])
    }
}

struct BodyWeightListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @State private var adding = false

    var body: some View {
        List {
            if weights.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "scalemass")
            }
            ForEach(weights) { w in
                HStack {
                    Text(Fmt.dayLong(w.date))
                    Spacer()
                    Text(Fmt.kg(w.kg)).monospacedDigit().fontWeight(.semibold)
                }
            }
            .onDelete { idx in
                idx.map { weights[$0] }.forEach { context.delete($0) }
                try? context.save()
            }
        }
        .navigationTitle("Körpergewicht")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { adding = true } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Gewicht hinzufügen")
            }
        }
        .sheet(isPresented: $adding) { AddWeightSheet() }
    }
}
