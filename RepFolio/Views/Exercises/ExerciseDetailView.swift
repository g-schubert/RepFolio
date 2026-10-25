import SwiftUI
import SwiftData
import Charts
import PhotosUI
import UIKit

struct ExerciseDetailView: View {
    let exercise: Exercise
    var isSheet: Bool = false
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query private var notes: [ExerciseNote]

    @State private var history: [SessionSets] = []
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showOwnPhoto = false
    @State private var settingsText = ""

    init(exercise: Exercise, isSheet: Bool = false) {
        self.exercise = exercise
        self.isSheet = isSheet
        let id = exercise.id
        _notes = Query(filter: #Predicate<ExerciseNote> { $0.exerciseId == id })
    }

    private var note: ExerciseNote? { notes.first }

    private struct Point: Identifiable {
        let date: Date; let value: Double; let series: String
        var id: String { "\(series)-\(date.timeIntervalSince1970)" }
    }

    private var isEnglish: Bool { AppLanguage.current == .en }
    private var topSeries: String { L("Top-Gewicht") }
    private var ormSeries: String { L("Geschätztes 1RM") }

    private var chartPoints: [Point] {
        history.reversed().flatMap { entry -> [Point] in
            let top = entry.sets.map(\.weightKg).max() ?? 0
            let orm = entry.sets.map(\.estimatedOneRepMax).max() ?? 0
            return [Point(date: entry.date, value: top, series: topSeries),
                    Point(date: entry.date, value: orm, series: ormSeries)]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseImageView(exercise: exercise, customPhoto: note?.customPhoto, preferCustom: showOwnPhoto, cornerRadius: 16)
                    .frame(height: 240)
                    .frame(maxWidth: .infinity)
                if note?.customPhoto != nil {
                    Picker("Bild", selection: $showOwnPhoto) {
                        Text("Anleitung").tag(false)
                        Text("Mein Gerät").tag(true)
                    }
                    .pickerStyle(.segmented)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name).font(.title2.weight(.bold))
                    // The name in the other language helps to recognize labels on the machines.
                    Text(isEnglish ? exercise.nameDE : exercise.nameEN).font(.subheadline).foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Tag(text: exercise.equipmentName, symbol: "wrench.and.screwdriver")
                    Tag(text: exercise.groupName, symbol: ExerciseCatalog.groupSymbols[exercise.group] ?? "circle")
                }

                Card(title: "Muskeln", symbol: "figure.strengthtraining.traditional") {
                    VStack(alignment: .leading, spacing: 6) {
                        LabeledContent("Primär", value: exercise.primaryMusclesText)
                        if !exercise.secondaryMuscles.isEmpty {
                            LabeledContent("Sekundär", value: exercise.secondaryMusclesText)
                        }
                    }
                    .font(.subheadline)
                }

                if !exercise.howTo.isEmpty {
                    Card(title: "So geht's", symbol: "list.number") {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(Array(exercise.howTo.enumerated()), id: \.offset) { i, cue in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(verbatim: "\(i + 1)")
                                        .font(.caption.weight(.bold))
                                        .frame(width: 22, height: 22)
                                        .background(Color.accentColor.opacity(0.15), in: Circle())
                                    Text(cue).font(.subheadline)
                                }
                            }
                            if isEnglish {
                                Text("Bilder & Text: Free Exercise DB (Public Domain)")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Card(title: "Mein Gerät", symbol: "gearshape") {
                    VStack(alignment: .leading, spacing: 10) {
                        TextField("Einstellung, z. B. Sitz 4 · Lehne 2", text: $settingsText)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(saveSettings)
                        HStack {
                            PhotosPicker(selection: $photoItem, matching: .images) {
                                Label("Foto wählen", systemImage: "photo")
                            }
                            .buttonStyle(.bordered)
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button {
                                    showCamera = true
                                } label: {
                                    Label("Foto aufnehmen", systemImage: "camera")
                                }
                                .buttonStyle(.bordered)
                            }
                            if note?.customPhoto != nil {
                                Button(role: .destructive) {
                                    note?.customPhoto = nil
                                    showOwnPhoto = false
                                    try? context.save()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Eigenes Foto löschen")
                            }
                        }
                        Text("Fotografiere das Gerät in deinem Gym – dann erkennst du es sofort wieder.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                progressSection

                // In English the original instructions are already shown above.
                if !isEnglish {
                    DisclosureGroup("Originalanleitung (Englisch)") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(exercise.instructionsEN.enumerated()), id: \.offset) { _, line in
                                Text(line).font(.footnote).foregroundStyle(.secondary)
                            }
                            Text("Bilder & Text: Free Exercise DB (Public Domain)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.top, 6)
                    }
                    .padding(16)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
            }
            .padding()
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isSheet {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fertig") { saveSettings(); dismiss() }
                }
            }
        }
        .task {
            settingsText = note?.machineSettings ?? ""
            showOwnPhoto = note?.customPhoto != nil
            history = History.sessions(for: exercise.id, in: context)
        }
        .onDisappear(perform: saveSettings)
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    storePhoto(data)
                }
                photoItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) { storePhoto(data) }
            }
            .ignoresSafeArea()
        }
    }

    @ViewBuilder
    private var progressSection: some View {
        Card(title: "Fortschritt", symbol: "chart.line.uptrend.xyaxis") {
            if history.isEmpty {
                Text("Noch keine Einträge. Nach deinem ersten Training siehst du hier deine Entwicklung.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                let allSets = history.flatMap { $0.sets }
                let bestORM = allSets.map(\.estimatedOneRepMax).max() ?? 0
                let bestWeight = allSets.map(\.weightKg).max() ?? 0
                HStack {
                    StatTile(title: "Bestes Gewicht", value: Fmt.kg(bestWeight), symbol: "scalemass")
                    StatTile(title: "Geschätztes 1RM", value: Fmt.kg(bestORM), symbol: "trophy", tint: .orange)
                }
                if history.count >= 2 {
                    Chart(chartPoints) { p in
                        LineMark(x: .value("Datum", p.date), y: .value("kg", p.value))
                            .foregroundStyle(by: .value("Serie", p.series))
                            .interpolationMethod(.monotone)
                        PointMark(x: .value("Datum", p.date), y: .value("kg", p.value))
                            .foregroundStyle(by: .value("Serie", p.series))
                            .symbolSize(20)
                    }
                    .chartForegroundStyleScale([topSeries: Color.accentColor, ormSeries: Color.orange])
                    .chartLegend(position: .bottom)
                    .frame(height: 200)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(history.prefix(8))) { entry in
                        HStack(alignment: .firstTextBaseline) {
                            Text(Fmt.day(entry.date)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                            Text(entry.sets.map { "\(Fmt.num($0.weightKg, digits: 2))×\($0.reps)" }.joined(separator: "  "))
                                .font(.caption.monospacedDigit())
                        }
                    }
                }
            }
        }
    }

    private func ensureNote() -> ExerciseNote {
        if let note { return note }
        let n = ExerciseNote(exerciseId: exercise.id)
        context.insert(n)
        return n
    }

    private func saveSettings() {
        let trimmed = settingsText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != (note?.machineSettings ?? "") else { return }
        ensureNote().machineSettings = trimmed
        try? context.save()
    }

    private func storePhoto(_ data: Data) {
        guard let image = UIImage(data: data) else { return }
        let resized = image.resized(maxSide: 1200)
        ensureNote().customPhoto = resized.jpegData(compressionQuality: 0.7)
        showOwnPhoto = true
        try? context.save()
    }
}

struct Tag: View {
    let text: String
    let symbol: String
    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.12), in: Capsule())
    }
}

extension UIImage {
    func resized(maxSide: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxSide else { return self }
        let scale = maxSide / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)
        return UIGraphicsImageRenderer(size: newSize).image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

/// Minimal camera wrapper (UIImagePickerController).
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
