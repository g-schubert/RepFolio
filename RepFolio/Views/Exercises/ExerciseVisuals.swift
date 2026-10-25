import SwiftUI
import UIKit

/// Large exercise picture with controls: play/pause the loop, jump to start or end position, tap for fullscreen.
struct ExerciseMediaViewer: View {
    let exercise: Exercise
    let customPhoto: Data?
    let showOwnPhoto: Bool

    @State private var playing = true
    @State private var frame = 0
    @State private var fullscreen = false

    private var hasFrames: Bool { !showOwnPhoto && exercise.images.count >= 2 }

    var body: some View {
        VStack(spacing: 10) {
            Button {
                fullscreen = true
            } label: {
                picture(contentMode: .fit)
                    .aspectRatio(3 / 2, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.caption.weight(.semibold))
                            .padding(7)
                            .background(.ultraThinMaterial, in: Circle())
                            .padding(8)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Vollbild"))

            if hasFrames {
                HStack(spacing: 10) {
                    Button {
                        playing.toggle()
                    } label: {
                        Image(systemName: playing ? "pause.fill" : "play.fill")
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel(playing ? Text("Animation anhalten") : Text("Animation abspielen"))
                    Picker("Position", selection: Binding(get: { frame }, set: { frame = $0; playing = false })) {
                        ForEach(exercise.images.indices, id: \.self) { i in
                            Text(Self.frameLabel(i, count: exercise.images.count)).tag(i)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
        }
        .fullScreenCover(isPresented: $fullscreen) {
            ZoomableView {
                picture(contentMode: .fit)
            } onClose: {
                fullscreen = false
            }
        }
    }

    private func picture(contentMode: ContentMode) -> some View {
        ExerciseImageView(exercise: exercise, customPhoto: customPhoto, preferCustom: showOwnPhoto,
                          cornerRadius: 16, fixedFrame: playing ? nil : frame, contentMode: contentMode)
    }

    static func frameLabel(_ index: Int, count: Int) -> String {
        if index == 0 { return L("Start") }
        if index == count - 1 { return L("Ende") }
        return L("Phase \(index + 1)")
    }
}

/// Black fullscreen container with pinch-to-zoom, drag and double-tap.
struct ZoomableView<Content: View>: View {
    @ViewBuilder var content: Content
    let onClose: () -> Void

    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            content
                .scaleEffect(scale)
                .offset(offset)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    MagnifyGesture()
                        .onChanged { scale = max(1, min(5, lastScale * $0.magnification)) }
                        .onEnded { _ in
                            lastScale = scale
                            if scale == 1 { reset() }
                        }
                        .simultaneously(with: DragGesture()
                            .onChanged { v in
                                guard scale > 1 else { return }
                                offset = CGSize(width: lastOffset.width + v.translation.width,
                                                height: lastOffset.height + v.translation.height)
                            }
                            .onEnded { _ in lastOffset = offset })
                )
                .onTapGesture(count: 2) {
                    withAnimation(.spring) {
                        if scale > 1 { reset() } else { scale = 2.5; lastScale = 2.5 }
                    }
                }
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.18), in: Circle())
            }
            .padding()
            .accessibilityLabel("Schließen")
        }
    }

    private func reset() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
    }
}

/// Body map + text for the muscles of one exercise.
struct ExerciseMuscleCard: View {
    let exercise: Exercise

    private var colors: [String: Color] {
        var c: [String: Color] = [:]
        for m in exercise.secondaryMuscles { c[m] = Color.chartGym.opacity(0.4) }
        for m in exercise.primaryMuscles { c[m] = Color.chartGym }
        return c
    }

    var body: some View {
        Card(title: "Muskeln", symbol: "figure.strengthtraining.traditional") {
            HStack(alignment: .center, spacing: 16) {
                BodyMapView(colors: colors)
                    .frame(width: 160, height: 175)
                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        LegendDot(color: .chartGym, text: "Primär")
                        Text(exercise.primaryMusclesText).font(.subheadline)
                    }
                    if !exercise.secondaryMuscles.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            LegendDot(color: Color.chartGym.opacity(0.4), text: "Sekundär")
                            Text(exercise.secondaryMusclesText).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Best weight per rep count – only entries that no heavier set with more reps beats.
struct RepRecordsCard: View {
    let history: [SessionSets]

    struct Row: Identifiable {
        let reps: Int; let weight: Double; let date: Date
        var id: Int { reps }
    }

    static func rows(_ history: [SessionSets]) -> [Row] {
        var best: [Int: Row] = [:]
        for entry in history {
            for set in entry.sets where set.reps > 0 && set.weightKg > 0 {
                if let old = best[set.reps], old.weight >= set.weightKg { continue }
                best[set.reps] = Row(reps: set.reps, weight: set.weightKg, date: entry.date)
            }
        }
        let sorted = best.values.sorted { $0.reps < $1.reps }
        return sorted.filter { row in !sorted.contains { $0.reps > row.reps && $0.weight >= row.weight } }
    }

    var body: some View {
        let rows = Self.rows(history)
        if !rows.isEmpty {
            Card(title: "Bestleistungen", symbol: "trophy") {
                VStack(spacing: 8) {
                    ForEach(rows.prefix(8)) { row in
                        HStack {
                            Text("\(row.reps) Wdh.").font(.subheadline.weight(.semibold)).frame(width: 70, alignment: .leading)
                            Text(Fmt.kg(row.weight)).font(.subheadline.monospacedDigit())
                            Spacer()
                            Text(Fmt.day(row.date)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Text("Schwerstes Gewicht je Wiederholungszahl. Wird automatisch neu berechnet, wenn du alte Trainings korrigierst.")
                        .font(.caption2).foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}
