import SwiftUI

/// Rußfilter-Seite: Live-Werte des Dieselpartikelfilters, nur lesend.
struct DPFView: View {
    /// Schließen-Knopf nur, wenn als eigenes Fenster geöffnet (nicht als Tab)
    var showsClose = true

    @EnvironmentObject private var monitor: DPFMonitor
    @Environment(\.dismiss) private var dismiss

    private var r: DPFMonitor.Reading { monitor.reading }

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(tint: r.regenerating ? Theme.fault : Theme.violet)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    content
                }
                .pageWidth()
                .padding(.top, 18)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            if showsClose {
            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .heavy))
                        .frame(width: 36, height: 36)
                        .frosted(cornerRadius: 18)
                }
                .buttonStyle(PressableStyle())
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            }
        }
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: r.regenerating)
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: monitor.state)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(spacing: 8) {
            DPFLampIcon(size: 40)
                .foregroundStyle(Theme.brandGradient)
                .background(Glow(color: Theme.violet, opacity: 0.45).frame(width: 110, height: 110))
                .padding(.top, showsClose ? 26 : 8)
                .buildIn(0)
            Text("Rußfilter")
                .font(Theme.display(36))
                .foregroundStyle(Theme.titleGradient)
            Text("Die Crew guckt dem Diesel in den Auspuff.")
                .font(Theme.rounded(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
            sourceChip
        }
        .frame(maxWidth: .infinity)
    }

    private var sourceChip: some View {
        let (text, color): (String, Color) = {
            if monitor.isDemo { return ("Beispieldaten · kein Stecker verbunden", Theme.violet) }
            switch monitor.state {
            case .discovering: return ("Frage Motorsteuergerät …", .yellow)
            case .live: return ("Live vom Motorsteuergerät", Theme.ok)
            case .failed: return ("Keine Werte", Theme.fault)
            case .idle: return ("Bereit", .gray)
            }
        }()
        return HStack(spacing: 7) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(Theme.rounded(12, weight: .bold))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frosted(cornerRadius: 16)
        .padding(.top, 4)
    }

    // MARK: - Inhalt

    @ViewBuilder
    private var content: some View {
        switch monitor.state {
        case .failed(let message):
            InfoCard(icon: "exclamationmark.triangle.fill", color: Theme.fault, title: "Keine Rußfilter-Werte", text: message)
            Button {
                Haptics.tap()
                monitor.start()
            } label: {
                Label("Nochmal versuchen", systemImage: "arrow.clockwise")
                    .font(Theme.rounded(15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.brandGradient))
            }
            .buttonStyle(PressableStyle())
            tipsCard
        case .discovering, .idle:
            ProgressView()
                .tint(Theme.accent)
                .scaleEffect(1.3)
                .padding(40)
        case .live:
            SootGauge(percent: r.regenTrigger, deltaPressure: r.deltaPressure, regenerating: r.regenerating)
                .padding(.vertical, 6)
            statusBanner
            valuesGrid
            tipsCard
            Text("RideReader liest hier nur – am Motor wird nichts verändert oder gestartet.")
                .font(Theme.rounded(12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
    }

    private var statusBanner: some View {
        let active = r.regenerating
        let color = active ? Theme.fault : Theme.ok
        return HStack(spacing: 14) {
            Image(systemName: active ? "flame.fill" : "checkmark.seal.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(color)
                .background(Glow(color: color, opacity: 0.45).frame(width: 64, height: 64))
                .symbolEffectPulse(active)
            VStack(alignment: .leading, spacing: 3) {
                Text(active ? "Regeneration läuft" : "Keine Regeneration aktiv")
                    .font(Theme.rounded(17, weight: .bold))
                Text(active
                     ? "Der Filter brennt gerade Ruß ab. Weiterfahren und den Motor jetzt nicht abstellen."
                     : regenHint)
                    .font(Theme.rounded(13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    private var regenHint: String {
        if r.regenActive == nil {
            return "Das Steuergerät meldet den Status nicht direkt – RideReader erkennt eine Regeneration an der Temperatur vor dem Filter."
        }
        if let p = r.regenTrigger, p >= 85 { return "Der Filter ist ziemlich voll. Eine längere Fahrt hilft ihm beim Freibrennen." }
        return "Alles entspannt. Der Filter regeneriert sich beim Fahren von selbst."
    }

    private var valuesGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ValueTile(icon: "gauge.with.dots.needle.33percent", title: "Differenzdruck", value: r.deltaPressure, unit: "mbar",
                      digits: 0, supported: monitor.supported.contains(0x7A))
            ValueTile(icon: "thermometer.high", title: "Vor dem Filter", value: r.inletTemp, unit: "°C",
                      digits: 0, supported: monitor.supported.contains(0x7C), hot: (r.inletTemp ?? 0) > 480)
            ValueTile(icon: "thermometer.medium", title: "Nach dem Filter", value: r.outletTemp, unit: "°C",
                      digits: 0, supported: monitor.supported.contains(0x7C), hot: (r.outletTemp ?? 0) > 480)
            ValueTile(icon: "flame", title: "Abgastemperatur", value: r.exhaustTemp, unit: "°C",
                      digits: 0, supported: monitor.supported.contains(0x78), hot: (r.exhaustTemp ?? 0) > 500)
            ValueTile(icon: "road.lanes", title: "Ø km je Regeneration", value: r.averageDistance, unit: "km",
                      digits: 0, supported: r.averageDistance != nil)
            ValueTile(icon: "drop.fill", title: "Kühlmittel", value: r.coolant, unit: "°C",
                      digits: 0, supported: monitor.supported.contains(0x05))
            ValueTile(icon: "oilcan.fill", title: "Motoröl", value: r.oil, unit: "°C",
                      digits: 0, supported: monitor.supported.contains(0x5C))
            ValueTile(icon: "speedometer", title: "Drehzahl", value: r.rpm, unit: "U/min",
                      digits: 0, supported: monitor.supported.contains(0x0C))
        }
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("SO BRENNT ER SICH FREI")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
            tip("road.lanes", "20–30 Minuten Landstraße oder Autobahn, gleichmäßig über ca. 2.000 U/min.")
            tip("thermometer.medium", "Motor erst warm fahren – unter ca. 70 °C Kühlmittel startet keine Regeneration.")
            tip("fuelpump.fill", "Mindestens ein Viertel Tank: das Steuergerät regeneriert sonst nicht.")
            tip("hand.raised.fill", "Läuft eine Regeneration, den Motor möglichst nicht abstellen – sonst beginnt alles von vorn.")
            tip("exclamationmark.triangle.fill", "Leuchtet die Motor- oder DPF-Lampe dauerhaft, ab in die Werkstatt.", color: Theme.severe)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private func tip(_ icon: String, _ text: String, color: Color = Theme.accent) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 22)
            Text(text)
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Großer Ring: Beladung bis zur nächsten Regeneration (oder – falls nicht geliefert – der Differenzdruck).
struct SootGauge: View {
    var percent: Double?
    var deltaPressure: Double?
    var regenerating: Bool

    @State private var spin = false

    private let diameter: CGFloat = 230

    private var fraction: Double {
        if let percent { return min(max(percent / 100, 0), 1) }
        if let deltaPressure { return min(max(deltaPressure / 150, 0), 1) }
        return 0
    }

    private var color: Color {
        if regenerating { return Theme.fault }
        return fraction >= 0.85 ? Theme.severe : fraction >= 0.6 ? Theme.fault : Theme.ok
    }

    var body: some View {
        ZStack {
            Glow(color: color, opacity: 0.35)
                .frame(width: diameter * 1.3, height: diameter * 1.3)

            // Skala
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Wert
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(AngularGradient(colors: [Theme.ok, Theme.accent, Theme.fault, Theme.severe],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .rotationEffect(.degrees(135))

            // Hitze-Ring während der Regeneration
            if regenerating {
                Circle()
                    .strokeBorder(AngularGradient(colors: [Theme.fault, Theme.severe, Theme.magenta, Theme.fault], center: .center),
                                  style: StrokeStyle(lineWidth: 2, dash: [4, 8]))
                    .padding(-14)
                    .rotationEffect(.degrees(spin ? 360 : 0))
                    .transition(.opacity)
            }

            VStack(spacing: 2) {
                Text(valueText)
                    .font(Theme.display(46))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                    .contentTransition(.numericText())
                Text(caption)
                    .font(Theme.rounded(13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(.easeOut(duration: 0.5), value: fraction)
        .onAppear {
            withAnimation(.linear(duration: 6).repeatForever(autoreverses: false)) { spin = true }
        }
    }

    private var valueText: String {
        if let percent { return "\(Int(percent.rounded())) %" }
        if let deltaPressure { return "\(Int(deltaPressure.rounded()))" }
        return "–"
    }

    private var caption: String {
        if percent != nil { return "Beladung bis zur\nnächsten Regeneration" }
        if deltaPressure != nil { return "mbar Differenzdruck\n(steigt mit Ruß und Gas)" }
        return "keine Angabe"
    }
}

/// Kachel mit einem Messwert.
struct ValueTile: View {
    var icon: String
    var title: String
    var value: Double?
    var unit: String
    var digits: Int = 0
    var supported: Bool
    var hot: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(hot ? AnyShapeStyle(Theme.fault) : AnyShapeStyle(Theme.brandGradient))
                Text(title)
                    .font(Theme.rounded(12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            if supported, let value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.\(digits)f", value))
                        .font(Theme.display(24))
                        .monospacedDigit()
                        .foregroundStyle(hot ? Theme.fault : .white)
                        .contentTransition(.numericText())
                    Text(unit)
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .animation(.easeOut(duration: 0.3), value: value)
            } else {
                Text(supported ? "…" : "nicht geliefert")
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.35))
                    .frame(height: 29, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 20, tint: hot ? Theme.fault : nil)
    }
}

private extension View {
    /// Sanftes Pulsieren, solange `active` (ohne iOS-17-Symboleffekte).
    func symbolEffectPulse(_ active: Bool) -> some View {
        modifier(PulseModifier(active: active))
    }
}

private struct PulseModifier: ViewModifier {
    let active: Bool
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(active && on ? 1.12 : 1)
            .opacity(active && on ? 0.75 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { on = true }
            }
    }
}
