import SwiftUI

/// Hilfsfunktionen für zeitgesteuerte Motion Graphics.
enum Motion {
    /// Fortschritt 0…1 zwischen zwei Zeitpunkten.
    static func progress(_ t: Double, _ start: Double, _ end: Double) -> Double {
        min(max((t - start) / (end - start), 0), 1)
    }

    static func easeInOut(_ x: Double) -> Double {
        x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
    }

    static func easeOut(_ x: Double) -> Double {
        1 - pow(1 - x, 4)
    }

    /// Leichtes Überschwingen am Ende – wirkt „federnd“.
    static func backOut(_ x: Double) -> Double {
        let c1 = 1.70158, c3 = c1 + 1
        return 1 + c3 * pow(x - 1, 3) + c1 * pow(x - 1, 2)
    }

    static func ease(_ t: Double, _ start: Double, _ end: Double) -> Double {
        easeInOut(progress(t, start, end))
    }
}

/// Kino-Intro: Laserlinie → Auto wird Linie für Linie gezeichnet → Lack, Räder, Licht → Schriftzug RideReader.
/// Läuft komplett über die Zeit (TimelineView), daher flüssig mit 120 Hz. Antippen überspringt.
struct IntroView: View {
    var onFinish: () -> Void
    /// Für Screenshots: Intro bei dieser Sekunde anhalten
    var frozenTime: Double?

    @State private var start = Date()
    @State private var finished = false

    static let duration = 4.6

    var body: some View {
        TimelineView(.animation(paused: frozenTime != nil)) { context in
            let t = frozenTime ?? context.date.timeIntervalSince(start)
            scene(t)
                .onChange(of: t >= Self.duration) { done in
                    if done { finish() }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .onAppear { start = Date() }
    }

    private func finish() {
        guard !finished, frozenTime == nil else { return }
        finished = true
        Haptics.tap()
        onFinish()
    }

    @ViewBuilder
    private func scene(_ t: Double) -> some View {
        let outline = Motion.ease(t, 0.35, 1.7)
        let details = Motion.ease(t, 1.0, 1.9)
        let wheels = Motion.backOut(Motion.progress(t, 1.25, 1.75))
        let fill = Motion.ease(t, 1.75, 2.4)
        let lights = Motion.easeOut(Motion.progress(t, 2.05, 2.45))
        // Räder drehen sich schnell ein und laufen aus
        let spin = 900 * Motion.easeOut(Motion.progress(t, 1.25, 3.2))
        let push = Motion.ease(t, 1.8, 4.2)
        let exit = Motion.ease(t, 3.95, Self.duration)

        GeometryReader { geo in
            let w = geo.size.width
            ZStack {
                ZStack {
                    Color.black
                    // Studio-Licht hinter dem Auto
                    RadialGradient(colors: [Theme.accent.opacity(0.22 * fill), .clear],
                                   center: .center, startRadius: 0, endRadius: w)
                        .offset(y: -40)
                    GridFloor().opacity(Motion.ease(t, 0.2, 1.2))
                }

                // Laserlinie (Boden), wächst aus der Mitte
                let laser = Motion.easeOut(Motion.progress(t, 0.05, 0.6))
                Capsule()
                    .fill(LinearGradient(colors: [.clear, Theme.accent, .white, Theme.accent, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: w * 1.1 * laser, height: 1.6)
                    .shadow(color: Theme.accent, radius: 8)
                    .offset(y: carGroundY(w))
                    .opacity(1 - fill * 0.6)

                // Geschwindigkeitslinien
                SpeedLines(t: t)
                    .opacity(Motion.progress(t, 1.9, 2.3) * (1 - Motion.progress(t, 3.6, 4.1)))

                CarArtwork(outline: outline, details: details, fill: fill, wheels: wheels,
                           wheelRotation: .degrees(spin), lights: lights, tint: Theme.accent)
                    .frame(width: w * 0.92)
                    .scaleEffect(0.88 + 0.12 * push)
                    .offset(x: -14 * (1 - push), y: -30)
                    .rotation3DEffect(.degrees(8 * (1 - push)), axis: (x: 0, y: 1, z: 0), perspective: 0.6)

                // Scheinwerfer-Blitz über das ganze Bild
                Circle()
                    .fill(RadialGradient(colors: [.white.opacity(0.55), Theme.accent.opacity(0.2), .clear],
                                         center: .center, startRadius: 0, endRadius: w * 0.6))
                    .frame(width: w * 1.2, height: w * 1.2)
                    .offset(x: w * 0.42, y: -40)
                    .blendMode(.screen)
                    .opacity(flash(t))

                VStack(spacing: 14) {
                    Spacer()
                    Wordmark(t: t - 2.25, size: min(w * 0.115, 48))
                    Text("Dein Auto spricht. Wir übersetzen.")
                        .font(Theme.rounded(15, weight: .medium))
                        .foregroundStyle(.white.opacity(0.7))
                        .opacity(Motion.ease(t, 3.1, 3.6))
                        .blur(radius: 8 * (1 - Motion.ease(t, 3.1, 3.6)))
                        .offset(y: 8 * (1 - Motion.ease(t, 3.1, 3.6)))
                    Spacer().frame(height: geo.size.height * 0.16)
                }

                // Kinobalken
                VStack {
                    Rectangle().fill(.black).frame(height: 70 * (1 - Motion.ease(t, 3.4, 4.2)))
                    Spacer()
                    Rectangle().fill(.black).frame(height: 70 * (1 - Motion.ease(t, 3.4, 4.2)))
                }

                // Vignette
                RadialGradient(colors: [.clear, .black.opacity(0.7)], center: .center,
                               startRadius: w * 0.45, endRadius: w * 1.25)
                    .allowsHitTesting(false)

                VStack {
                    Spacer()
                    Text("Tippen zum Überspringen")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.white.opacity(0.3))
                        .padding(.bottom, 24)
                        .opacity(Motion.ease(t, 0.8, 1.4) * (1 - exit))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .scaleEffect(1 + 0.08 * exit)
            .blur(radius: 24 * exit)
            .opacity(1 - exit)
        }
        .ignoresSafeArea()
    }

    private func carGroundY(_ width: CGFloat) -> CGFloat {
        // Unterkante der Räder relativ zur Bildmitte
        width * 0.92 * (350 - 170) / 1000 - 30
    }

    /// Kurzer heller Blitz, wenn die Scheinwerfer angehen.
    private func flash(_ t: Double) -> Double {
        let up = Motion.progress(t, 2.05, 2.18)
        let down = Motion.progress(t, 2.18, 2.8)
        return up * (1 - Motion.easeOut(down))
    }
}

/// Der Schriftzug: Buchstaben fliegen gestaffelt aus der Unschärfe ein, danach läuft ein Lichtreflex darüber.
struct Wordmark: View {
    /// Zeit seit Beginn der Schrift-Animation (negativ = noch unsichtbar)
    var t: Double
    var size: CGFloat = 44

    private let letters = Array("RIDEREADER")

    var body: some View {
        let sheen = Motion.progress(t, 0.9, 1.7)
        HStack(spacing: size * 0.02) {
            ForEach(letters.indices, id: \.self) { i in
                let p = Motion.progress(t, Double(i) * 0.05, Double(i) * 0.05 + 0.5)
                let e = Motion.backOut(p)
                Text(String(letters[i]))
                    .font(Theme.display(size))
                    .italic()
                    .foregroundStyle(i < 4 ? AnyShapeStyle(Color.white)
                                     : AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.accentDeep],
                                                                    startPoint: .top, endPoint: .bottom)))
                    .opacity(Motion.easeOut(p))
                    .blur(radius: 10 * (1 - p))
                    .offset(y: 26 * (1 - e))
                    .scaleEffect(0.6 + 0.4 * e)
            }
        }
        .fixedSize()
        .overlay(
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.3)
                    .offset(x: -geo.size.width * 0.3 + geo.size.width * 1.6 * sheen)
                    .blendMode(.overlay)
            }
            .mask(
                HStack(spacing: size * 0.02) {
                    ForEach(letters.indices, id: \.self) { i in
                        Text(String(letters[i])).font(Theme.display(size)).italic()
                    }
                }
                .fixedSize()
            )
            .opacity(sheen > 0 && sheen < 1 ? 1 : 0)
        )
        .shadow(color: Theme.accent.opacity(0.45), radius: 18)
    }
}

/// Horizontale Lichtstreifen, die am Auto vorbeiziehen.
struct SpeedLines: View {
    var t: Double

    var body: some View {
        Canvas { context, size in
            for i in 0..<18 {
                let seed = Double(i) * 37.13
                let y = size.height * (0.3 + 0.4 * fract(sin(seed) * 43758.5))
                let speed = 900 + 700 * fract(seed * 0.618)
                let length = 60 + 140 * fract(seed * 1.37)
                let x = size.width + length - CGFloat(fmod(t * speed + seed * 50, Double(size.width + length * 2)))
                var line = Path()
                line.move(to: CGPoint(x: x, y: y))
                line.addLine(to: CGPoint(x: x + length, y: y))
                context.stroke(line, with: .linearGradient(
                    Gradient(colors: [Theme.accent.opacity(0.0), Theme.accent.opacity(0.6)]),
                    startPoint: CGPoint(x: x + length, y: y), endPoint: CGPoint(x: x, y: y)),
                               lineWidth: i % 3 == 0 ? 1.6 : 0.8)
            }
        }
        .allowsHitTesting(false)
    }

    private func fract(_ x: Double) -> Double { x - floor(x) }
}
