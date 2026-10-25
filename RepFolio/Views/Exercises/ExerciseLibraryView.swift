import SwiftUI
import SwiftData

struct ExerciseLibraryView: View {
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(ExerciseCatalog.shared.grouped(matching: search)) { group in
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
