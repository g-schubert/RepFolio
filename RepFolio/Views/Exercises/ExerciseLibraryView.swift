import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
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
                let groups = ExerciseCatalog.shared.grouped(matching: search, equipment: equipment)
                if groups.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
                ForEach(groups) { group in
                    Section {
                        ForEach(group.items) { ex in
                            NavigationLink(value: ex) {
                                HStack(spacing: 12) {
                                    ExerciseThumb(exerciseId: ex.id, size: 56)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(ex.name).font(.subheadline.weight(.semibold))
                                        Text(verbatim: "\(ex.equipmentName) · \(ex.primaryMusclesText)")
                                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }
                            }
                        }
                    } header: {
                        Label(CatalogText.group(group.group), systemImage: ExerciseCatalog.groupSymbols[group.group] ?? "circle")
                    }
                }
            }
            .searchable(text: $search, prompt: "z. B. Beinpresse, Kabel, Brust")
            .navigationTitle("Übungen")
            .navigationDestination(for: Exercise.self) { ex in
                ExerciseDetailView(exercise: ex)
            }
        }
    }
}

/// Horizontal chips: all equipment or one kind (machine, cable, …).
struct EquipmentFilter: View {
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(L("Alle"), symbol: "square.grid.2x2", value: nil)
                ForEach(ExerciseCatalog.shared.equipmentKinds, id: \.self) { eq in
                    chip(CatalogText.equipment(eq), symbol: ExerciseCatalog.equipmentSymbols[eq] ?? "circle", value: eq)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func chip(_ title: String, symbol: String, value: String?) -> some View {
        let active = selection == value
        return Button {
            withAnimation(.snappy) { selection = value }
        } label: {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(active ? Color.accentColor : Color(.secondarySystemGroupedBackground), in: Capsule())
                .foregroundStyle(active ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? .isSelected : [])
    }
}
