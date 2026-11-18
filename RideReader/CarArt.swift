import SwiftUI

/// Seitenansicht eines sportlichen Coupés als Vektorgrafik, entworfen in einem 1000 × 340-Raster.
/// Alle Teile sind eigene Shapes, damit sie einzeln „gezeichnet“ (trim), gefüllt und beleuchtet werden können.
enum CarGeometry {
    static let size = CGSize(width: 1000, height: 340)
    static let rearWheel = CGPoint(x: 232, y: 290)
    static let frontWheel = CGPoint(x: 768, y: 290)
    static let wheelRadius: CGFloat = 60
    static let headlight = CGPoint(x: 948, y: 196)
    static let taillight = CGPoint(x: 62, y: 186)

    /// Rechnet einen Rasterpunkt in das Zielrechteck um (Seitenverhältnis bleibt erhalten).
    static func mapper(for rect: CGRect) -> (CGPoint) -> CGPoint {
        let scale = min(rect.width / size.width, rect.height / size.height)
        let dx = rect.midX - size.width * scale / 2
        let dy = rect.midY - size.height * scale / 2
        return { CGPoint(x: dx + $0.x * scale, y: dy + $0.y * scale) }
    }

    static func scale(for rect: CGRect) -> CGFloat {
        min(rect.width / size.width, rect.height / size.height)
    }

    /// Radlauf als Bogen über dem Rad (von links nach rechts über die Oberseite).
    static func arch(_ path: inout Path, around center: CGPoint, radius: CGFloat, map: (CGPoint) -> CGPoint) {
        let steps = 24
        for i in 0...steps {
            let angle = Double.pi + Double.pi * Double(i) / Double(steps)
            path.addLine(to: map(CGPoint(x: center.x + radius * cos(angle), y: center.y + radius * sin(angle) - 4)))
        }
    }
}

/// Außenkontur der Karosserie.
struct CarBodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let m = CarGeometry.mapper(for: rect)
        var p = Path()
        p.move(to: m(CGPoint(x: 150, y: 282)))
        CarGeometry.arch(&p, around: CarGeometry.rearWheel, radius: 74, map: m)
        p.addLine(to: m(CGPoint(x: 694, y: 280)))
        CarGeometry.arch(&p, around: CarGeometry.frontWheel, radius: 74, map: m)
        p.addLine(to: m(CGPoint(x: 950, y: 278)))
        p.addQuadCurve(to: m(CGPoint(x: 988, y: 240)), control: m(CGPoint(x: 984, y: 274)))
        p.addQuadCurve(to: m(CGPoint(x: 968, y: 196)), control: m(CGPoint(x: 992, y: 210)))
        p.addQuadCurve(to: m(CGPoint(x: 900, y: 172)), control: m(CGPoint(x: 950, y: 178)))
        p.addCurve(to: m(CGPoint(x: 640, y: 148)), control1: m(CGPoint(x: 820, y: 160)), control2: m(CGPoint(x: 700, y: 150)))
        p.addCurve(to: m(CGPoint(x: 470, y: 76)), control1: m(CGPoint(x: 580, y: 120)), control2: m(CGPoint(x: 530, y: 82)))
        p.addCurve(to: m(CGPoint(x: 300, y: 86)), control1: m(CGPoint(x: 410, y: 70)), control2: m(CGPoint(x: 350, y: 74)))
        p.addCurve(to: m(CGPoint(x: 120, y: 150)), control1: m(CGPoint(x: 230, y: 104)), control2: m(CGPoint(x: 170, y: 140)))
        p.addQuadCurve(to: m(CGPoint(x: 44, y: 172)), control: m(CGPoint(x: 70, y: 156)))
        p.addQuadCurve(to: m(CGPoint(x: 30, y: 236)), control: m(CGPoint(x: 26, y: 196)))
        p.addQuadCurve(to: m(CGPoint(x: 150, y: 282)), control: m(CGPoint(x: 40, y: 280)))
        p.closeSubpath()
        return p
    }
}

/// Seitenfenster mit B-Säule.
struct CarWindowShape: Shape {
    func path(in rect: CGRect) -> Path {
        let m = CarGeometry.mapper(for: rect)
        var p = Path()
        p.move(to: m(CGPoint(x: 612, y: 152)))
        p.addCurve(to: m(CGPoint(x: 466, y: 92)), control1: m(CGPoint(x: 560, y: 124)), control2: m(CGPoint(x: 520, y: 96)))
        p.addCurve(to: m(CGPoint(x: 320, y: 100)), control1: m(CGPoint(x: 410, y: 88)), control2: m(CGPoint(x: 360, y: 90)))
        p.addCurve(to: m(CGPoint(x: 214, y: 154)), control1: m(CGPoint(x: 270, y: 116)), control2: m(CGPoint(x: 236, y: 140)))
        p.closeSubpath()
        return p
    }
}

/// Linien: Schulterlinie, Türfugen, B-Säule, Schweller.
struct CarDetailShape: Shape {
    func path(in rect: CGRect) -> Path {
        let m = CarGeometry.mapper(for: rect)
        var p = Path()
        // Schulter-/Sicke
        p.move(to: m(CGPoint(x: 930, y: 200)))
        p.addCurve(to: m(CGPoint(x: 70, y: 190)), control1: m(CGPoint(x: 700, y: 182)), control2: m(CGPoint(x: 300, y: 178)))
        // B-Säule
        p.move(to: m(CGPoint(x: 420, y: 90)))
        p.addLine(to: m(CGPoint(x: 412, y: 154)))
        // Türfugen
        p.move(to: m(CGPoint(x: 612, y: 152)))
        p.addQuadCurve(to: m(CGPoint(x: 640, y: 268)), control: m(CGPoint(x: 650, y: 200)))
        p.move(to: m(CGPoint(x: 412, y: 154)))
        p.addLine(to: m(CGPoint(x: 410, y: 270)))
        // Schweller
        p.move(to: m(CGPoint(x: 318, y: 262)))
        p.addLine(to: m(CGPoint(x: 680, y: 262)))
        // Türgriffe
        p.move(to: m(CGPoint(x: 560, y: 196)))
        p.addLine(to: m(CGPoint(x: 590, y: 195)))
        p.move(to: m(CGPoint(x: 360, y: 197)))
        p.addLine(to: m(CGPoint(x: 390, y: 196)))
        // Scheinwerfer- und Rückleuchtenkontur
        p.move(to: m(CGPoint(x: 970, y: 200)))
        p.addQuadCurve(to: m(CGPoint(x: 900, y: 186)), control: m(CGPoint(x: 940, y: 182)))
        p.move(to: m(CGPoint(x: 44, y: 178)))
        p.addQuadCurve(to: m(CGPoint(x: 110, y: 180)), control: m(CGPoint(x: 80, y: 170)))
        return p
    }
}

/// Felge mit fünf Speichen; `rotation` dreht sie.
struct WheelView: View {
    var rotation: Angle
    var tint: Color

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.05))
            Circle().strokeBorder(Color(white: 0.16), lineWidth: 4)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.55), Color(white: 0.18)], center: .center, startRadius: 2, endRadius: 40))
                .padding(14)
            ForEach(0..<5) { i in
                Capsule()
                    .fill(LinearGradient(colors: [Color(white: 0.8), Color(white: 0.35)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 7, height: 34)
                    .offset(y: -17)
                    .rotationEffect(.degrees(Double(i) * 72))
            }
            .rotationEffect(rotation)
            Circle().fill(Color(white: 0.12)).frame(width: 14, height: 14)
            Circle()
                .strokeBorder(tint.opacity(0.55), lineWidth: 1.2)
                .padding(13)
        }
    }
}

/// Das komplette Auto. Alle Werte 0…1, damit Intro und Startseite es animieren können.
struct CarArtwork: View {
    /// wie weit die Kontur gezeichnet ist
    var outline: Double = 1
    /// wie weit Fenster und Linien gezeichnet sind
    var details: Double = 1
    /// Füllung der Karosserie
    var fill: Double = 1
    /// Räder sichtbar (Skalierung)
    var wheels: Double = 1
    var wheelRotation: Angle = .zero
    /// Scheinwerfer-Leuchten
    var lights: Double = 1
    /// Kantenlicht-Farbe (Zustand)
    var tint: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            let m = CarGeometry.mapper(for: rect)
            let s = CarGeometry.scale(for: rect)
            ZStack {
                // Bodenschatten
                Ellipse()
                    .fill(RadialGradient(colors: [.black.opacity(0.75), .clear], center: .center, startRadius: 0, endRadius: 420 * s))
                    .frame(width: 940 * s, height: 70 * s)
                    .position(m(CGPoint(x: 500, y: 350)))
                    .opacity(fill)

                // Lichtreflex am Boden
                Ellipse()
                    .fill(tint.opacity(0.35))
                    .frame(width: 700 * s, height: 26 * s)
                    .blur(radius: 18 * s)
                    .position(m(CGPoint(x: 500, y: 352)))
                    .opacity(fill * 0.8)

                // Karosserie-Füllung (dunkler Lack mit Kantenlicht)
                CarBodyShape()
                    .fill(LinearGradient(stops: [
                        .init(color: Color(white: 0.2), location: 0),
                        .init(color: Color(white: 0.07), location: 0.45),
                        .init(color: Color(white: 0.03), location: 1),
                    ], startPoint: .top, endPoint: .bottom))
                    .overlay(
                        CarBodyShape()
                            .fill(LinearGradient(colors: [tint.opacity(0.0), tint.opacity(0.22), tint.opacity(0.0)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .blendMode(.screen)
                    )
                    .opacity(fill)

                CarWindowShape()
                    .fill(LinearGradient(colors: [Color(white: 0.28).opacity(0.9), Color(white: 0.02)], startPoint: .top, endPoint: .bottom))
                    .opacity(fill)

                // Konturen
                CarBodyShape()
                    .trim(from: 0, to: outline)
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .shadow(color: tint, radius: 6)
                    .shadow(color: tint.opacity(0.6), radius: 16)
                    .opacity(1 - fill * 0.45)

                ZStack {
                    CarWindowShape()
                        .trim(from: 0, to: details)
                        .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                    CarDetailShape()
                        .trim(from: 0, to: details)
                        .stroke(tint.opacity(0.85), style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))
                }
                .shadow(color: tint.opacity(0.7), radius: 5)
                .opacity(1 - fill * 0.55)

                // Räder
                ForEach([CarGeometry.rearWheel, CarGeometry.frontWheel], id: \.x) { center in
                    WheelView(rotation: wheelRotation, tint: tint)
                        .frame(width: CarGeometry.wheelRadius * 2 * s, height: CarGeometry.wheelRadius * 2 * s)
                        .scaleEffect(wheels)
                        .opacity(wheels)
                        .position(m(center))
                }

                // Scheinwerfer: Kern + Strahl
                ZStack {
                    Capsule()
                        .fill(Color.white)
                        .frame(width: 46 * s, height: 9 * s)
                        .shadow(color: .white, radius: 4)
                    Ellipse()
                        .fill(RadialGradient(colors: [Color.white.opacity(0.9), tint.opacity(0.35), .clear],
                                             center: .center, startRadius: 0, endRadius: 120 * s))
                        .frame(width: 240 * s, height: 70 * s)
                        .blendMode(.screen)
                    // Lichtstreifen (Anamorph-Flare)
                    Capsule()
                        .fill(LinearGradient(colors: [.clear, tint.opacity(0.85), .white, tint.opacity(0.85), .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(width: 520 * s * lights, height: 2.5 * s)
                        .blur(radius: 0.6)
                        .blendMode(.screen)
                }
                .position(m(CarGeometry.headlight))
                .opacity(lights)

                // Rückleuchte
                Capsule()
                    .fill(Color(red: 1, green: 0.15, blue: 0.2))
                    .frame(width: 56 * s, height: 8 * s)
                    .shadow(color: .red, radius: 8)
                    .position(m(CarGeometry.taillight))
                    .opacity(lights * 0.9)
            }
        }
        .aspectRatio(CarGeometry.size.width / CarGeometry.size.height, contentMode: .fit)
    }
}
