import SwiftUI

/// Ladeanimation: drei kleine Anime-Mechaniker arbeiten an einem Motor.
/// - Kenji läuft hin und her und schlägt mit dem Schraubenschlüssel zu (Funken!)
/// - Mia steht auf der Werkzeugkiste und leuchtet mit der Taschenlampe in den Motor
/// - Bolt rollt einen Reifen über den Fortschrittsbalken – der Reifen IST der Ladebalken
/// Alles wird pro Bild mit Canvas gezeichnet (flüssig, 120 Hz).
struct MechanicsLoader: View {
    /// 0…1, nil = unbestimmt (Bolt läuft dann hin und her)
    var progress: Double?
    var accent: Color = Theme.accent

    @State private var start = Date()

    static let jokes = [
        "Wer hat meinen 10er gesehen?!",
        "Hmm … klingt teuer.",
        "Licht hierher, bitte!",
        "Nur noch EINE Schraube …",
        "Das war vorher schon so!",
        "Ich les' Steuergeräte wie Manga.",
        "Keine Panik, nur ein Kabel.",
        "Kaffee? Erst nach dem Scan!",
        "Gleich hab ich's … glaub ich.",
        "Sieht aus wie neu. Fast.",
    ]

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas { ctx, size in
                draw(ctx, size: size, t: t)
            }
            .overlay(alignment: .top) { bubble(t) }
        }
        .aspectRatio(1.35, contentMode: .fit)
        .onAppear { start = Date() }
    }

    // MARK: - Sprechblase

    @ViewBuilder
    private func bubble(_ t: Double) -> some View {
        let slot = Int(t / 2.6)
        let local = t - Double(slot) * 2.6
        let appear = Motion.backOut(Motion.progress(local, 0.0, 0.35))
        let fade = 1 - Motion.progress(local, 2.25, 2.6)
        let joke = Self.jokes[slot % Self.jokes.count]
        let sides: [UnitPoint] = [.leading, .trailing, .center]
        let side = sides[slot % 3]
        Text(joke)
            .font(Theme.rounded(12, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                BubbleShape(tailX: side == .leading ? 0.25 : side == .trailing ? 0.75 : 0.5)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.35), radius: 6, y: 3)
            )
            .scaleEffect(appear, anchor: .bottom)
            .opacity(fade)
            .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : side == .trailing ? .trailing : .center)
            .padding(.horizontal, 8)
    }

    // MARK: - Szene

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let u = size.width / 340   // Basiseinheit, Szene ist für 340 pt Breite entworfen
        let floorY = size.height * 0.74
        let engineCenter = CGPoint(x: size.width * 0.5, y: floorY - 46 * u)

        // Werkstattlicht von oben
        var cone = Path()
        cone.move(to: CGPoint(x: size.width * 0.44, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.56, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.92, y: floorY + 10 * u))
        cone.addLine(to: CGPoint(x: size.width * 0.08, y: floorY + 10 * u))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [accent.opacity(0.16), accent.opacity(0.0)]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))

        // Boden
        ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.06, y: floorY - 8 * u, width: size.width * 0.88, height: 22 * u)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.12), .clear]),
                                       center: CGPoint(x: size.width / 2, y: floorY), startRadius: 0, endRadius: size.width * 0.45))

        // Mia mit Taschenlampe – Lichtkegel zuerst, damit er hinter allem liegt
        let miaPos = CGPoint(x: size.width * 0.8, y: floorY - 26 * u)
        let sweep = sin(t * 1.3)
        let miaScale = u * 0.9
        let miaBob = sin(t * 2.4) * 1.2
        let miaArm = 0.28 + sweep * 0.22
        // Hand- und Lampenposition genau wie in drawMechanic berechnen (Figur schaut nach links)
        let shoulder = CGPoint(x: miaPos.x - 8 * miaScale, y: miaPos.y + (miaBob - 48) * miaScale)
        let dir = CGPoint(x: -cos(miaArm), y: sin(miaArm))
        let lamp = CGPoint(x: shoulder.x + dir.x * 42 * miaScale, y: shoulder.y + dir.y * 42 * miaScale)
        let reach = 170 * u
        var beam = Path()
        beam.move(to: lamp)
        for spread in [-0.2, 0.2] {
            let a = atan2(dir.y, dir.x) + spread
            beam.addLine(to: CGPoint(x: lamp.x + cos(a) * reach, y: lamp.y + sin(a) * reach))
        }
        beam.closeSubpath()
        ctx.fill(beam, with: .radialGradient(Gradient(colors: [Color(red: 1, green: 0.95, blue: 0.7).opacity(0.55), .clear]),
                                             center: lamp, startRadius: 0, endRadius: reach))

        drawEngine(ctx, center: engineCenter, u: u, t: t)

        // Kenji: läuft zwischen zwei Punkten, bleibt am Motor stehen und schlägt zu
        let cycle = fmod(t, 4.0)
        let leftX = size.width * 0.1, workX = engineCenter.x - 78 * u
        var kenjiX: CGFloat, facing: CGFloat, walking: Bool, swing: Double
        if cycle < 1.1 {           // zum Motor laufen
            let p = Motion.easeInOut(cycle / 1.1)
            kenjiX = leftX + (workX - leftX) * p; facing = 1; walking = true; swing = 0
        } else if cycle < 2.9 {    // arbeiten
            kenjiX = workX; facing = 1; walking = false
            swing = max(0, sin((cycle - 1.1) * 9))
        } else {                   // zurück zum Werkzeugwagen
            let p = Motion.easeInOut((cycle - 2.9) / 1.1)
            kenjiX = workX + (leftX - workX) * p; facing = -1; walking = true; swing = 0
        }
        // Werkzeugwagen links
        drawToolCart(ctx, at: CGPoint(x: size.width * 0.06, y: floorY), u: u)
        let kenji = Mechanic(suit: Color(red: 0.2, green: 0.45, blue: 0.95), hair: Color(red: 0.12, green: 0.1, blue: 0.16),
                             hat: .cap(Color(red: 1, green: 0.35, blue: 0.3)), tool: .wrench, blush: true)
        drawMechanic(ctx, kenji, feet: CGPoint(x: kenjiX, y: floorY), scale: u * 0.95, facing: facing,
                     walk: walking ? t * 9 : 0, armAngle: walking ? 0.3 + sin(t * 9) * 0.3 : -0.4 + swing * 1.6, t: t)
        // Funken beim Treffer
        if !walking && swing > 0.92 {
            drawSparks(ctx, at: CGPoint(x: workX + 30 * u, y: floorY - 70 * u), u: u, t: t)
        }

        // Werkzeugkiste + Mia
        let box = CGRect(x: miaPos.x - 26 * u, y: floorY - 26 * u, width: 52 * u, height: 26 * u)
        drawToolbox(ctx, box, u: u)
        let mia = Mechanic(suit: Color(red: 1, green: 0.55, blue: 0.2), hair: Color(red: 0.95, green: 0.45, blue: 0.62),
                           hat: .ponytail, tool: .flashlight, blush: true)
        drawMechanic(ctx, mia, feet: miaPos, scale: miaScale, facing: -1, walk: 0,
                     armAngle: miaArm, t: t, bob: miaBob)

        // Fortschrittsbalken + Bolt mit Reifen
        let trackY = floorY + 30 * u
        let track = CGRect(x: size.width * 0.08, y: trackY, width: size.width * 0.84, height: 8 * u)
        ctx.fill(Path(roundedRect: track, cornerRadius: 4 * u), with: .color(.white.opacity(0.08)))
        let p: Double
        if let progress {
            p = min(max(progress, 0), 1)
        } else {
            p = 0.5 + 0.5 * sin(t * 0.9)
        }
        let filled = CGRect(x: track.minX, y: track.minY, width: max(track.height, track.width * p), height: track.height)
        ctx.fill(Path(roundedRect: filled, cornerRadius: 4 * u),
                 with: .linearGradient(Gradient(colors: [Theme.accentDeep, accent]),
                                       startPoint: CGPoint(x: filled.minX, y: 0), endPoint: CGPoint(x: filled.maxX, y: 0)))
        var glow = ctx
        glow.addFilter(.blur(radius: 6 * u))
        glow.fill(Path(roundedRect: filled, cornerRadius: 4 * u), with: .color(accent.opacity(0.6)))

        let tireR = 13 * u
        let tireCenter = CGPoint(x: filled.maxX, y: track.midY - tireR - 2 * u)
        drawTire(ctx, center: tireCenter, radius: tireR, rotation: Double(filled.maxX / tireR))
        let bolt = Mechanic(suit: Color(red: 0.25, green: 0.8, blue: 0.55), hair: Color(red: 0.98, green: 0.82, blue: 0.3),
                            hat: .spiky, tool: .none, blush: true)
        drawMechanic(ctx, bolt, feet: CGPoint(x: tireCenter.x - 28 * u, y: track.midY - 2 * u), scale: u * 0.62, facing: 1,
                     walk: progress == nil ? t * 8 : t * 6, armAngle: 0.15, t: t, sweat: true)
    }

    // MARK: - Figuren

    enum Hat { case cap(Color), ponytail, spiky }
    enum Tool { case wrench, flashlight, none }

    struct Mechanic {
        var suit: Color
        var hair: Color
        var hat: Hat
        var tool: Tool
        var blush: Bool
    }

    private static let outline = Color(red: 0.06, green: 0.05, blue: 0.09)
    private static let skin = Color(red: 1.0, green: 0.86, blue: 0.74)

    /// Zeichnet einen Chibi-Mechaniker (großer Kopf, große Augen, Cel-Shading mit Kontur).
    /// `feet` = Mittelpunkt zwischen den Füßen, Figur ist ca. 100 Einheiten hoch.
    private func drawMechanic(_ base: GraphicsContext, _ m: Mechanic, feet: CGPoint, scale: CGFloat, facing: CGFloat,
                              walk: Double, armAngle: Double, t: Double, bob: Double = 0, sweat: Bool = false) {
        // Schatten
        base.fill(Path(ellipseIn: CGRect(x: feet.x - 18 * scale, y: feet.y - 3 * scale, width: 36 * scale, height: 7 * scale)),
                  with: .color(.black.opacity(0.35)))

        var c = base
        let bounce = walk == 0 ? bob : -abs(sin(walk)) * 3
        c.translateBy(x: feet.x, y: feet.y + bounce * scale)
        c.scaleBy(x: facing * scale, y: scale)
        let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(Self.outline)

        func limb(from: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: Color) -> CGPoint {
            let end = CGPoint(x: from.x + sin(angle) * length, y: from.y + cos(angle) * length)
            var p = Path()
            p.move(to: from)
            p.addLine(to: end)
            c.stroke(p, with: ink, style: StrokeStyle(lineWidth: width + 4.4, lineCap: .round))
            c.stroke(p, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round))
            return end
        }

        // Beine
        let legSwing = sin(walk) * 0.55
        let suitDark = m.suit.opacity(0.75)
        for (i, swing) in [legSwing, -legSwing].enumerated() {
            let hip = CGPoint(x: i == 0 ? -5 : 5, y: -26)
            let foot = limb(from: hip, angle: swing, length: 20, width: 9, color: i == 0 ? suitDark : m.suit)
            let boot = Path(roundedRect: CGRect(x: foot.x - 5, y: foot.y - 3, width: 12, height: 7), cornerRadius: 3)
            c.fill(boot, with: .color(Color(white: 0.15)))
            c.stroke(boot, with: ink, style: line)
        }

        // hinterer Arm
        _ = limb(from: CGPoint(x: -9, y: -48), angle: walk == 0 ? -0.25 : -sin(walk) * 0.6, length: 18, width: 7, color: suitDark)

        // Körper (Overall)
        let body = Path(roundedRect: CGRect(x: -14, y: -54, width: 28, height: 32), cornerRadius: 11)
        c.fill(body, with: .color(m.suit))
        var shade = c
        shade.clip(to: body)
        shade.fill(Path(CGRect(x: -14, y: -54, width: 10, height: 32)), with: .color(.black.opacity(0.18)))
        c.stroke(body, with: ink, style: line)
        // Gürtel + Tasche
        var belt = Path()
        belt.move(to: CGPoint(x: -13, y: -32))
        belt.addLine(to: CGPoint(x: 13, y: -32))
        c.stroke(belt, with: .color(.black.opacity(0.45)), lineWidth: 2.5)
        c.stroke(Path(roundedRect: CGRect(x: 2, y: -47, width: 8, height: 7), cornerRadius: 1.5), with: .color(.white.opacity(0.5)), lineWidth: 1.2)

        // Kopf
        let head = CGRect(x: -21, y: -98, width: 42, height: 40)
        // Pferdeschwanz hinter dem Kopf
        if case .ponytail = m.hat {
            var tail = Path()
            tail.move(to: CGPoint(x: -16, y: -90))
            tail.addQuadCurve(to: CGPoint(x: -30, y: -62 + sin(t * 4) * 2), control: CGPoint(x: -38, y: -88))
            tail.addQuadCurve(to: CGPoint(x: -12, y: -80), control: CGPoint(x: -20, y: -66))
            c.fill(tail, with: .color(m.hair))
            c.stroke(tail, with: ink, style: line)
        }
        c.fill(Path(ellipseIn: head), with: .color(Self.skin))
        c.stroke(Path(ellipseIn: head), with: ink, style: line)

        // Haare / Mütze
        switch m.hat {
        case .cap(let color):
            var cap = Path()
            cap.move(to: CGPoint(x: -21, y: -80))
            cap.addCurve(to: CGPoint(x: 21, y: -80), control1: CGPoint(x: -22, y: -106), control2: CGPoint(x: 22, y: -106))
            cap.closeSubpath()
            c.fill(cap, with: .color(color))
            c.stroke(cap, with: ink, style: line)
            var brim = Path()
            brim.move(to: CGPoint(x: 8, y: -81))
            brim.addQuadCurve(to: CGPoint(x: 33, y: -78), control: CGPoint(x: 24, y: -86))
            brim.addLine(to: CGPoint(x: 8, y: -77))
            c.fill(brim, with: .color(color.opacity(0.8)))
            c.stroke(brim, with: ink, style: line)
            // Pony unter der Mütze
            var bangs = Path()
            bangs.move(to: CGPoint(x: -20, y: -80))
            bangs.addLine(to: CGPoint(x: -14, y: -72))
            bangs.addLine(to: CGPoint(x: -9, y: -79))
            bangs.addLine(to: CGPoint(x: -3, y: -71))
            bangs.addLine(to: CGPoint(x: 2, y: -79))
            bangs.closeSubpath()
            c.fill(bangs, with: .color(m.hair))
        case .ponytail, .spiky:
            var hair = Path()
            hair.move(to: CGPoint(x: -22, y: -72))
            if case .spiky = m.hat {
                let spikes: [(CGFloat, CGFloat)] = [(-24, -94), (-14, -112), (-4, -100), (6, -116), (14, -100), (26, -106), (22, -84)]
                for s in spikes { hair.addLine(to: CGPoint(x: s.0, y: s.1)) }
            } else {
                hair.addCurve(to: CGPoint(x: 22, y: -78), control1: CGPoint(x: -26, y: -110), control2: CGPoint(x: 26, y: -108))
            }
            hair.addLine(to: CGPoint(x: 18, y: -76))
            hair.addLine(to: CGPoint(x: 12, y: -84))
            hair.addLine(to: CGPoint(x: 6, y: -74))
            hair.addLine(to: CGPoint(x: -2, y: -84))
            hair.addLine(to: CGPoint(x: -8, y: -73))
            hair.addLine(to: CGPoint(x: -14, y: -83))
            hair.closeSubpath()
            c.fill(hair, with: .color(m.hair))
            c.stroke(hair, with: ink, style: line)
            // Glanzlicht im Haar
            var gloss = Path()
            gloss.move(to: CGPoint(x: -8, y: -96))
            gloss.addQuadCurve(to: CGPoint(x: 6, y: -98), control: CGPoint(x: -1, y: -101))
            c.stroke(gloss, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }

        // Augen (große Anime-Augen mit zwei Glanzpunkten, blinzeln gelegentlich)
        let blink = fmod(t + Double(feet.x) * 0.01, 3.7) < 0.12
        for ex in [CGFloat(-3), CGFloat(11)] {
            if blink {
                var lid = Path()
                lid.move(to: CGPoint(x: ex - 4, y: -71))
                lid.addQuadCurve(to: CGPoint(x: ex + 4, y: -71), control: CGPoint(x: ex, y: -68))
                c.stroke(lid, with: ink, style: line)
            } else {
                let eye = CGRect(x: ex - 4, y: -78, width: 8, height: 11)
                c.fill(Path(ellipseIn: eye), with: .linearGradient(
                    Gradient(colors: [Color(red: 0.12, green: 0.08, blue: 0.25), Color(red: 0.25, green: 0.5, blue: 0.95)]),
                    startPoint: CGPoint(x: 0, y: eye.minY), endPoint: CGPoint(x: 0, y: eye.maxY)))
                c.fill(Path(ellipseIn: CGRect(x: ex - 2.5, y: -77, width: 3.6, height: 3.6)), with: .color(.white))
                c.fill(Path(ellipseIn: CGRect(x: ex + 1, y: -71.5, width: 1.8, height: 1.8)), with: .color(.white.opacity(0.9)))
            }
        }
        if m.blush {
            c.fill(Path(ellipseIn: CGRect(x: -9, y: -66, width: 6, height: 3)), with: .color(Color.pink.opacity(0.45)))
            c.fill(Path(ellipseIn: CGRect(x: 14, y: -66, width: 6, height: 3)), with: .color(Color.pink.opacity(0.45)))
        }
        // Mund: arbeitet konzentriert (kleines „o“) oder grinst
        if armAngle > 0.9 && m.tool == .wrench {
            c.fill(Path(ellipseIn: CGRect(x: 5, y: -65, width: 4, height: 4)), with: ink)
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 3, y: -64))
            mouth.addQuadCurve(to: CGPoint(x: 10, y: -64), control: CGPoint(x: 6.5, y: -60))
            c.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        // Schweißtropfen
        if sweat {
            let drop = fmod(t * 1.5, 1)
            var d = Path()
            let dx: CGFloat = -22, dy = -88 + CGFloat(drop) * 10
            d.move(to: CGPoint(x: dx, y: dy - 5))
            d.addQuadCurve(to: CGPoint(x: dx, y: dy + 4), control: CGPoint(x: dx - 5, y: dy + 2))
            d.addQuadCurve(to: CGPoint(x: dx, y: dy - 5), control: CGPoint(x: dx + 5, y: dy + 2))
            c.fill(d, with: .color(Color(red: 0.6, green: 0.85, blue: 1).opacity(1 - drop)))
        }

        // vorderer Arm mit Werkzeug
        let shoulder = CGPoint(x: 8, y: -48)
        let hand = limb(from: shoulder, angle: Double.pi / 2 - armAngle, length: 18, width: 7, color: m.suit)
        c.fill(Path(ellipseIn: CGRect(x: hand.x - 4, y: hand.y - 4, width: 8, height: 8)), with: .color(Self.skin))
        c.stroke(Path(ellipseIn: CGRect(x: hand.x - 4, y: hand.y - 4, width: 8, height: 8)), with: ink, lineWidth: 1.8)

        var tool = c
        tool.translateBy(x: hand.x, y: hand.y)
        tool.rotate(by: .radians(armAngle))
        switch m.tool {
        case .wrench:
            let handle = Path(roundedRect: CGRect(x: 0, y: -3, width: 26, height: 6), cornerRadius: 3)
            tool.fill(handle, with: .linearGradient(Gradient(colors: [Color(white: 0.9), Color(white: 0.55)]),
                                                    startPoint: CGPoint(x: 0, y: -3), endPoint: CGPoint(x: 0, y: 3)))
            tool.stroke(handle, with: ink, lineWidth: 1.8)
            var jaw = Path()
            jaw.addArc(center: CGPoint(x: 30, y: 0), radius: 7, startAngle: .degrees(40), endAngle: .degrees(320), clockwise: false)
            tool.stroke(jaw, with: ink, style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
            tool.stroke(jaw, with: .color(Color(white: 0.8)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        case .flashlight:
            let body = Path(roundedRect: CGRect(x: -2, y: -3.5, width: 18, height: 7), cornerRadius: 2)
            tool.fill(body, with: .color(Color(red: 0.95, green: 0.8, blue: 0.2)))
            tool.stroke(body, with: ink, lineWidth: 1.8)
            let head = Path(roundedRect: CGRect(x: 15, y: -5.5, width: 7, height: 11), cornerRadius: 2)
            tool.fill(head, with: .color(Color(white: 0.3)))
            tool.stroke(head, with: ink, lineWidth: 1.8)
            tool.fill(Path(ellipseIn: CGRect(x: 19, y: -5, width: 5, height: 10)), with: .color(.white))
        case .none:
            break
        }
    }

    // MARK: - Requisiten

    private func drawEngine(_ ctx: GraphicsContext, center: CGPoint, u: CGFloat, t: Double) {
        var c = ctx
        // Motor läuft leicht unruhig
        c.translateBy(x: center.x + CGFloat(sin(t * 38)) * 0.6 * u, y: center.y + CGFloat(cos(t * 31)) * 0.5 * u)
        c.scaleBy(x: u, y: u)
        let ink = GraphicsContext.Shading.color(Self.outline)
        let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

        // Dampfwölkchen
        for i in 0..<3 {
            let life = fmod(t * 0.7 + Double(i) / 3, 1)
            let r = 6 + 10 * life
            let x = 26 + CGFloat(sin(t * 2 + Double(i))) * 6
            let y = -58 - 38 * life
            c.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)),
                   with: .color(.white.opacity(0.22 * (1 - life))))
        }

        // Block
        let block = Path(roundedRect: CGRect(x: -52, y: -24, width: 104, height: 58), cornerRadius: 9)
        c.fill(block, with: .linearGradient(Gradient(colors: [Color(white: 0.55), Color(white: 0.28)]),
                                            startPoint: CGPoint(x: 0, y: -24), endPoint: CGPoint(x: 0, y: 34)))
        c.stroke(block, with: ink, style: line)
        // Ventildeckel mit Rippen
        let cover = Path(roundedRect: CGRect(x: -46, y: -46, width: 92, height: 24), cornerRadius: 8)
        c.fill(cover, with: .linearGradient(Gradient(colors: [Theme.accent.opacity(0.95), Theme.accentDeep]),
                                            startPoint: CGPoint(x: 0, y: -46), endPoint: CGPoint(x: 0, y: -22)))
        c.stroke(cover, with: ink, style: line)
        for i in 0..<5 {
            var rib = Path()
            let x = -32 + CGFloat(i) * 16
            rib.move(to: CGPoint(x: x, y: -41))
            rib.addLine(to: CGPoint(x: x, y: -27))
            c.stroke(rib, with: .color(.white.opacity(0.35)), lineWidth: 2)
        }
        // Öldeckel
        c.fill(Path(ellipseIn: CGRect(x: 24, y: -54, width: 14, height: 9)), with: .color(Color(white: 0.15)))
        c.stroke(Path(ellipseIn: CGRect(x: 24, y: -54, width: 14, height: 9)), with: ink, lineWidth: 2)
        // Krümmer
        for i in 0..<3 {
            var pipe = Path()
            let y = -10 + CGFloat(i) * 12
            pipe.move(to: CGPoint(x: 50, y: y))
            pipe.addQuadCurve(to: CGPoint(x: 66, y: 30), control: CGPoint(x: 66, y: y))
            c.stroke(pipe, with: ink, style: StrokeStyle(lineWidth: 8, lineCap: .round))
            c.stroke(pipe, with: .color(Color(red: 0.75, green: 0.42, blue: 0.25)), style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
        }
        // Riemenscheibe, dreht sich
        let pulley = CGRect(x: -70, y: -6, width: 30, height: 30)
        c.fill(Path(ellipseIn: pulley), with: .color(Color(white: 0.22)))
        c.stroke(Path(ellipseIn: pulley), with: ink, style: line)
        var spokes = c
        spokes.translateBy(x: -55, y: 9)
        spokes.rotate(by: .radians(t * 8))
        for i in 0..<3 {
            var s = Path()
            s.move(to: .zero)
            s.addLine(to: CGPoint(x: 0, y: -11))
            var r = spokes
            r.rotate(by: .degrees(Double(i) * 120))
            r.stroke(s, with: .color(Color(white: 0.75)), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        // Lampe am Block (Status)
        let pulse = 0.5 + 0.5 * sin(t * 5)
        c.fill(Path(ellipseIn: CGRect(x: 30, y: 10, width: 9, height: 9)), with: .color(Theme.accent.opacity(0.4 + 0.6 * pulse)))
        // Halter
        c.fill(Path(roundedRect: CGRect(x: -40, y: 34, width: 80, height: 8), cornerRadius: 3), with: .color(Color(white: 0.12)))
    }

    private func drawSparks(_ ctx: GraphicsContext, at point: CGPoint, u: CGFloat, t: Double) {
        for i in 0..<9 {
            let angle = Double(i) / 9 * .pi * 2 + t * 13
            let len = (8 + 10 * abs(sin(t * 40 + Double(i)))) * u
            var p = Path()
            p.move(to: point)
            p.addLine(to: CGPoint(x: point.x + cos(angle) * len, y: point.y + sin(angle) * len))
            ctx.stroke(p, with: .color(Color(red: 1, green: 0.85, blue: 0.3)), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }
        var glow = ctx
        glow.addFilter(.blur(radius: 6 * u))
        glow.fill(Path(ellipseIn: CGRect(x: point.x - 10 * u, y: point.y - 10 * u, width: 20 * u, height: 20 * u)),
                  with: .color(Color.yellow.opacity(0.8)))
    }

    private func drawToolbox(_ ctx: GraphicsContext, _ rect: CGRect, u: CGFloat) {
        let ink = GraphicsContext.Shading.color(Self.outline)
        let box = Path(roundedRect: rect, cornerRadius: 4 * u)
        ctx.fill(box, with: .color(Color(red: 0.85, green: 0.18, blue: 0.22)))
        ctx.stroke(box, with: ink, lineWidth: 2.2 * u)
        var lid = Path()
        lid.move(to: CGPoint(x: rect.minX, y: rect.minY + 8 * u))
        lid.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + 8 * u))
        ctx.stroke(lid, with: ink, lineWidth: 1.8 * u)
        ctx.fill(Path(roundedRect: CGRect(x: rect.midX - 6 * u, y: rect.minY + 11 * u, width: 12 * u, height: 4 * u), cornerRadius: 1),
                 with: .color(Color(white: 0.85)))
    }

    private func drawToolCart(_ ctx: GraphicsContext, at foot: CGPoint, u: CGFloat) {
        let ink = GraphicsContext.Shading.color(Self.outline)
        let rect = CGRect(x: foot.x - 6 * u, y: foot.y - 44 * u, width: 26 * u, height: 40 * u)
        let cart = Path(roundedRect: rect, cornerRadius: 3 * u)
        ctx.fill(cart, with: .color(Color(white: 0.25)))
        ctx.stroke(cart, with: ink, lineWidth: 2 * u)
        for i in 1..<3 {
            var shelf = Path()
            let y = rect.minY + CGFloat(i) * 13 * u
            shelf.move(to: CGPoint(x: rect.minX, y: y))
            shelf.addLine(to: CGPoint(x: rect.maxX, y: y))
            ctx.stroke(shelf, with: .color(.white.opacity(0.3)), lineWidth: 1.2 * u)
        }
        for x in [rect.minX + 4 * u, rect.maxX - 4 * u] {
            ctx.fill(Path(ellipseIn: CGRect(x: x - 3 * u, y: foot.y - 5 * u, width: 6 * u, height: 6 * u)), with: .color(.black))
        }
    }

    private func drawTire(_ ctx: GraphicsContext, center: CGPoint, radius: CGFloat, rotation: Double) {
        let ink = GraphicsContext.Shading.color(Self.outline)
        let outer = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        ctx.fill(Path(ellipseIn: outer), with: .color(Color(white: 0.1)))
        ctx.stroke(Path(ellipseIn: outer), with: ink, lineWidth: 2)
        let rim = outer.insetBy(dx: radius * 0.38, dy: radius * 0.38)
        ctx.fill(Path(ellipseIn: rim), with: .color(Color(white: 0.7)))
        var c = ctx
        c.translateBy(x: center.x, y: center.y)
        c.rotate(by: .radians(rotation))
        for i in 0..<4 {
            var tread = Path()
            let a = Double(i) * .pi / 2
            tread.move(to: CGPoint(x: cos(a) * radius * 0.7, y: sin(a) * radius * 0.7))
            tread.addLine(to: CGPoint(x: cos(a) * radius * 0.95, y: sin(a) * radius * 0.95))
            c.stroke(tread, with: .color(Color(white: 0.4)), lineWidth: 1.6)
        }
    }
}

/// Sprechblase mit kleinem Zipfel unten.
struct BubbleShape: Shape {
    var tailX: CGFloat = 0.5

    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: min(14, rect.height / 2))
        let x = rect.minX + rect.width * tailX
        p.move(to: CGPoint(x: x - 6, y: rect.maxY - 1))
        p.addLine(to: CGPoint(x: x, y: rect.maxY + 7))
        p.addLine(to: CGPoint(x: x + 6, y: rect.maxY - 1))
        p.closeSubpath()
        return p
    }
}
