import SwiftUI

/// Farben, Schriften und wiederverwendbare Effekte von RideReader.
enum Theme {
    // Markenfarben kommen aus dem gewählten Design (ThemeStore) – Original, M, AMG, S-Line oder eigenes.
    static var background: Color { Palette.current.background }
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.105)
    /// Hauptfarbe des Designs (Original: elektrisches Cyan)
    static var accent: Color { Palette.current.accent }
    static var accentDeep: Color { Palette.current.accentDeep }
    static let ok = Color(red: 0.32, green: 0.95, blue: 0.62)
    /// Orange = Fehler
    static let fault = Color(red: 1.0, green: 0.6, blue: 0.14)
    /// Rot = schwerwiegender Fehler
    static let severe = Color(red: 1.0, green: 0.25, blue: 0.3)

    static var violet: Color { Palette.current.violet }
    static var magenta: Color { Palette.current.magenta }

    /// Markenverlauf (Original: Cyan → Blau → Violett → Magenta)
    static var brandColors: [Color] { [accent, accentDeep, violet, magenta] }
    /// Geschlossener Verlauf für Ringe (Anfang = Ende)
    static var brandLoop: [Color] { [accent, accentDeep, violet, magenta, accent] }

    /// Gefüllte Knöpfe (Tab-Leiste, Haupt-Aktionen) – Schrift darauf: `onButton`
    static var buttonGradient: LinearGradient {
        let p = Palette.current
        let colors = p.buttonColors.isEmpty ? [p.accentDeep, p.violet, p.magenta.opacity(0.9)] : p.buttonColors
        return LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing)
    }

    static var onButton: Color { Palette.current.onButton }

    static var brandGradient: LinearGradient {
        LinearGradient(colors: [accent, violet, magenta], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Verlauf des Schriftzugs: Weiß läuft in die Markenfarben aus.
    static var logoGradient: LinearGradient {
        LinearGradient(colors: [.white, accent, violet, magenta], startPoint: .leading, endPoint: .trailing)
    }

    /// Verlauf für Überschriften
    static var titleGradient: LinearGradient {
        LinearGradient(colors: [.white, Palette.current.titleMid, violet.opacity(0.95)],
                       startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func color(_ severity: Severity?) -> Color {
        switch severity {
        case .severe: return severe
        case .fault: return fault
        case nil: return ok
        }
    }

    /// Breite, schwere Display-Schrift für Überschriften und das Logo.
    static func display(_ size: CGFloat, weight: Font.Weight = .black) -> Font {
        .system(size: size, weight: weight).width(.expanded)
    }

    /// Freundliche, runde Schrift für Fließtext mit Gewicht.
    static func rounded(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

// MARK: - Übergänge

private struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        // Bewusst ohne Weichzeichner: Blur über ganze Seiten ruckelt auf älteren iPhones.
        content
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? 0.97 : 1)
    }
}

extension AnyTransition {
    /// Unschärfe + Ausblenden + leichtes Skalieren – der Standard-Übergang der App.
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }

    /// Von unten hereinfahren mit Unschärfe.
    static var blurRise: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
            .combined(with: .offset(y: 28))
    }
}

// MARK: - Flächen

extension View {
    /// Dunkle Glasfläche mit feiner Lichtkante, optional farbig getönt.
    func card(cornerRadius: CGFloat = 26, tint: Color? = nil) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape
                    .fill(LinearGradient(colors: [Color.white.opacity(0.085), Color.white.opacity(0.035)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .background(shape.fill(Theme.surface.opacity(0.72)))
                    .overlay(
                        shape.fill(
                            RadialGradient(colors: [(tint ?? Theme.accent).opacity(tint == nil ? 0.07 : 0.18), .clear],
                                           center: .topLeading, startRadius: 0, endRadius: 260))
                    )
                    .overlay(
                        shape.fill(
                            RadialGradient(colors: [Theme.violet.opacity(0.08), .clear],
                                           center: .bottomTrailing, startRadius: 0, endRadius: 240))
                    )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [(tint ?? Theme.accent).opacity(tint == nil ? 0.3 : 0.55),
                                            Theme.violet.opacity(0.12), .white.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
        // Kein .shadow: Schatten werden beim Scrollen in jedem Bild neu berechnet.
    }

    /// Glas-Optik für schwebende Elemente (Tab-Leiste, Pop-ups). Absichtlich ohne Live-Hintergrund-Blur
    /// (Material) – der müsste über animierten Flächen in jedem Bild neu gerechnet werden.
    func frosted(cornerRadius: CGFloat = 30) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(
                shape.fill(LinearGradient(colors: [Color(red: 0.15, green: 0.16, blue: 0.22).opacity(0.94),
                                                   Color(red: 0.07, green: 0.075, blue: 0.11).opacity(0.96)],
                                          startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
    }

    /// Eingabefeld für Hex-Werte: Großbuchstaben, keine Autokorrektur.
    func hexInput() -> some View {
        #if os(iOS)
        return self
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        #else
        return self.autocorrectionDisabled().font(.body.monospaced())
        #endif
    }
}

/// Gedrückt: leicht kleiner und heller – für alle großen Knöpfe.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .brightness(configuration.isPressed ? 0.06 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Dunkler Hintergrund mit langsam wandernden Farbflecken in den Markenfarben; `tint` zeigt den Zustand.
/// Performance: Die Flecken sind weiche Radialverläufe (kein Blur-Filter), liegen im Overlay (verbreitern das
/// Layout nicht) und bewegen sich nur per Verschiebung – das kostet fast nichts, auch auf alten iPhones.
/// `dimmed` = Fehleransicht: Hintergrund tritt weich und abgedunkelt zurück.
struct AmbientBackground: View {
    var tint: Color = Theme.accent
    var dimmed = false
    @State private var drift = false

    var body: some View {
        Theme.background
            .overlay {
                ZStack {
                    blob(tint.opacity(0.34), size: 680, x: drift ? -70 : -150, y: drift ? -250 : -330)
                    blob(Theme.violet.opacity(0.28), size: 620, x: drift ? 170 : 110, y: drift ? -60 : 30)
                    blob(Theme.magenta.opacity(0.17), size: 600, x: drift ? -110 : -40, y: drift ? 330 : 250)
                    blob(Theme.accentDeep.opacity(0.24), size: 560, x: drift ? 130 : 180, y: drift ? 260 : 350)
                }
                .scaleEffect(dimmed ? 1.15 : 1)
                .animation(.easeInOut(duration: 9).repeatForever(autoreverses: true), value: drift)
            }
            .overlay(GridFloor().opacity(dimmed ? 0 : 0.35))
            .overlay(Color.black.opacity(dimmed ? 0.35 : 0))
            .clipped()
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.8), value: tint)
            .animation(.easeInOut(duration: 0.6), value: dimmed)
            .onAppear { drift = true }
            .allowsHitTesting(false)
    }

    private func blob(_ color: Color, size: CGFloat, x: CGFloat, y: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color, color.opacity(0.45), color.opacity(0)],
                                 center: .center, startRadius: 0, endRadius: size / 2))
            .frame(width: size, height: size)
            .drawingGroup()          // einmal als Textur gerendert, danach nur noch verschoben
            .offset(x: x, y: y)
    }
}

/// Weicher Lichtschein ohne Blur-Filter (Radialverlauf) – Ersatz für teure .shadow/.blur-Glows.
struct Glow: View {
    var color: Color
    var opacity: Double = 0.6

    var body: some View {
        GeometryReader { geo in
            let radius = max(geo.size.width, geo.size.height) / 2
            Ellipse()
                .fill(RadialGradient(colors: [color.opacity(opacity), color.opacity(opacity * 0.35), color.opacity(0)],
                                     center: .center, startRadius: 0, endRadius: radius))
        }
        .allowsHitTesting(false)
    }
}

/// Perspektivisches Bodenraster für den Studio-Look.
struct GridFloor: View {
    var body: some View {
        Canvas { context, size in
            let horizon = size.height * 0.58
            let vanish = CGPoint(x: size.width / 2, y: horizon - 60)
            var lines = Path()
            for i in -10...10 {
                let x = size.width / 2 + CGFloat(i) * size.width / 7
                lines.move(to: CGPoint(x: x, y: size.height))
                lines.addLine(to: vanish)
            }
            for i in 0..<12 {
                let p = pow(CGFloat(i) / 12, 2)
                let y = horizon + (size.height - horizon) * p
                lines.move(to: CGPoint(x: 0, y: y))
                lines.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.clip(to: Path(CGRect(x: 0, y: horizon, width: size.width, height: size.height - horizon)))
            context.stroke(lines, with: .linearGradient(
                Gradient(colors: [.white.opacity(0), .white.opacity(0.07)]),
                startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: size.height)), lineWidth: 0.7)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Seitenaufbau

private struct PageRevealedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// false, solange das Intro läuft – danach bauen sich die Seiten gestaffelt auf.
    var pageRevealed: Bool {
        get { self[PageRevealedKey.self] }
        set { self[PageRevealedKey.self] = newValue }
    }
}

/// Element gleitet nach dem Intro gestaffelt aus der Unschärfe nach oben.
private struct BuildIn: ViewModifier {
    @Environment(\.pageRevealed) private var revealed
    let delay: Double
    let rise: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed ? 0 : rise)
            .scaleEffect(revealed ? 1 : 0.97)
            .animation(.spring(response: 0.75, dampingFraction: 0.86).delay(revealed ? delay : 0), value: revealed)
    }
}

extension View {
    /// Gestaffelter Aufbau: `index` bestimmt die Reihenfolge.
    func buildIn(_ index: Int, rise: CGFloat = 26) -> some View {
        modifier(BuildIn(delay: 0.12 + Double(index) * 0.075, rise: rise))
    }

    func buildIn(delay: Double, rise: CGFloat = 0) -> some View {
        modifier(BuildIn(delay: delay, rise: rise))
    }

    /// Einheitliche, mittige Seitenbreite mit großzügigem Rand (auch auf Pro-Max-Geräten).
    func pageWidth() -> some View {
        self
            .padding(.horizontal, 24)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
    }
}
