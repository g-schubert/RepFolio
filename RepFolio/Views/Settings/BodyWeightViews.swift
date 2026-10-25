import SwiftUI
import SwiftData

/// Adds a new weigh-in, or edits / deletes an existing one when `entry` is set.
struct AddWeightSheet: View {
    var entry: BodyWeightEntry? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date) private var weights: [BodyWeightEntry]
    @State private var kg: Double = 0
    @State private var date = Date.now
    @State private var confirmDelete = false

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
                if entry == nil {
                    Section {
                        Text("Tipp: Am besten morgens nach dem Aufstehen wiegen – dann sind die Werte vergleichbar.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Button("Eintrag löschen", role: .destructive) { confirmDelete = true }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Gewicht eintragen" : "Gewicht bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Abbrechen") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern", action: save)
                        .disabled(kg < 30 || kg > 300)
                }
            }
            .confirmationDialog("Eintrag löschen?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Löschen", role: .destructive) {
                    if let entry { context.delete(entry) }
                    try? context.save()
                    BackupService.autoBackup(context)
                    dismiss()
                }
            }
            .onAppear {
                if let entry {
                    kg = entry.kg
                    date = entry.date
                } else if kg == 0 {
                    kg = weights.last?.kg ?? 75
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        if let entry {
            entry.kg = kg
            entry.date = date
        } else {
            context.insert(BodyWeightEntry(date: date, kg: kg))
        }
        try? context.save()
        BackupService.autoBackup(context)
        dismiss()
    }
}

struct BodyWeightListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \BodyWeightEntry.date, order: .reverse) private var weights: [BodyWeightEntry]
    @State private var adding = false
    @State private var editing: BodyWeightEntry?

    var body: some View {
        List {
            if weights.isEmpty {
                ContentUnavailableView("Noch keine Einträge", systemImage: "scalemass")
            }
            ForEach(Array(weights.enumerated()), id: \.element.id) { idx, w in
                Button {
                    editing = w
                } label: {
                    HStack {
                        Text(Fmt.dayLong(w.date)).foregroundStyle(.primary)
                        Spacer()
                        // Change to the previous (older) weigh-in.
                        if idx + 1 < weights.count {
                            let diff = w.kg - weights[idx + 1].kg
                            if abs(diff) >= 0.05 {
                                Text(verbatim: "\(diff > 0 ? "+" : "−")\(Fmt.num(abs(diff), digits: 1))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(Fmt.kg(w.kg)).monospacedDigit().fontWeight(.semibold).foregroundStyle(.primary)
                    }
                    .contentShape(Rectangle())
                }
                .swipeActions(edge: .trailing) {
                    Button("Löschen", systemImage: "trash", role: .destructive) { delete(w) }
                }
                .swipeActions(edge: .leading) {
                    Button("Bearbeiten", systemImage: "pencil") { editing = w }
                        .tint(.accentColor)
                }
                .contextMenu {
                    Button("Bearbeiten", systemImage: "pencil") { editing = w }
                    Button("Löschen", systemImage: "trash", role: .destructive) { delete(w) }
                }
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
        .sheet(item: $editing) { w in AddWeightSheet(entry: w) }
    }

    private func delete(_ entry: BodyWeightEntry) {
        context.delete(entry)
        try? context.save()
        BackupService.autoBackup(context)
    }
}
