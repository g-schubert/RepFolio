import SwiftUI
import SwiftData
import UIKit

/// Shows the exercise like a GIF: start and end position cross-fade in a loop.
/// If you added your own photo of the machine, that photo is shown instead (when `preferCustom`).
struct ExerciseImageView: View {
    let exercise: Exercise
    var customPhoto: Data? = nil
    var preferCustom: Bool = true
    var interval: Double = 1.3
    var cornerRadius: CGFloat = 12

    var body: some View {
        Group {
            if preferCustom, let data = customPhoto, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else if exercise.images.isEmpty {
                ZStack {
                    Color.secondary.opacity(0.15)
                    Image(systemName: "dumbbell").font(.largeTitle).foregroundStyle(.secondary)
                }
            } else {
                TimelineView(.periodic(from: .now, by: interval)) { context in
                    let idx = Int(context.date.timeIntervalSinceReferenceDate / interval) % exercise.images.count
                    ZStack {
                        ForEach(Array(exercise.images.enumerated()), id: \.offset) { i, name in
                            if let img = ExerciseImageStore.image(named: name) {
                                Image(uiImage: img).resizable().scaledToFill()
                                    .opacity(i == idx ? 1 : 0)
                            }
                        }
                    }
                    .animation(.easeInOut(duration: 0.35), value: idx)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityLabel(Text("Bild: \(exercise.name)"))
    }
}

/// Thumbnail that looks up a custom photo for the exercise.
struct ExerciseThumb: View {
    let exerciseId: String
    var size: CGFloat = 64
    @Query private var notes: [ExerciseNote]

    init(exerciseId: String, size: CGFloat = 64) {
        self.exerciseId = exerciseId
        self.size = size
        let id = exerciseId
        _notes = Query(filter: #Predicate<ExerciseNote> { $0.exerciseId == id })
    }

    var body: some View {
        ExerciseImageView(exercise: ExerciseCatalog.shared.exercise(exerciseId),
                          customPhoto: notes.first?.customPhoto, cornerRadius: 10)
            .frame(width: size * 1.4, height: size)
    }
}

struct StatTile: View {
    let title: LocalizedStringKey
    let value: String
    var detail: String? = nil
    var symbol: String
    var tint: Color = .accentColor

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct Card<Content: View>: View {
    let title: LocalizedStringKey
    var symbol: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let symbol {
                Label(title, systemImage: symbol).font(.headline)
            } else {
                Text(title).font(.headline)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// Progress ring (e.g. 2 / 3 workouts this week).
struct GoalRing: View {
    let value: Int
    let goal: Int
    let title: LocalizedStringKey
    let tint: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 10)
                Circle()
                    .trim(from: 0, to: goal > 0 ? min(1, CGFloat(value) / CGFloat(goal)) : 0)
                    .stroke(tint, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text(verbatim: "\(value)/\(goal)").font(.title3.weight(.bold)).monospacedDigit()
                    if value >= goal && goal > 0 {
                        Image(systemName: "checkmark").font(.caption.weight(.bold)).foregroundStyle(tint)
                    }
                }
            }
            .frame(width: 84, height: 84)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Text field for decimals/integers that accepts "62,5" and "62.5" and writes through on every keystroke.
struct NumberField: View {
    let placeholder: String
    @Binding var value: Double
    var decimals: Bool = true
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .keyboardType(decimals ? .decimalPad : .numberPad)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .focused($focused)
            .onAppear { text = Self.format(value, decimals: decimals) }
            .onChange(of: text) { _, new in
                if let v = Fmt.parse(new) { value = decimals ? v : v.rounded() }
                else if new.isEmpty { value = 0 }
            }
            .onChange(of: value) { _, new in
                if !focused { text = Self.format(new, decimals: decimals) }
            }
            .onChange(of: focused) { _, isFocused in
                if isFocused, value == 0 { text = "" }
                if !isFocused { text = Self.format(value, decimals: decimals) }
            }
    }

    static func format(_ v: Double, decimals: Bool) -> String {
        decimals ? Fmt.num(v, digits: 2) : String(Int(v))
    }
}

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

/// Int <-> Double binding helper for NumberField.
extension Binding where Value == Int {
    var asDouble: Binding<Double> {
        Binding<Double>(get: { Double(wrappedValue) }, set: { wrappedValue = Int($0) })
    }
}
