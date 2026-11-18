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

    /// Sehr weiches Auslaufen – typisch für Marken-Animationen.
    static func expoOut(_ x: Double) -> Double {
        x >= 1 ? 1 : 1 - pow(2, -10 * x)
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

/// Marken-Intro:
/// 1. Ein Lichtfaden zieht sich auf, die Buchstaben steigen dahinter hervor (mit chromatischem Versatz)
/// 2. Kurzes Einatmen – dann der **Durchbruch**: Blitz, Schockwellen, Glassplitter, Risse, der Schriftzug springt nach vorn
///    und erblüht im Markenverlauf
/// 3. Der Hintergrund wird durchsichtig, die Startseite baut sich darunter auf, während der Schriftzug
///    obenauf bleibt und in den Kopf der Startseite gleitet.
/// Läuft komplett über die Zeit (TimelineView) – flüssig mit 120 Hz. Antippen überspringt.
struct IntroView: View {
    /// Wird aufgerufen, sobald die Startseite darunter sichtbar werden soll
    var onReveal: () -> Void = {}
    var onFinish: () -> Void
    /// Für Screenshots: Intro bei dieser Sekunde anhalten
    var frozenTime: Double?

    @State private var start = Date()
    @State private var revealed = false
    @State private var finished = false

    static let impact = 1.5
    static let revealStart = 2.9
    static let duration = 4.15
    /// Größe des Schriftzugs im Kopf der Startseite und dessen Mittelpunkt (ab sicherem Bereich oben)
    static let headerLogoSize: CGFloat = 22
    static let headerLogoCenterY: CGFloat = 8 + 16

    var body: some View {
        TimelineView(.animation(paused: frozenTime != nil)) { context in
            let t = frozenTime ?? context.date.timeIntervalSince(start)
            scene(t)
                .onChange(of: t >= Self.impact) { hit in
                    if hit && frozenTime == nil { Haptics.impact() }
                }
                .onChange(of: t >= Self.revealStart) { due in
                    if due { reveal() }
                }
                .onChange(of: t >= Self.duration) { done in
                    if done { finish() }
                }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            reveal()
            finish()
        }
        .onAppear { start = Date() }
    }

    private func reveal() {
        guard !revealed, frozenTime == nil else { return }
        revealed = true
        onReveal()
    }

    private func finish() {
        guard !finished, frozenTime == nil else { return }
        finished = true
        onFinish()
    }

    @ViewBuilder
    private func scene(_ t: Double) -> some View {
        let d = t - Self.impact                                   // Zeit seit dem Durchbruch
        let bloom = Motion.easeOut(Motion.progress(t, Self.impact, Self.impact + 0.6))
        let reveal = Motion.ease(t, Self.revealStart, Self.revealStart + 0.85)
        let fadeOut = Motion.ease(t, 3.75, Self.duration)

        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let size = min(w * 0.105, 46)
            let center = CGPoint(x: w / 2, y: h * 0.46)
            let headerScale = Self.headerLogoSize / size
            let logoY = center.y + (Self.headerLogoCenterY - center.y) * CGFloat(reveal)
            let logoScale = 1 + (headerScale - 1) * CGFloat(reveal)

            ZStack {
                // Bühne: schwarz, nach dem Durchbruch farbiges Polarlicht; wird beim Aufdecken durchsichtig
                ZStack {
                    Color.black
                    aurora(t: t, w: w, bloom: bloom)
                        .position(center)
                    RadialGradient(colors: [.clear, .black.opacity(0.75)], center: .center,
                                   startRadius: w * 0.35, endRadius: w * 1.2)
                }
                .opacity(1 - reveal)
                .ignoresSafeArea()

                // Lichtfaden unter dem Schriftzug
                lightThread(t: t, w: w)
                    .position(x: center.x, y: center.y + size * 0.78)
                    .opacity(1 - reveal)

                // Schockwellen
                ForEach(0..<2, id: \.self) { i in
                    let p = Motion.progress(d - Double(i) * 0.12, 0, 1.1)
                    Circle()
                        .strokeBorder(AngularGradient(colors: Theme.brandLoop, center: .center,
                                                      angle: .degrees(t * 90)),
                                      lineWidth: 1 + 9 * (1 - p))
                        .frame(width: w * 0.32, height: w * 0.32)
                        .scaleEffect(0.2 + 4.2 * Motion.expoOut(p))
                        .opacity(p > 0 && p < 1 ? (1 - p) * 0.9 : 0)
                        .blur(radius: 1.5 * p)
                        .position(center)
                }

                // Splitter, Risse, Funken
                BreakthroughBurst(d: d)
                    .frame(width: w, height: h)
                    .position(x: w / 2, y: h / 2 + (center.y - h / 2))
                    .allowsHitTesting(false)

                // Kleine Oberzeile
                Text("AUTOMOTIVE DIAGNOSTICS")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(2 + 5 * Motion.expoOut(Motion.progress(t, 1.6, 2.6)))
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(Motion.ease(t, 1.65, 2.2) * (1 - reveal))
                    .position(x: center.x, y: center.y - size * 1.2)

                // Der Schriftzug – bleibt obenauf und gleitet in den Kopf der Startseite
                logo(t: t, d: d, size: size, bloom: bloom)
                    .scaleEffect(logoScale)
                    .position(x: center.x, y: logoY)
                    .opacity(1 - fadeOut)

                // Unterzeile
                Text("Dein Auto spricht. Wir übersetzen.")
                    .font(Theme.rounded(15, weight: .medium))
                    .foregroundStyle(LinearGradient(colors: [.white.opacity(0.85), Theme.accent.opacity(0.9)],
                                                    startPoint: .leading, endPoint: .trailing))
                    .opacity(Motion.ease(t, 2.05, 2.55) * (1 - reveal))
                    .blur(radius: 8 * (1 - Motion.ease(t, 2.05, 2.55)))
                    .position(x: center.x, y: center.y + size * 1.45 + 10 * CGFloat(1 - Motion.ease(t, 2.05, 2.55)))

                // Weißer Blitz beim Durchbruch
                Color.white
                    .opacity(d > 0 ? 0.6 * exp(-9 * d) : 0)
                    .blendMode(.screen)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)

                Text("Tippen zum Überspringen")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .opacity(Motion.ease(t, 0.6, 1.2) * (1 - reveal))
                    .position(x: w / 2, y: h - 12)
            }
            .frame(width: w, height: h)
        }
    }

    // MARK: - Bausteine

    /// Rotierender, stark weichgezeichneter Markenverlauf hinter dem Schriftzug.
    private func aurora(t: Double, w: CGFloat, bloom: Double) -> some View {
        ZStack {
            Circle()
                .fill(AngularGradient(colors: Theme.brandLoop, center: .center))
                .frame(width: w * 1.25, height: w * 1.25)
                .rotationEffect(.degrees(t * 35))
                .blur(radius: 90)
                .opacity(0.5 * bloom)
            Ellipse()
                .fill(RadialGradient(colors: [Theme.accent.opacity(0.55), .clear], center: .center,
                                     startRadius: 0, endRadius: w * 0.5))
                .frame(width: w * 1.1, height: w * 0.45)
                .opacity(Motion.ease(t, 0.3, 1.2) * (1 - 0.5 * bloom))
        }
    }

    /// Feiner Lichtfaden, der sich aus der Mitte aufzieht und beim Durchbruch nach außen schießt.
    private func lightThread(t: Double, w: CGFloat) -> some View {
        let grow = Motion.expoOut(Motion.progress(t, 0.1, 1.0))
        let shoot = Motion.expoOut(Motion.progress(t, Self.impact, Self.impact + 0.7))
        let width = w * (0.62 * grow + 0.8 * shoot)
        return Capsule()
            .fill(LinearGradient(colors: [.clear, Theme.accent, .white, Theme.magenta, .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(width: width, height: 1.4 + 1.2 * (1 - shoot))
            .shadow(color: Theme.accent, radius: 8)
            .shadow(color: Theme.violet.opacity(0.8), radius: 18)
            .opacity(1 - shoot * 0.85)
    }

    /// Schriftzug mit chromatischen Geistern, Erblühen in den Markenverlauf und Glanzlauf.
    private func logo(t: Double, d: Double, size: CGFloat, bloom: Double) -> some View {
        // Geister laufen zusammen, beim Einschlag kurz auseinander
        let converge = size * 0.22 * CGFloat(1 - Motion.ease(t, 0.55, Self.impact))
        let kick = d > 0 ? size * 0.3 * CGFloat(exp(-9 * d)) : 0
        let split = converge + kick
        // Einatmen vor dem Einschlag, dann Sprung nach vorn mit gedämpfter Schwingung
        let inhale = 1 - 0.045 * Motion.ease(t, 1.15, Self.impact)
        let punch = d > 0 ? 1 + 0.11 * exp(-5.5 * d) * cos(17 * d) : inhale
        let sheen = Motion.progress(t, 2.15, 3.0)

        return ZStack {
            // Glut hinter den Buchstaben
            Capsule()
                .fill(LinearGradient(colors: Theme.brandColors, startPoint: .leading, endPoint: .trailing))
                .frame(width: size * 9, height: size * 1.1)
                .blur(radius: 34)
                .opacity(0.55 * bloom)

            LogoLetters(size: size, t: t)
                .foregroundStyle(Theme.magenta)
                .offset(x: split)
                .blendMode(.screen)
                .opacity(split > 0.5 ? 0.85 : 0)
            LogoLetters(size: size, t: t)
                .foregroundStyle(Theme.accent)
                .offset(x: -split)
                .blendMode(.screen)
                .opacity(split > 0.5 ? 0.85 : 0)

            // Hauptschrift: vor dem Einschlag silbern, danach Markenverlauf
            LogoMark(size: size, t: t)
                .opacity(bloom)
            LogoLetters(size: size, t: t)
                .foregroundStyle(LinearGradient(colors: [.white, Color(white: 0.72)], startPoint: .top, endPoint: .bottom))
                .opacity(1 - bloom)

            // Glanz, der über den Schriftzug läuft
            LogoLetters(size: size, t: t)
                .opacity(0)
                .overlay {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.95), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.25)
                            .offset(x: -geo.size.width * 0.3 + geo.size.width * 1.6 * Motion.easeInOut(sheen))
                    }
                    .mask { LogoLetters(size: size, t: t) }
                }
                .opacity(sheen > 0 && sheen < 1 ? 1 : 0)
        }
        .scaleEffect(punch)
        .shadow(color: Theme.violet.opacity(0.5 * bloom), radius: 20)
    }
}

/// Die Buchstaben von RIDEREADER. Mit `t` steigen sie gestaffelt hinter einer Kante hervor; ohne `t` stehen sie fertig da.
struct LogoLetters: View {
    var size: CGFloat
    var t: Double? = nil

    static let letters = Array("RIDEREADER")

    var body: some View {
        HStack(spacing: size * 0.035) {
            ForEach(0..<Self.letters.count, id: \.self) { i in
                let begin = 0.5 + Double(i) * 0.05
                let p = t.map { Motion.progress($0, begin, begin + 0.65) } ?? 1
                let e = Motion.expoOut(p)
                Text(String(Self.letters[i]))
                    .font(Theme.display(size, weight: .heavy))
                    .italic()
                    .offset(y: size * 1.35 * CGFloat(1 - e))
                    .blur(radius: 5 * CGFloat(1 - p))
            }
        }
        .padding(.horizontal, size * 0.3)
        .frame(height: size * 1.45)
        .clipped()
        .fixedSize()
    }
}

/// Der fertige Schriftzug im Markenverlauf – im Intro und im Kopf der Startseite identisch.
struct LogoMark: View {
    var size: CGFloat
    var t: Double? = nil

    var body: some View {
        LogoLetters(size: size, t: t)
            .opacity(0)
            .overlay {
                Theme.logoGradient
                    .mask { LogoLetters(size: size, t: t) }
            }
    }
}

/// Der Durchbruch: Risse wie in Glas, Splitter und Funken fliegen aus der Mitte. `d` = Sekunden seit dem Einschlag.
struct BreakthroughBurst: View {
    var d: Double

    var body: some View {
        Canvas { ctx, size in
            guard d > 0, d < 1.8 else { return }
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let colors: [Color] = [Theme.accent, Theme.violet, Theme.magenta, .white, Theme.accentDeep]

            // Risse: zackige Linien, die blitzschnell aufreißen und verglühen
            let crack = min(d / 0.1, 1)
            let crackFade = max(0, 1 - d / 0.75)
            if crackFade > 0 {
                var cracks = Path()
                for i in 0..<14 {
                    var pt = c
                    cracks.move(to: pt)
                    let base = Double(i) / 14 * .pi * 2 + rand(i) * 0.35
                    for s in 1...5 {
                        let len = CGFloat(14 + 26 * rand(i * 7 + s)) * CGFloat(crack)
                        let a = base + (rand(i * 13 + s) - 0.5) * 0.8
                        pt = CGPoint(x: pt.x + CGFloat(cos(a)) * len, y: pt.y + CGFloat(sin(a)) * len * 0.8)
                        cracks.addLine(to: pt)
                    }
                }
                ctx.stroke(cracks, with: .color(.white.opacity(0.75 * crackFade)), lineWidth: 1)
                var glow = ctx
                glow.addFilter(.blur(radius: 4))
                glow.stroke(cracks, with: .color(Theme.accent.opacity(0.8 * crackFade)), lineWidth: 2.5)
            }

            // Splitter und Funken als Lichtstreifen
            var glow = ctx
            glow.addFilter(.blur(radius: 3))
            for i in 0..<60 {
                let angle = rand(i) * .pi * 2
                let speed = 220 + 560 * rand(i + 100)
                let lifetime = 0.8 + 0.8 * rand(i + 200)
                let life = d / lifetime
                guard life < 1 else { continue }
                let travel = CGFloat(speed * Motion.expoOut(min(d / 1.3, 1)) * 0.8)
                let dir = CGPoint(x: CGFloat(cos(angle)), y: CGFloat(sin(angle)) * 0.7)
                let pos = CGPoint(x: c.x + dir.x * travel, y: c.y + dir.y * travel)
                let tail = CGFloat(8 + 46 * (1 - min(d / 0.6, 1)))
                var streak = Path()
                streak.move(to: pos)
                streak.addLine(to: CGPoint(x: pos.x - dir.x * tail, y: pos.y - dir.y * tail))
                let color = colors[i % colors.count].opacity(1 - life)
                let width = CGFloat(1 + 2.2 * rand(i + 300))
                ctx.stroke(streak, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
                glow.stroke(streak, with: .color(color), style: StrokeStyle(lineWidth: width * 2.5, lineCap: .round))

                // jeder vierte ist ein kleiner, rotierender Glassplitter
                if i % 4 == 0 {
                    var shard = ctx
                    shard.translateBy(x: pos.x, y: pos.y)
                    shard.rotate(by: .radians(angle + d * (4 + 6 * rand(i + 400))))
                    let s = CGFloat(4 + 6 * rand(i + 500))
                    var tri = Path()
                    tri.move(to: CGPoint(x: -s, y: -s * 0.4))
                    tri.addLine(to: CGPoint(x: s, y: 0))
                    tri.addLine(to: CGPoint(x: -s * 0.3, y: s * 0.6))
                    tri.closeSubpath()
                    shard.fill(tri, with: .color(.white.opacity(0.55 * (1 - life))))
                    shard.stroke(tri, with: .color(colors[(i / 4) % colors.count].opacity(1 - life)), lineWidth: 0.8)
                }
            }
        }
        .blendMode(.screen)
    }

    /// Feste Pseudo-Zufallszahl 0…1 je Index (gleiches Bild bei jedem Durchlauf).
    private func rand(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898 + 78.233) * 43758.5453
        return x - floor(x)
    }
}
