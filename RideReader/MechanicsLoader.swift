import SwiftUI

/// Ladeanimation im Anime-Slapstick-Stil: drei Chibi-Mechaniker in voller Panik.
/// - Kenji rennt kopflos hin und her, rudert mit den Armen, legt einen Bauchklatscher hin und sucht verzweifelt
/// - Mia wühlt in der Werkzeugkiste, wirft alles im hohen Bogen raus und springt kreischend hoch
/// - Bolt schiebt in Todesangst einen Reifen über den Fortschrittsbalken – der Reifen IST der Ladebalken
/// Alles wird pro Bild mit Canvas gezeichnet (flüssig, 120 Hz).
struct MechanicsLoader: View {
    /// 0…1, nil = unbestimmt (Bolt läuft dann hin und her)
    var progress: Double?
    var accent: Color = Theme.accent
    /// Ruhemodus beim Löschen: die Crew putzt in aller Ruhe den Motor – „Alles wird gut …“
    var calm = false

    @State private var start = Date()

    static let jokes = [
        "AAAH! Wo ist der 10er?!",
        "Es piept! WARUM PIEPT ES?!",
        "Wer hat das Kabel gezogen?!",
        "Ruhig bleiben. RUHIG BLEIBEN!",
        "Ich hab nix gemacht!!",
        "Schnell, bevor der Chef kommt!",
        "Gehört das Teil da hin?!",
        "NICHT ANFASSEN! … ups.",
        "Mein Schraubenschlüssel lebt!",
        "Kaffee! Ich brauch KAFFEE!",
    ]

    static let calmLines = [
        "Alles wird gut …",
        "Alles wird gut … alles wird gut …",
        "Ganz ruhig, kleiner Motor.",
        "Alles wird gut …",
        "Ein bisschen Glanz, ein bisschen Liebe.",
        "Schhh … gleich ist alles sauber.",
        "Alles wird gut … alles wird gut …",
        "Tief einatmen. Und polieren.",
    ]

    var body: some View {
        // Höchstens 60 Bilder/s und Zeichnen abseits des Haupt-Threads: bleibt auch auf alten iPhones flüssig,
        // die Bedienung (Abbrechen-Knopf) reagiert trotzdem sofort.
        TimelineView(.animation(minimumInterval: 1.0 / 60)) { context in
            let t = context.date.timeIntervalSince(start)
            Canvas(rendersAsynchronously: true) { ctx, size in
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
        let slotLength = calm ? 3.2 : 1.9
        let slot = Int(t / slotLength)
        let local = t - Double(slot) * slotLength
        let appear = calm ? Motion.easeOut(Motion.progress(local, 0.0, 0.6)) : Motion.backOut(Motion.progress(local, 0.0, 0.25))
        let fade = 1 - Motion.progress(local, slotLength - (calm ? 0.6 : 0.25), slotLength)
        let lines = calm ? Self.calmLines : Self.jokes
        let joke = lines[slot % lines.count]
        let sides: [UnitPoint] = calm ? [.leading, .trailing] : [.leading, .trailing, .center]
        let side = sides[slot % sides.count]
        Text(joke)
            .font(calm ? Theme.rounded(13, weight: .semibold).italic() : Theme.rounded(12, weight: .bold))
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(
                BubbleShape(tailX: side == .leading ? 0.25 : side == .trailing ? 0.75 : 0.5)
                    .fill(.white)
            )
            .scaleEffect(calm ? 0.85 + 0.15 * appear : appear, anchor: .bottom)
            .rotationEffect(.degrees(calm ? 0 : sin(t * 40) * 2.5))
            .offset(x: calm ? 0 : CGFloat(sin(t * 53)) * 1.5, y: calm ? CGFloat(sin(t * 1.4)) * 2 : 0)
            .opacity(fade * (calm ? appear : 1))
            .frame(maxWidth: .infinity, alignment: side == .leading ? .leading : side == .trailing ? .trailing : .center)
            .padding(.horizontal, 8)
    }

    // MARK: - Szene

    private func draw(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        if calm {
            drawCalm(ctx, size: size, t: t)
            return
        }
        let u = size.width / 340   // Basiseinheit, Szene ist für 340 pt Breite entworfen
        let floorY = size.height * 0.74
        let engineCenter = CGPoint(x: size.width * 0.5, y: floorY - 46 * u)

        // Werkstattlicht von oben – flackert hektisch mit
        let flicker = 0.75 + 0.25 * (sin(t * 23) > 0.92 ? 0.0 : 1.0)
        var cone = Path()
        cone.move(to: CGPoint(x: size.width * 0.44, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.56, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.92, y: floorY + 10 * u))
        cone.addLine(to: CGPoint(x: size.width * 0.08, y: floorY + 10 * u))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [accent.opacity(0.18 * flicker), accent.opacity(0.0)]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))

        // Boden
        ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.06, y: floorY - 8 * u, width: size.width * 0.88, height: 22 * u)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.12), .clear]),
                                       center: CGPoint(x: size.width / 2, y: floorY), startRadius: 0, endRadius: size.width * 0.45))

        drawToolCart(ctx, at: CGPoint(x: size.width * 0.06, y: floorY), u: u)
        drawEngine(ctx, center: engineCenter, u: u, t: t)

        // MIA: wühlt panisch in der Werkzeugkiste und wirft alles raus, springt zwischendurch kreischend hoch
        let box = CGRect(x: size.width * 0.8 - 26 * u, y: floorY - 26 * u, width: 52 * u, height: 26 * u)
        drawFlyingTools(ctx, from: CGPoint(x: box.midX, y: box.minY), u: u, t: t)
        drawToolbox(ctx, box, u: u)
        let miaCycle = fmod(t, 3.0)
        let mia = Mechanic(suit: Color(red: 1, green: 0.55, blue: 0.2), hair: Color(red: 0.95, green: 0.45, blue: 0.62),
                           hat: .ponytail, tool: .flashlight, blush: true)
        let miaFeet = CGPoint(x: box.maxX + 12 * u, y: floorY)
        if miaCycle < 2.1 {
            // kopfüber in der Kiste: vorgebeugt, Arme wühlen
            drawMechanic(ctx, mia, feet: miaFeet, scale: u * 0.85, facing: -1, walk: sin(t * 14) * 0.3,
                         armAngle: 0.9 + sin(t * 26) * 0.7, t: t, tilt: 0.75 + sin(t * 9) * 0.08,
                         panic: true, backArm: 0.6 + sin(t * 26 + 2) * 0.9)
        } else {
            // springt hoch: „AAAH!“
            let p = (miaCycle - 2.1) / 0.9
            let lift = CGFloat(sin(p * .pi)) * 22
            drawMechanic(ctx, mia, feet: miaFeet, scale: u * 0.85, facing: -1, walk: 0,
                         armAngle: -1.3 + sin(t * 30) * 0.3, t: t, panic: true,
                         backArm: .pi - 0.4 + sin(t * 30) * 0.3, lift: lift, sweat: true)
            drawPanicMarks(ctx, head: CGPoint(x: miaFeet.x, y: floorY - (78 + lift) * u * 0.85), u: u, t: t, exclaim: true)
        }

        // KENJI: rennt kopflos hin und her, rudert mit den Armen, stolpert, sucht verzweifelt
        let kenji = Mechanic(suit: Color(red: 0.2, green: 0.45, blue: 0.95), hair: Color(red: 0.12, green: 0.1, blue: 0.16),
                             hat: .cap(Color(red: 1, green: 0.35, blue: 0.3)), tool: .wrench, blush: true)
        let ks = u * 0.95
        let left = size.width * 0.1, right = size.width * 0.6
        let k = fmod(t, 6.4)
        if k < 1.4 {
            // sprintet nach rechts
            let x = left + (right - left) * CGFloat(Motion.easeInOut(k / 1.4))
            drawRunner(ctx, kenji, x: x, floorY: floorY, scale: ks, facing: 1, t: t, u: u, speed: 1)
        } else if k < 1.75 {
            // stolpert – Bauchklatscher
            let p = (k - 1.4) / 0.35
            let x = right + 22 * u * CGFloat(Motion.easeOut(p))
            drawMechanic(ctx, kenji, feet: CGPoint(x: x, y: floorY), scale: ks, facing: 1, walk: t * 30,
                         armAngle: -1.4, t: t, tilt: 1.5 * p * p, panic: true, backArm: .pi - 0.3,
                         lift: CGFloat(sin(p * .pi)) * 10)
        } else if k < 2.5 {
            // liegt flach, Beine zappeln, Sternchen kreisen
            let x = right + 22 * u
            drawDust(ctx, at: CGPoint(x: x + 60 * u, y: floorY), u: u, age: (k - 1.75) / 0.75)
            drawMechanic(ctx, kenji, feet: CGPoint(x: x, y: floorY), scale: ks, facing: 1, walk: t * 40,
                         armAngle: -1.5, t: t, tilt: 1.5, panic: true, backArm: .pi - 0.2, dizzy: true)
            drawStars(ctx, around: CGPoint(x: x + 80 * ks, y: floorY - 22 * u), u: u, t: t)
        } else if k < 2.8 {
            // springt wieder auf
            let p = (k - 2.5) / 0.3
            let x = right + 22 * u
            drawMechanic(ctx, kenji, feet: CGPoint(x: x, y: floorY), scale: ks, facing: 1, walk: 0,
                         armAngle: -1.2, t: t, tilt: 1.5 * (1 - Motion.backOut(p)), panic: true,
                         backArm: .pi - 0.6, lift: CGFloat(sin(p * .pi)) * 16)
        } else if k < 4.2 {
            // rennt zurück, noch schneller
            let p = (k - 2.8) / 1.4
            let x = right + 22 * u + (left - right - 22 * u) * CGFloat(Motion.easeInOut(p))
            drawRunner(ctx, kenji, x: x, floorY: floorY, scale: ks, facing: -1, t: t, u: u, speed: 1.3)
        } else {
            // am Werkzeugwagen: hektisch suchen – Kopf links/rechts, hüpfen, Arme hoch
            let facing: CGFloat = fmod(t, 0.5) < 0.25 ? 1 : -1
            let lift = CGFloat(abs(sin(t * 11))) * 7
            drawMechanic(ctx, kenji, feet: CGPoint(x: left + 14 * u, y: floorY), scale: ks, facing: facing, walk: 0,
                         armAngle: -1.1 + sin(t * 18) * 0.5, t: t, panic: true,
                         backArm: .pi - 0.5 + sin(t * 18 + 1) * 0.5, lift: lift, sweat: true)
            drawPanicMarks(ctx, head: CGPoint(x: left + 14 * u, y: floorY - (80 + lift) * ks), u: u, t: t, exclaim: false)
        }

        // Fortschrittsbalken + BOLT, der den Reifen in Todesangst über den Balken schiebt
        let trackY = floorY + 30 * u
        let track = CGRect(x: size.width * 0.08, y: trackY, width: size.width * 0.84, height: 8 * u)
        ctx.fill(Path(roundedRect: track, cornerRadius: 4 * u), with: .color(.white.opacity(0.08)))
        let p: Double
        if let progress {
            p = min(max(progress, 0), 1)
        } else {
            p = 0.5 + 0.5 * sin(t * 1.4)
        }
        let filled = CGRect(x: track.minX, y: track.minY, width: max(track.height, track.width * p), height: track.height)
        ctx.fill(Path(roundedRect: filled, cornerRadius: 4 * u),
                 with: .linearGradient(Gradient(colors: [Theme.accentDeep, accent]),
                                       startPoint: CGPoint(x: filled.minX, y: 0), endPoint: CGPoint(x: filled.maxX, y: 0)))
        // Leuchten ohne Blur-Filter: breiter, halbtransparenter Saum
        ctx.fill(Path(roundedRect: filled.insetBy(dx: -3 * u, dy: -3 * u), cornerRadius: 7 * u), with: .color(accent.opacity(0.18)))
        ctx.fill(Path(roundedRect: filled.insetBy(dx: -6 * u, dy: -6 * u), cornerRadius: 10 * u), with: .color(accent.opacity(0.08)))

        let tireR = 13 * u
        let jitter = CGFloat(sin(t * 47)) * 1.2 * u
        let tireCenter = CGPoint(x: filled.maxX, y: track.midY - tireR - 2 * u)
        drawTire(ctx, center: tireCenter, radius: tireR, rotation: Double(filled.maxX / tireR) + t * 6)
        let bolt = Mechanic(suit: Color(red: 0.25, green: 0.8, blue: 0.55), hair: Color(red: 0.98, green: 0.82, blue: 0.3),
                            hat: .spiky, tool: .none, blush: true)
        let boltFeet = CGPoint(x: tireCenter.x - 30 * u + jitter, y: track.midY - 2 * u)
        drawSpeedLines(ctx, behind: CGPoint(x: boltFeet.x - 12 * u, y: boltFeet.y - 30 * u), facing: 1, u: u * 0.6, t: t)
        drawMechanic(ctx, bolt, feet: boltFeet, scale: u * 0.62, facing: 1, walk: t * 22,
                     armAngle: 0.1 + sin(t * 30) * 0.08, t: t, tilt: 0.35, panic: true, sweat: true)
    }

    /// Kenji im Vollsprint: Arme wie Windmühlen, Staubwolken, Speedlines.
    private func drawRunner(_ ctx: GraphicsContext, _ m: Mechanic, x: CGFloat, floorY: CGFloat, scale: CGFloat,
                            facing: CGFloat, t: Double, u: CGFloat, speed: Double) {
        drawSpeedLines(ctx, behind: CGPoint(x: x - facing * 20 * u, y: floorY - 50 * u), facing: facing, u: u, t: t)
        drawDust(ctx, at: CGPoint(x: x - facing * 16 * u, y: floorY), u: u, age: fmod(t * 4, 1))
        drawMechanic(ctx, m, feet: CGPoint(x: x, y: floorY), scale: scale, facing: facing, walk: t * 26 * speed,
                     armAngle: -0.4 + sin(t * 24 * speed) * 1.5, t: t, tilt: 0.28, panic: true,
                     backArm: .pi * 0.75 + sin(t * 24 * speed + 2) * 1.6, sweat: true)
    }

    // MARK: - Anime-Effekte

    private func drawSpeedLines(_ ctx: GraphicsContext, behind point: CGPoint, facing: CGFloat, u: CGFloat, t: Double) {
        for i in 0..<5 {
            let y = point.y + CGFloat(i - 2) * 9 * u
            let len = (18 + 14 * abs(sin(t * 17 + Double(i) * 1.7))) * Double(u)
            var line = Path()
            line.move(to: CGPoint(x: point.x, y: y))
            line.addLine(to: CGPoint(x: point.x - facing * CGFloat(len), y: y))
            ctx.stroke(line, with: .color(.white.opacity(0.45)), style: StrokeStyle(lineWidth: 1.6 * u, lineCap: .round))
        }
    }

    private func drawDust(_ ctx: GraphicsContext, at point: CGPoint, u: CGFloat, age: Double) {
        for i in 0..<3 {
            let r = (4 + 7 * age + Double(i) * 2) * Double(u)
            let x = point.x + CGFloat(i - 1) * 8 * u
            let y = point.y - CGFloat(age) * 8 * u - CGFloat(i) * 3 * u
            ctx.fill(Path(ellipseIn: CGRect(x: x - CGFloat(r), y: y - CGFloat(r), width: CGFloat(r * 2), height: CGFloat(r * 2))),
                     with: .color(Color(white: 0.75).opacity(0.35 * (1 - age))))
        }
    }

    /// Kreisende Sternchen über dem Kopf (nach dem Sturz).
    private func drawStars(_ ctx: GraphicsContext, around center: CGPoint, u: CGFloat, t: Double) {
        for i in 0..<3 {
            let a = t * 6 + Double(i) * 2.1
            let p = CGPoint(x: center.x + CGFloat(cos(a)) * 18 * u, y: center.y + CGFloat(sin(a)) * 6 * u)
            var star = Path()
            for k in 0..<10 {
                let r = (k % 2 == 0 ? 5.5 : 2.3) * Double(u)
                let ang = Double(k) * .pi / 5 - .pi / 2 + t * 4
                let q = CGPoint(x: p.x + CGFloat(cos(ang) * r), y: p.y + CGFloat(sin(ang) * r))
                if k == 0 { star.move(to: q) } else { star.addLine(to: q) }
            }
            star.closeSubpath()
            ctx.fill(star, with: .color(Color(red: 1, green: 0.88, blue: 0.3)))
        }
    }

    /// Anime-Stresslinien am Kopf, optional mit „!!“.
    private func drawPanicMarks(_ ctx: GraphicsContext, head: CGPoint, u: CGFloat, t: Double, exclaim: Bool) {
        let pulse = 1 + 0.15 * sin(t * 30)
        for i in 0..<3 {
            let a = -Double.pi / 2 + Double(i - 1) * 0.55
            var l = Path()
            l.move(to: CGPoint(x: head.x + CGFloat(cos(a)) * 26 * u, y: head.y + CGFloat(sin(a)) * 26 * u))
            l.addLine(to: CGPoint(x: head.x + CGFloat(cos(a) * 36 * pulse) * u, y: head.y + CGFloat(sin(a) * 36 * pulse) * u))
            ctx.stroke(l, with: .color(.white.opacity(0.85)), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }
        if exclaim {
            ctx.draw(Text("!!").font(.system(size: 20 * u, weight: .black)).foregroundColor(Theme.severe),
                     at: CGPoint(x: head.x + 30 * u, y: head.y - 26 * u + CGFloat(sin(t * 25)) * 2 * u))
        }
    }

    /// Werkzeug, das Mia im hohen Bogen aus der Kiste wirft.
    private func drawFlyingTools(_ ctx: GraphicsContext, from origin: CGPoint, u: CGFloat, t: Double) {
        let interval = 0.42
        let current = floor(t / interval)
        for k in 0..<4 {
            let n = current - Double(k)
            let age = t - n * interval
            guard age >= 0, age < 1.4 else { continue }
            let seed = sin(n * 12.9898) * 43758.5453
            let r = seed - floor(seed)
            let vx = (-60 - 70 * r) * Double(u)
            let vy = (-150 - 50 * r) * Double(u)
            let g = 260.0 * Double(u)
            let p = CGPoint(x: origin.x + CGFloat(vx * age), y: origin.y + CGFloat(vy * age + g * age * age))
            var c = ctx
            c.opacity = 1 - max(0, (age - 1.1) / 0.3)
            c.translateBy(x: p.x, y: p.y)
            c.rotate(by: .radians(age * 14 * (r > 0.5 ? 1 : -1)))
            c.scaleBy(x: u, y: u)
            let ink = GraphicsContext.Shading.color(Self.outline)
            switch Int(r * 3) {
            case 0: // Schraubenzieher
                let grip = Path(roundedRect: CGRect(x: -10, y: -3.5, width: 10, height: 7), cornerRadius: 3)
                c.fill(grip, with: .color(Color(red: 0.9, green: 0.2, blue: 0.25)))
                c.stroke(grip, with: ink, lineWidth: 1.5)
                c.fill(Path(CGRect(x: 0, y: -1.2, width: 14, height: 2.4)), with: .color(Color(white: 0.8)))
            case 1: // Schraubenschlüssel
                c.fill(Path(roundedRect: CGRect(x: -10, y: -2.5, width: 20, height: 5), cornerRadius: 2.5), with: .color(Color(white: 0.8)))
                c.stroke(Path(ellipseIn: CGRect(x: 8, y: -5, width: 10, height: 10)), with: .color(Color(white: 0.8)), lineWidth: 3)
            default: // Mutter
                var hex = Path()
                for i in 0..<6 {
                    let a = Double(i) * .pi / 3
                    let q = CGPoint(x: cos(a) * 6, y: sin(a) * 6)
                    if i == 0 { hex.move(to: q) } else { hex.addLine(to: q) }
                }
                hex.closeSubpath()
                c.fill(hex, with: .color(Color(white: 0.7)))
                c.stroke(hex, with: ink, lineWidth: 1.4)
                c.fill(Path(ellipseIn: CGRect(x: -2.2, y: -2.2, width: 4.4, height: 4.4)), with: .color(Color(white: 0.2)))
            }
        }
    }

    // MARK: - Figuren

    enum Hat { case cap(Color), ponytail, spiky }
    enum Tool { case wrench, flashlight, cloth, sponge, broom, none }

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
                              walk: Double, armAngle: Double, t: Double, bob: Double = 0, tilt: Double = 0,
                              panic: Bool = false, backArm: Double? = nil, lift: CGFloat = 0, sweat: Bool = false,
                              dizzy: Bool = false, serene: Bool = false) {
        // Schatten
        let shadowW = 36 * scale * (1 - min(lift, 30) / 60)
        base.fill(Path(ellipseIn: CGRect(x: feet.x - shadowW / 2 + CGFloat(sin(tilt)) * 40 * scale * facing,
                                         y: feet.y - 3 * scale, width: shadowW, height: 7 * scale)),
                  with: .color(.black.opacity(0.35)))

        var c = base
        let bounce = walk == 0 ? bob : -abs(sin(walk)) * 3
        c.translateBy(x: feet.x, y: feet.y + (CGFloat(bounce) - lift) * scale)
        c.rotate(by: .radians(tilt * Double(facing)))
        c.scaleBy(x: facing * scale, y: scale)
        let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
        let ink = GraphicsContext.Shading.color(Self.outline)

        func limb(from: CGPoint, angle: Double, length: CGFloat, width: CGFloat, color: Color) -> CGPoint {
            let end = CGPoint(x: from.x + CGFloat(sin(angle)) * length, y: from.y + CGFloat(cos(angle)) * length)
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
        _ = limb(from: CGPoint(x: -9, y: -48), angle: backArm ?? (walk == 0 ? -0.25 : -sin(walk) * 0.6), length: 18, width: 7, color: suitDark)

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

        // Augen: normal große Anime-Augen; in Panik weiße Kulleraugen mit winzigen zitternden Pupillen; nach Sturz Spiralen
        let blink = fmod(t + Double(feet.x) * 0.01, 3.7) < 0.12
        for ex in [CGFloat(-3), CGFloat(11)] {
            if dizzy {
                var spiral = Path()
                for i in 0...20 {
                    let a = Double(i) * 0.6 + t * 12
                    let r = 0.25 * Double(i)
                    let q = CGPoint(x: ex + CGFloat(cos(a) * r), y: -72 + CGFloat(sin(a) * r))
                    if i == 0 { spiral.move(to: q) } else { spiral.addLine(to: q) }
                }
                c.stroke(spiral, with: ink, lineWidth: 1.4)
            } else if serene {
                // zufrieden geschlossene Augen ^ ^
                var arc = Path()
                arc.move(to: CGPoint(x: ex - 4.5, y: -70))
                arc.addQuadCurve(to: CGPoint(x: ex + 4.5, y: -70), control: CGPoint(x: ex, y: -77))
                c.stroke(arc, with: ink, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
            } else if panic {
                let eye = CGRect(x: ex - 5, y: -80, width: 10, height: 13)
                c.fill(Path(ellipseIn: eye), with: .color(.white))
                c.stroke(Path(ellipseIn: eye), with: ink, lineWidth: 1.8)
                let jx = CGFloat(sin(t * 61 + Double(ex))) * 1.4, jy = CGFloat(cos(t * 53)) * 1.2
                c.fill(Path(ellipseIn: CGRect(x: ex - 1.6 + jx, y: -74.5 + jy, width: 3.2, height: 3.2)), with: ink)
            } else if blink {
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
            let blushColor = panic ? Color.blue.opacity(0.35) : Color.pink.opacity(0.45)
            c.fill(Path(ellipseIn: CGRect(x: -9, y: -66, width: 6, height: 3)), with: .color(blushColor))
            c.fill(Path(ellipseIn: CGRect(x: 14, y: -66, width: 6, height: 3)), with: .color(blushColor))
        }
        if panic || dizzy {
            // weit aufgerissener Schreimund mit Zunge, „wackelt“ beim Schreien
            let open = 5 + 2 * CGFloat(abs(sin(t * 28)))
            let mouthRect = CGRect(x: 1, y: -66, width: 11, height: open)
            c.fill(Path(roundedRect: mouthRect, cornerRadius: 3), with: .color(Color(red: 0.35, green: 0.05, blue: 0.1)))
            c.fill(Path(ellipseIn: CGRect(x: 4, y: mouthRect.maxY - 3, width: 6, height: 3)), with: .color(Color(red: 1, green: 0.45, blue: 0.5)))
            c.stroke(Path(roundedRect: mouthRect, cornerRadius: 3), with: ink, lineWidth: 1.6)
            // blaue Schreck-Schraffur auf der Stirn
            for i in 0..<3 {
                var l = Path()
                let x = CGFloat(-6 + i * 6)
                l.move(to: CGPoint(x: x, y: -90))
                l.addLine(to: CGPoint(x: x, y: -84))
                c.stroke(l, with: .color(Color.blue.opacity(0.5)), lineWidth: 1.4)
            }
        } else if armAngle > 0.9 && m.tool == .wrench {
            c.fill(Path(ellipseIn: CGRect(x: 5, y: -65, width: 4, height: 4)), with: ink)
        } else {
            var mouth = Path()
            mouth.move(to: CGPoint(x: 3, y: -64))
            mouth.addQuadCurve(to: CGPoint(x: 10, y: -64), control: CGPoint(x: 6.5, y: -60))
            c.stroke(mouth, with: ink, style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
        }
        // Schweißtropfen – in Panik fliegen mehrere vom Kopf weg
        if sweat || panic {
            for i in 0..<(panic ? 3 : 1) {
                let drop = fmod(t * (panic ? 2.4 : 1.5) + Double(i) / 3, 1)
                let side: CGFloat = i == 1 ? 1 : -1
                let dx = side * (22 + CGFloat(drop) * 14), dy = -90 - CGFloat(sin(drop * .pi)) * 12 + CGFloat(drop) * 10
                var d = Path()
                d.move(to: CGPoint(x: dx, y: dy - 5))
                d.addQuadCurve(to: CGPoint(x: dx, y: dy + 4), control: CGPoint(x: dx - 5, y: dy + 2))
                d.addQuadCurve(to: CGPoint(x: dx, y: dy - 5), control: CGPoint(x: dx + 5, y: dy + 2))
                c.fill(d, with: .color(Color(red: 0.6, green: 0.85, blue: 1).opacity(1 - drop)))
                c.stroke(d, with: .color(Self.outline.opacity(0.6 * (1 - drop))), lineWidth: 1)
            }
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
        case .cloth:
            let cloth = Path(roundedRect: CGRect(x: -2, y: -7, width: 15, height: 13), cornerRadius: 3)
            tool.fill(cloth, with: .color(Color(red: 0.62, green: 0.9, blue: 1)))
            tool.stroke(cloth, with: ink, lineWidth: 1.6)
            for i in 0..<2 {
                var fold = Path()
                fold.move(to: CGPoint(x: 2 + CGFloat(i) * 5, y: -5))
                fold.addLine(to: CGPoint(x: 1 + CGFloat(i) * 5, y: 4))
                tool.stroke(fold, with: .color(.white.opacity(0.7)), lineWidth: 1)
            }
        case .sponge:
            let sponge = Path(roundedRect: CGRect(x: -1, y: -6, width: 16, height: 11), cornerRadius: 3.5)
            tool.fill(sponge, with: .color(Color(red: 1, green: 0.86, blue: 0.3)))
            tool.stroke(sponge, with: ink, lineWidth: 1.6)
            for (x, y) in [(3.0, -2.0), (8.0, 1.0), (11.0, -3.0)] {
                tool.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 2.2, height: 2.2)), with: .color(Color(red: 0.85, green: 0.65, blue: 0.15)))
            }
        case .broom:
            var stick = Path()
            stick.move(to: CGPoint(x: -14, y: 0))
            stick.addLine(to: CGPoint(x: 30, y: 0))
            tool.stroke(stick, with: ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
            tool.stroke(stick, with: .color(Color(red: 0.75, green: 0.5, blue: 0.28)), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
            var bristles = Path()
            bristles.move(to: CGPoint(x: 29, y: -4))
            bristles.addLine(to: CGPoint(x: 42, y: -9))
            bristles.addLine(to: CGPoint(x: 42, y: 9))
            bristles.addLine(to: CGPoint(x: 29, y: 4))
            bristles.closeSubpath()
            tool.fill(bristles, with: .color(Color(red: 0.98, green: 0.78, blue: 0.35)))
            tool.stroke(bristles, with: ink, lineWidth: 1.6)
        case .none:
            break
        }
    }

    // MARK: - Einzelporträt

    /// Kenji, gut gelaunt mit erhobenem Schraubenschlüssel – für Hinweise außerhalb der Ladeanimation.
    func drawPortrait(_ ctx: GraphicsContext, size: CGSize) {
        let kenji = Mechanic(suit: Color(red: 0.2, green: 0.45, blue: 0.95), hair: Color(red: 0.12, green: 0.1, blue: 0.16),
                             hat: .cap(Color(red: 1, green: 0.35, blue: 0.3)), tool: .wrench, blush: true)
        let scale = size.height / 118
        drawMechanic(ctx, kenji, feet: CGPoint(x: size.width * 0.42, y: size.height - 4 * scale), scale: scale, facing: 1,
                     walk: 0, armAngle: -0.9, t: 0.5, backArm: -0.3)
    }

    // MARK: - Ruhemodus (Löschen)

    /// Die Crew putzt in aller Ruhe: Kenji wischt mit dem Tuch, Mia schrubbt mit dem Schwamm, Bolt fegt den Balken.
    /// Augen zufrieden geschlossen, Seifenblasen, Glitzer, Summen.
    private func drawCalm(_ ctx: GraphicsContext, size: CGSize, t: Double) {
        let u = size.width / 340
        let floorY = size.height * 0.74
        let engineCenter = CGPoint(x: size.width * 0.5, y: floorY - 46 * u)
        let calmGreen = Theme.ok

        // Weiches, warmes Licht – kein Flackern
        let breathe = 0.85 + 0.15 * sin(t * 1.2)
        var cone = Path()
        cone.move(to: CGPoint(x: size.width * 0.44, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.56, y: 0))
        cone.addLine(to: CGPoint(x: size.width * 0.9, y: floorY + 10 * u))
        cone.addLine(to: CGPoint(x: size.width * 0.1, y: floorY + 10 * u))
        cone.closeSubpath()
        ctx.fill(cone, with: .linearGradient(Gradient(colors: [calmGreen.opacity(0.16 * breathe), Theme.violet.opacity(0.04), .clear]),
                                             startPoint: .zero, endPoint: CGPoint(x: 0, y: floorY)))
        ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.06, y: floorY - 8 * u, width: size.width * 0.88, height: 22 * u)),
                 with: .radialGradient(Gradient(colors: [Color.white.opacity(0.12), .clear]),
                                       center: CGPoint(x: size.width / 2, y: floorY), startRadius: 0, endRadius: size.width * 0.45))

        // Glänzender, ruhiger Motor
        ctx.fill(Path(ellipseIn: CGRect(x: engineCenter.x - 90 * u, y: engineCenter.y - 70 * u, width: 180 * u, height: 140 * u)),
                 with: .radialGradient(Gradient(colors: [calmGreen.opacity(0.22 * breathe), calmGreen.opacity(0)]),
                                       center: engineCenter, startRadius: 0, endRadius: 90 * u))
        drawEngine(ctx, center: engineCenter, u: u, t: t, calm: true)

        // Glitzer rund um den Motor
        for i in 0..<7 {
            let phase = fmod(t * 0.55 + Double(i) * 0.37, 1)
            let a = Double(i) * 2.1
            let p = CGPoint(x: engineCenter.x + CGFloat(cos(a)) * (40 + 18 * CGFloat(i % 3)) * u,
                            y: engineCenter.y - 10 * u + CGFloat(sin(a)) * 30 * u)
            drawSparkle(ctx, at: p, size: (3 + 5 * CGFloat(sin(phase * .pi))) * u, alpha: sin(phase * .pi))
        }

        // KENJI: wischt mit dem Tuch in kleinen Kreisen, summt
        let kenji = Mechanic(suit: Color(red: 0.2, green: 0.45, blue: 0.95), hair: Color(red: 0.12, green: 0.1, blue: 0.16),
                             hat: .cap(Color(red: 1, green: 0.35, blue: 0.3)), tool: .cloth, blush: true)
        let kenjiFeet = CGPoint(x: engineCenter.x - 96 * u, y: floorY)
        drawMechanic(ctx, kenji, feet: kenjiFeet, scale: u * 0.95, facing: 1, walk: 0,
                     armAngle: 0.15 + 0.35 * sin(t * 2.6), t: t, bob: sin(t * 1.3) * 1.2,
                     tilt: 0.04 * sin(t * 1.3), backArm: -0.2 + 0.1 * sin(t * 1.3), serene: true)
        drawNotes(ctx, from: CGPoint(x: kenjiFeet.x - 6 * u, y: floorY - 98 * u), u: u, t: t)

        // MIA: schrubbt mit dem Schwamm, Seifenblasen steigen auf
        let mia = Mechanic(suit: Color(red: 1, green: 0.55, blue: 0.2), hair: Color(red: 0.95, green: 0.45, blue: 0.62),
                           hat: .ponytail, tool: .sponge, blush: true)
        let miaFeet = CGPoint(x: engineCenter.x + 94 * u, y: floorY)
        drawMechanic(ctx, mia, feet: miaFeet, scale: u * 0.85, facing: -1, walk: 0,
                     armAngle: 0.3 + 0.3 * sin(t * 3.1 + 1), t: t, bob: sin(t * 1.3 + 2) * 1.2,
                     tilt: 0.05 * sin(t * 1.1 + 1), serene: true)
        drawSoapBubbles(ctx, from: CGPoint(x: miaFeet.x - 26 * u, y: engineCenter.y), u: u, t: t)

        // Balken: ein ruhiges, glänzendes Band, das Bolt sauber fegt
        let trackY = floorY + 30 * u
        let track = CGRect(x: size.width * 0.08, y: trackY, width: size.width * 0.84, height: 8 * u)
        ctx.fill(Path(roundedRect: track, cornerRadius: 4 * u), with: .color(.white.opacity(0.08)))
        let sweep = 0.5 + 0.42 * sin(t * 0.55)
        let boltX = track.minX + track.width * CGFloat(sweep)
        let facing: CGFloat = cos(t * 0.55) >= 0 ? 1 : -1
        let clean = CGRect(x: track.minX, y: track.minY, width: track.width, height: track.height)
        ctx.fill(Path(roundedRect: clean, cornerRadius: 4 * u),
                 with: .linearGradient(Gradient(colors: [.clear, calmGreen.opacity(0.7), Theme.accent, calmGreen.opacity(0.7), .clear]),
                                       startPoint: CGPoint(x: boltX - track.width * 0.35, y: 0),
                                       endPoint: CGPoint(x: boltX + track.width * 0.35, y: 0)))
        ctx.fill(Path(ellipseIn: CGRect(x: boltX - 50 * u, y: track.minY - 10 * u, width: 100 * u, height: track.height + 20 * u)),
                 with: .radialGradient(Gradient(colors: [calmGreen.opacity(0.4), calmGreen.opacity(0)]),
                                       center: CGPoint(x: boltX, y: track.midY), startRadius: 0, endRadius: 50 * u))

        // BOLT: fegt gemütlich hin und her
        let bolt = Mechanic(suit: Color(red: 0.25, green: 0.8, blue: 0.55), hair: Color(red: 0.98, green: 0.82, blue: 0.3),
                            hat: .spiky, tool: .broom, blush: true)
        drawMechanic(ctx, bolt, feet: CGPoint(x: boltX - facing * 14 * u, y: track.midY - 2 * u), scale: u * 0.62, facing: facing,
                     walk: t * 5, armAngle: 1.05 + 0.18 * sin(t * 5), t: t, serene: true)
        drawSparkle(ctx, at: CGPoint(x: boltX + facing * 16 * u, y: track.minY - 6 * u),
                    size: (2 + 3 * CGFloat(abs(sin(t * 4)))) * u, alpha: 0.9)
    }

    /// Vierzackiger Glitzerstern.
    private func drawSparkle(_ ctx: GraphicsContext, at p: CGPoint, size s: CGFloat, alpha: Double) {
        guard alpha > 0.02 else { return }
        var star = Path()
        star.move(to: CGPoint(x: p.x, y: p.y - s))
        star.addQuadCurve(to: CGPoint(x: p.x + s, y: p.y), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x, y: p.y + s), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x - s, y: p.y), control: p)
        star.addQuadCurve(to: CGPoint(x: p.x, y: p.y - s), control: p)
        ctx.fill(star, with: .color(.white.opacity(alpha)))
    }

    /// Schillernde Seifenblasen, die langsam aufsteigen.
    private func drawSoapBubbles(_ ctx: GraphicsContext, from origin: CGPoint, u: CGFloat, t: Double) {
        for i in 0..<5 {
            let life = fmod(t * 0.35 + Double(i) / 5, 1)
            let r = (3 + 4 * CGFloat(i % 3)) * u * CGFloat(0.6 + 0.4 * life)
            let x = origin.x + CGFloat(sin(t * 1.4 + Double(i) * 1.7)) * 10 * u - CGFloat(i) * 4 * u
            let y = origin.y - CGFloat(life) * 90 * u
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            let alpha = sin(life * .pi)
            ctx.stroke(Path(ellipseIn: rect), with: .linearGradient(
                Gradient(colors: [Theme.accent.opacity(0.8 * alpha), Theme.magenta.opacity(0.6 * alpha), Theme.violet.opacity(0.7 * alpha)]),
                startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.maxY)), lineWidth: 1.2 * u)
            ctx.fill(Path(ellipseIn: CGRect(x: rect.minX + r * 0.45, y: rect.minY + r * 0.35, width: r * 0.45, height: r * 0.35)),
                     with: .color(.white.opacity(0.7 * alpha)))
        }
    }

    /// Kleine Noten – jemand summt zufrieden.
    private func drawNotes(_ ctx: GraphicsContext, from origin: CGPoint, u: CGFloat, t: Double) {
        for i in 0..<2 {
            let life = fmod(t * 0.4 + Double(i) * 0.5, 1)
            let p = CGPoint(x: origin.x - CGFloat(life) * 16 * u + CGFloat(sin(life * 6)) * 4 * u,
                            y: origin.y - CGFloat(life) * 34 * u)
            let note = Text(i == 0 ? "♪" : "♫")
                .font(.system(size: 14 * u, weight: .bold))
                .foregroundColor(Theme.ok.opacity(sin(life * .pi)))
            ctx.draw(note, at: p)
        }
    }

    // MARK: - Requisiten

    private func drawEngine(_ ctx: GraphicsContext, center: CGPoint, u: CGFloat, t: Double, calm: Bool = false) {
        var c = ctx
        // Motor bockt immer wieder heftig – im Ruhemodus läuft er ganz ruhig
        let rattle = calm ? 0.0 : 0.6 + 2.2 * max(0, sin(t * 2.3))
        c.translateBy(x: center.x + CGFloat(sin(t * 38) * rattle) * u, y: center.y + CGFloat(cos(t * 31) * rattle * 0.8) * u)
        c.rotate(by: .radians(sin(t * 29) * 0.02 * rattle))
        c.scaleBy(x: u, y: u)
        let ink = GraphicsContext.Shading.color(Self.outline)
        let line = StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)

        // Dampfwölkchen (nicht beim Putzen)
        for i in 0..<(calm ? 0 : 3) {
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
            let len = CGFloat(8 + 10 * abs(sin(t * 40 + Double(i)))) * u
            var p = Path()
            p.move(to: point)
            p.addLine(to: CGPoint(x: point.x + CGFloat(cos(angle)) * len, y: point.y + CGFloat(sin(angle)) * len))
            ctx.stroke(p, with: .color(Color(red: 1, green: 0.85, blue: 0.3)), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
        }
        ctx.fill(Path(ellipseIn: CGRect(x: point.x - 14 * u, y: point.y - 14 * u, width: 28 * u, height: 28 * u)),
                 with: .radialGradient(Gradient(colors: [Color.yellow.opacity(0.8), Color.yellow.opacity(0)]),
                                       center: point, startRadius: 0, endRadius: 14 * u))
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
            tread.move(to: CGPoint(x: CGFloat(cos(a)) * radius * 0.7, y: CGFloat(sin(a)) * radius * 0.7))
            tread.addLine(to: CGPoint(x: CGFloat(cos(a)) * radius * 0.95, y: CGFloat(sin(a)) * radius * 0.95))
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
