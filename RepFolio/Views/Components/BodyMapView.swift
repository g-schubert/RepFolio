import SwiftUI

/// Stylized front + back figure; every Free Exercise DB muscle key is a region that can be tinted.
/// Drawn in a 100 × 200 unit space per side and scaled to fit.
struct BodyMapView: View {
    /// Tint per muscle key; muscles without an entry stay neutral.
    let colors: [String: Color]
    var showLabels: Bool = true

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            side(.front, label: "Vorne")
            side(.back, label: "Hinten")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(colors.keys.sorted().map(Muscle.name).joined(separator: ", ")))
    }

    private func side(_ side: BodySide, label: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Canvas { ctx, size in
                let scale = min(size.width / 100, size.height / 200)
                let offset = CGPoint(x: (size.width - 100 * scale) / 2, y: (size.height - 200 * scale) / 2)
                func shape(_ r: BodyRect) -> Path {
                    let rect = CGRect(x: offset.x + r.rect.minX * scale, y: offset.y + r.rect.minY * scale,
                                      width: r.rect.width * scale, height: r.rect.height * scale)
                    return Path(roundedRect: rect, cornerRadius: min(rect.width, rect.height) * r.roundness)
                }
                // One path → overlapping body parts don't stack up their transparency.
                let body = Path { p in BodyGeometry.silhouette.forEach { p.addPath(shape($0)) } }
                ctx.fill(body, with: .color(.secondary.opacity(0.14)))
                for region in BodyGeometry.regions where region.side == side {
                    let fill = colors[region.muscle] ?? Color.secondary.opacity(0.22)
                    for r in region.rects { ctx.fill(shape(r), with: .color(fill)) }
                }
            }
            .aspectRatio(0.5, contentMode: .fit)
            if showLabels {
                Text(label).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

enum BodySide { case front, back }

struct BodyRect {
    let rect: CGRect
    /// 0 = square corners, 0.5 = capsule / circle.
    var roundness: CGFloat = 0.45

    init(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, roundness: CGFloat = 0.45) {
        rect = CGRect(x: x, y: y, width: w, height: h)
        self.roundness = roundness
    }
}

struct BodyRegion {
    let muscle: String
    let side: BodySide
    let rects: [BodyRect]
}

enum BodyGeometry {
    /// Neutral body underneath the muscles (identical front and back).
    static let silhouette: [BodyRect] = [
        BodyRect(41, 3, 18, 22, roundness: 0.5),          // head
        BodyRect(45, 22, 10, 10, roundness: 0.2),         // neck
        BodyRect(30, 28, 40, 60, roundness: 0.22),        // torso
        BodyRect(32, 82, 36, 18, roundness: 0.3),         // hips
        BodyRect(19, 33, 13, 38),                         // upper arms
        BodyRect(68, 33, 13, 38),
        BodyRect(15, 67, 12, 30),                         // forearms
        BodyRect(73, 67, 12, 30),
        BodyRect(14, 95, 10, 11, roundness: 0.5),         // hands
        BodyRect(76, 95, 10, 11, roundness: 0.5),
        BodyRect(32, 94, 17, 54),                         // thighs
        BodyRect(51, 94, 17, 54),
        BodyRect(34, 145, 13, 45),                        // shins
        BodyRect(53, 145, 13, 45),
        BodyRect(32, 186, 15, 9, roundness: 0.5),         // feet
        BodyRect(53, 186, 15, 9, roundness: 0.5),
    ]

    static let regions: [BodyRegion] = [
        // Front
        BodyRegion(muscle: "neck", side: .front, rects: [BodyRect(46, 24, 8, 7, roundness: 0.3)]),
        BodyRegion(muscle: "shoulders", side: .front, rects: [BodyRect(21, 29, 15, 15, roundness: 0.5),
                                                              BodyRect(64, 29, 15, 15, roundness: 0.5)]),
        BodyRegion(muscle: "chest", side: .front, rects: [BodyRect(33, 32, 16, 15, roundness: 0.35),
                                                          BodyRect(51, 32, 16, 15, roundness: 0.35)]),
        BodyRegion(muscle: "abdominals", side: .front, rects: [BodyRect(40, 49, 20, 33, roundness: 0.3)]),
        BodyRegion(muscle: "biceps", side: .front, rects: [BodyRect(21, 45, 9, 21), BodyRect(70, 45, 9, 21)]),
        BodyRegion(muscle: "forearms", side: .front, rects: [BodyRect(16, 69, 9, 25), BodyRect(75, 69, 9, 25)]),
        BodyRegion(muscle: "abductors", side: .front, rects: [BodyRect(31, 84, 6, 15), BodyRect(63, 84, 6, 15)]),
        BodyRegion(muscle: "quadriceps", side: .front, rects: [BodyRect(34, 98, 12, 44), BodyRect(54, 98, 12, 44)]),
        BodyRegion(muscle: "adductors", side: .front, rects: [BodyRect(45, 99, 4, 26), BodyRect(51, 99, 4, 26)]),
        BodyRegion(muscle: "calves", side: .front, rects: [BodyRect(36, 150, 9, 32), BodyRect(55, 150, 9, 32)]),
        // Back
        BodyRegion(muscle: "traps", side: .back, rects: [BodyRect(37, 25, 26, 15, roundness: 0.4)]),
        BodyRegion(muscle: "shoulders", side: .back, rects: [BodyRect(21, 29, 15, 15, roundness: 0.5),
                                                             BodyRect(64, 29, 15, 15, roundness: 0.5)]),
        BodyRegion(muscle: "middle back", side: .back, rects: [BodyRect(43, 41, 14, 21, roundness: 0.3)]),
        BodyRegion(muscle: "lats", side: .back, rects: [BodyRect(31, 42, 11, 28, roundness: 0.4),
                                                        BodyRect(58, 42, 11, 28, roundness: 0.4)]),
        BodyRegion(muscle: "lower back", side: .back, rects: [BodyRect(40, 64, 20, 18, roundness: 0.3)]),
        BodyRegion(muscle: "triceps", side: .back, rects: [BodyRect(21, 44, 9, 23), BodyRect(70, 44, 9, 23)]),
        BodyRegion(muscle: "forearms", side: .back, rects: [BodyRect(16, 69, 9, 25), BodyRect(75, 69, 9, 25)]),
        BodyRegion(muscle: "glutes", side: .back, rects: [BodyRect(33, 84, 16, 17, roundness: 0.45),
                                                          BodyRect(51, 84, 16, 17, roundness: 0.45)]),
        BodyRegion(muscle: "hamstrings", side: .back, rects: [BodyRect(34, 104, 13, 40), BodyRect(53, 104, 13, 40)]),
        BodyRegion(muscle: "calves", side: .back, rects: [BodyRect(35, 148, 11, 30, roundness: 0.5),
                                                          BodyRect(54, 148, 11, 30, roundness: 0.5)]),
    ]

    static let muscles: [String] = Array(Set(regions.map(\.muscle))).sorted()
}

/// Small colored dot + text, used as map legend.
struct LegendDot: View {
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
