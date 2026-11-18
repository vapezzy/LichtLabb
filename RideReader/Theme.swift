import SwiftUI

/// Farben, Schriften und wiederverwendbare Effekte von RideReader.
enum Theme {
    static let background = Color(red: 0.027, green: 0.031, blue: 0.045)
    static let surface = Color(red: 0.075, green: 0.082, blue: 0.105)
    /// Markenfarbe: elektrisches Cyan
    static let accent = Color(red: 0.36, green: 0.92, blue: 1.0)
    static let accentDeep = Color(red: 0.27, green: 0.45, blue: 1.0)
    static let ok = Color(red: 0.32, green: 0.95, blue: 0.62)
    /// Orange = Fehler
    static let fault = Color(red: 1.0, green: 0.6, blue: 0.14)
    /// Rot = schwerwiegender Fehler
    static let severe = Color(red: 1.0, green: 0.25, blue: 0.3)

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
        content
            .blur(radius: active ? 16 : 0)
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
                            RadialGradient(colors: [(tint ?? .clear).opacity(0.18), .clear],
                                           center: .topLeading, startRadius: 0, endRadius: 260))
                    )
            )
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [(tint ?? .white).opacity(tint == nil ? 0.22 : 0.55), .white.opacity(0.03)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
            )
            .shadow(color: (tint ?? .black).opacity(tint == nil ? 0.35 : 0.22), radius: 18, y: 10)
    }

    /// Echtes Milchglas für schwebende Elemente (Tab-Leiste, Pop-ups).
    func frosted(cornerRadius: CGFloat = 30) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
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

/// Dunkler Hintergrund mit langsam wandernden Farbflecken; die Farbe zeigt den Zustand des Autos.
struct AmbientBackground: View {
    var tint: Color = Theme.accent

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                Theme.background
                Circle()
                    .fill(tint.opacity(0.28))
                    .frame(width: 460, height: 460)
                    .blur(radius: 130)
                    .offset(x: -120 + 40 * sin(t / 5), y: -300 + 30 * cos(t / 6))
                Circle()
                    .fill(Theme.accentDeep.opacity(0.22))
                    .frame(width: 400, height: 400)
                    .blur(radius: 140)
                    .offset(x: 150 + 30 * cos(t / 7), y: 280 + 40 * sin(t / 4.5))
                // feines Raster wie auf einer Hebebühne
                GridFloor()
                    .opacity(0.5)
            }
            .ignoresSafeArea()
        }
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
