import SwiftUI

/// Plate math for barbell exercises: which plates go on each side of the bar.
enum Plates {
    /// Standard Olympic bar.
    static let barKg: Double = 20
    /// Plates found in most gyms, heaviest first.
    static let available: [Double] = [25, 20, 15, 10, 5, 2.5, 1.25]

    struct Load {
        let perSide: [Double]
        /// Weight that can't be built from the available plates (0 when exact).
        let remainder: Double
    }

    /// Greedy split of `total` into plates per side. Nil if the weight is not above the bar.
    static func load(total: Double, bar: Double = barKg) -> Load? {
        guard total > bar else { return nil }
        var side = (total - bar) / 2
        var plates: [Double] = []
        for plate in available {
            while side + 0.001 >= plate {
                plates.append(plate)
                side -= plate
            }
        }
        return Load(perSide: plates, remainder: max(0, side * 2))
    }

    /// Only free barbell exercises get plate math (machines have their own stacks).
    static func applies(to exercise: Exercise) -> Bool {
        exercise.equipment == "Langhantel"
    }

    /// Competition colors, so the picture matches the plates in the gym.
    static func color(_ plate: Double) -> Color {
        switch plate {
        case 25: .red
        case 20: .blue
        case 15: .yellow
        case 10: .green
        case 5: Color(.systemGray5)
        case 2.5: .red
        default: Color(.systemGray2)
        }
    }

    /// Relative plate height (25 kg = 1).
    static func height(_ plate: Double) -> CGFloat {
        switch plate {
        case 15...: 1
        case 10: 0.82
        case 5: 0.62
        case 2.5: 0.5
        default: 0.42
        }
    }
}

/// One side of the bar, drawn with the plates in their colors.
struct PlateLoadView: View {
    let weight: Double

    var body: some View {
        if let load = Plates.load(total: weight) {
            HStack(spacing: 10) {
                HStack(spacing: 2) {
                    RoundedRectangle(cornerRadius: 1).fill(Color(.systemGray3)).frame(width: 18, height: 6)
                    ForEach(Array(load.perSide.enumerated()), id: \.offset) { _, plate in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Plates.color(plate))
                            .overlay(RoundedRectangle(cornerRadius: 2).stroke(.primary.opacity(0.2), lineWidth: 0.5))
                            .frame(width: plate >= 10 ? 7 : 5, height: 30 * Plates.height(plate))
                    }
                    RoundedRectangle(cornerRadius: 1).fill(Color(.systemGray3)).frame(width: 8, height: 6)
                }
                .frame(height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Pro Seite: \(load.perSide.map { Fmt.num($0, digits: 2) }.joined(separator: " + ")) kg")
                        .font(.caption.weight(.medium))
                    Text(load.remainder > 0
                         ? L("Stange \(Fmt.kg(Plates.barKg)) · \(Fmt.kg(load.remainder)) nicht steckbar")
                         : L("Stange \(Fmt.kg(Plates.barKg))"))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
}
