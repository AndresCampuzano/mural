import SwiftUI

/// Mural is black and white: a true black page, dark grey cards, white text, and white as the
/// accent, with black text on it. Colour is left to the content, such as the landmarks. Names
/// describe each colour's role, so `cream` is the page background and `ink` the text on it.
enum MuralColor {
    static let cream = Color(red: 0, green: 0, blue: 0)
    static let ink = Color(red: 1, green: 1, blue: 1)
    static let secondary = Color(white: 0.6)
    static let accent = Color(white: 0.96)
    /// Text and icons on an accent button.
    static let onAccent = Color(red: 0, green: 0, blue: 0)
    /// Cards, fields and controls raised above the page.
    static let surface = Color(white: 0.11)
    /// The highlighted card or chip: a lighter grey that reads as selected beside plain cards.
    static let peach = Color(white: 0.24)
    static let lilac = Color(white: 0.125)
    static let sage = Color(white: 0.115)
    static let butter = Color(white: 0.135)
    /// Icon colours, kept as a list so cards can still vary: white and soft greys.
    static let icons = [Color(white: 1), Color(white: 0.85), Color(white: 0.92), Color(white: 0.78)]
    /// The orb, the figure for a language without a landmark, glows in silver.
    static let glowButter = Color(white: 0.97)
    static let glowPeach = Color(white: 0.88)
    static let glowOrange = Color(white: 0.62)
    static let panels = [peach, lilac, sage, butter]
}

extension View {
    /// Keeps a screen to a phone-like column on iPad, so cards and lines do not stretch edge to edge.
    func readableColumn() -> some View {
        frame(maxWidth: 680).frame(maxWidth: .infinity)
    }
}

struct Brand: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "leaf.fill").font(.system(size: 19, weight: .semibold)).frame(width: 20, height: 20)
            Text("mural").font(.system(size: 30, weight: .bold, design: .rounded)).tracking(-1.6)
        }.foregroundStyle(MuralColor.ink).accessibilityLabel("Mural")
    }
}

struct SoftGlass: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var tint: Color = MuralColor.surface.opacity(0.6)
    func body(content: Content) -> some View {
        if reduceTransparency { content.background(MuralColor.surface, in: Capsule()) }
        else { content.glassEffect(.regular.tint(tint).interactive(), in: .capsule) }
    }
}

struct OrbShape: Shape {
    var phase: Double
    var energy: Double
    func path(in rect: CGRect) -> Path {
        let points = (0..<12).map { index -> CGPoint in
            let a = Double(index) / 12 * .pi * 2
            let wave = sin(a * 3 + phase) * 0.021 + cos(a * 2 - phase * 0.7) * (0.012 + energy * 0.025)
            let radius = min(rect.width, rect.height) * (0.47 + wave)
            return CGPoint(x: rect.midX + cos(a) * radius, y: rect.midY + sin(a) * radius)
        }
        var p = Path()
        for i in 0..<12 {
            let current = points[i], next = points[(i + 1) % 12]
            let midpoint = CGPoint(x: (current.x + next.x) / 2, y: (current.y + next.y) / 2)
            if i == 0 {
                let previous = points[11]
                p.move(to: CGPoint(x: (previous.x + current.x) / 2, y: (previous.y + current.y) / 2))
            }
            p.addQuadCurve(to: midpoint, control: current)
        }
        p.closeSubpath(); return p
    }
}

struct MuralOrb: View {
    var energy: Double = 0
    var listening = false
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion || !active || scenePhase != .active)) { timeline in
            let t = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
            let phase = t * 0.72
            let e = reduceMotion ? 0 : min(1, max(0, energy))
            GeometryReader { geometry in
                let side = min(geometry.size.width, geometry.size.height)
                ZStack {
                    Ellipse().fill(MuralColor.glowOrange.opacity(0.14)).frame(width: side * 0.57, height: side * 0.075)
                        .blur(radius: 10).offset(y: side * 0.47)
                    Circle().stroke(MuralColor.glowOrange.opacity(listening ? 0.18 : 0), lineWidth: 1).padding(-6)
                    Circle().stroke(MuralColor.glowOrange.opacity(listening ? 0.10 : 0), lineWidth: 1).padding(-16)
                    ZStack {
                        MeshGradient(width: 3, height: 3, points: [
                            [0,0], [0.5,0], [1,0],
                            [0,0.5], [Float(0.5 + sin(phase) * 0.08), Float(0.5 + cos(phase) * 0.06)], [1,0.5],
                            [0,1], [0.5,1], [1,1]
                        ], colors: [Color(white: 1), MuralColor.glowButter, MuralColor.glowPeach,
                                    Color(white: 0.8), MuralColor.glowOrange, Color(white: 0.74),
                                    Color(white: 0.45), Color(white: 0.6), Color(white: 0.82)])
                        Ellipse().fill(.white.opacity(0.65)).frame(width: side * 0.48, height: side * 0.15).blur(radius: 13)
                            .rotationEffect(.degrees(-28)).offset(x: -side * 0.17, y: -side * 0.28)
                        Ellipse().stroke(MuralColor.glowButter.opacity(0.48), lineWidth: 16).frame(width: side * 1.2, height: side * 0.5)
                            .blur(radius: 12).rotationEffect(.degrees(-15)).offset(y: side * 0.54)
                    }
                    .mask(OrbShape(phase: phase, energy: e))
                    .shadow(color: MuralColor.glowOrange.opacity(0.12), radius: 16, y: 10)
                    .rotationEffect(.degrees(sin(phase * 0.5) * 3))
                    .scaleEffect(1 + e * 0.045)
                    .offset(y: reduceMotion ? 0 : sin(t * 0.9) * 4 - 5)
                    Circle().fill(RadialGradient(colors: [.white, MuralColor.glowPeach, MuralColor.glowOrange.opacity(0.5)], center: .topLeading, startRadius: 0, endRadius: 12))
                        .frame(width: 12, height: 12).offset(x: side * 0.55, y: -side * 0.24)
                    Circle().fill(MuralColor.glowPeach).frame(width: 7, height: 7).offset(x: -side * 0.54, y: side * 0.26)
                }.frame(width: side, height: side).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }.accessibilityHidden(true)
    }
}

struct PageHeading: View {
    var eyebrow: String
    var title: String
    var subtitle: String = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(eyebrow.uppercased()).font(.system(.caption, design: .rounded, weight: .medium)).tracking(1.5).foregroundStyle(MuralColor.secondary)
            Text(title).font(.system(.largeTitle, design: .rounded, weight: .semibold)).tracking(-1).foregroundStyle(MuralColor.ink)
            if !subtitle.isEmpty { Text(subtitle).font(.subheadline).foregroundStyle(MuralColor.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
