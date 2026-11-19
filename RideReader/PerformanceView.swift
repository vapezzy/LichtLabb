import SwiftUI

/// 0–100-Messung: großer Tacho-Ring, laufende Zeit, Zwischenzeiten, Bestzeit.
struct PerformanceView: View {
    @EnvironmentObject private var perf: PerformanceMonitor
    @EnvironmentObject private var live: LiveMonitor
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(tint: tint)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Text("0–100")
                            .font(Theme.display(44))
                            .foregroundStyle(Theme.titleGradient)
                        Text("Wie schnell ist die Karre wirklich?")
                            .font(Theme.rounded(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.top, 40)

                    SpeedRing(speed: perf.speed, tint: tint)

                    timer

                    statusCard
                    splitsCard
                    if !perf.runs.isEmpty { historyCard }

                    Text("Nur auf abgesperrter Strecke messen. Zeit über das Tempo-Signal des Motorsteuergeräts, Zwischenwerte interpoliert.")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .multilineTextAlignment(.center)
                }
                .pageWidth()
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)

            HStack {
                Spacer()
                Button {
                    Haptics.tap()
                    perf.cancel()
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
        .foregroundStyle(.white)
        .preferredColorScheme(.dark)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: perf.phase)
        // Live-Abfrage pausieren → maximale Messrate fürs Tempo
        .onAppear { live.stop() }
        .onDisappear {
            perf.cancel()
            live.start()
        }
    }

    private var tint: Color {
        switch perf.phase {
        case .ready: return Theme.ok
        case .running: return Theme.magenta
        case .finished: return Theme.violet
        case .failed: return Theme.fault
        default: return Theme.accent
        }
    }

    // MARK: - Zeit

    private var timer: some View {
        Group {
            switch perf.phase {
            case .running(let start):
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    timeText(context.date.timeIntervalSince(start))
                }
            case .finished(let run):
                timeText(run.total ?? 0)
            default:
                timeText(0).opacity(0.35)
            }
        }
    }

    private func timeText(_ seconds: Double) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(String(format: "%.2f", max(0, seconds)))
                .font(Theme.display(60))
                .monospacedDigit()
                .foregroundStyle(LinearGradient(colors: [.white, tint], startPoint: .top, endPoint: .bottom))
            Text("s")
                .font(Theme.display(24))
                .foregroundStyle(.white.opacity(0.5))
        }
    }

    // MARK: - Status & Knopf

    private var statusCard: some View {
        let (icon, title, text): (String, String, String) = {
            switch perf.phase {
            case .idle:
                return ("flag.checkered", "Bereit zum Messen?", "Scharf schalten, anhalten, Vollgas. Die Zeit startet von selbst, sobald das Auto rollt.")
            case .waitingForStop:
                return ("pause.circle.fill", "Erst anhalten", "Die Messung startet aus dem Stand (0 km/h).")
            case .ready:
                return ("bolt.fill", "Scharf! Vollgas, wenn du willst.", perf.sampleRate > 0 ? "\(Int(perf.sampleRate)) Messungen pro Sekunde" : "Beispiel-Lauf startet gleich …")
            case .running:
                return ("speedometer", "Läuft …", "Bis 100 km/h durchziehen.")
            case .finished(let run):
                let isBest = !run.isDemo && perf.best?.id == run.id
                return (isBest ? "trophy.fill" : "checkmark.seal.fill", isBest ? "Neue Bestzeit!" : "Geschafft!",
                        run.isDemo ? "Beispiel-Lauf – mit verbundenem Stecker wird echt gemessen." : "Lauf gespeichert.")
            case .failed(let message):
                return ("exclamationmark.triangle.fill", "Messung abgebrochen", message)
            }
        }()
        let showArm: Bool = {
            switch perf.phase {
            case .idle, .finished, .failed: return true
            default: return false
            }
        }()
        return VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(tint)
                    .background(Glow(color: tint, opacity: 0.45).frame(width: 60, height: 60))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.rounded(17, weight: .bold))
                    Text(text)
                        .font(Theme.rounded(13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            Button {
                Haptics.tap()
                if showArm { perf.arm() } else { perf.cancel() }
            } label: {
                Label(showArm ? (perf.phase == .idle ? "Scharf schalten" : "Nochmal") : "Abbrechen",
                      systemImage: showArm ? "flag.checkered" : "xmark")
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(showArm ? Theme.onButton : .white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(
                        Capsule().fill(showArm
                                       ? AnyShapeStyle(Theme.buttonGradient)
                                       : AnyShapeStyle(Color.white.opacity(0.1)))
                    )
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: tint)
    }

    // MARK: - Zwischenzeiten

    private var splitsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ZWISCHENZEITEN")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
            ForEach(PerformanceMonitor.targets, id: \.self) { target in
                HStack {
                    Text("0–\(target) km/h")
                        .font(Theme.rounded(15, weight: .semibold))
                    Spacer()
                    if let best = perf.best?.splits[target] {
                        Text(String(format: "Best %.2f", best))
                            .font(Theme.rounded(11, weight: .bold))
                            .foregroundStyle(Theme.violet)
                    }
                    Text(perf.splits[target].map { String(format: "%.2f s", $0) } ?? "–")
                        .font(.system(size: 16, weight: .bold, design: .monospaced))
                        .foregroundStyle(perf.splits[target] == nil ? .white.opacity(0.35) : .white)
                        .frame(minWidth: 76, alignment: .trailing)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    private var historyCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("LETZTE LÄUFE")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
            ForEach(perf.runs.prefix(5)) { run in
                HStack {
                    Text(run.date.formatted(date: .abbreviated, time: .shortened))
                        .font(Theme.rounded(14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                    Spacer()
                    if perf.best?.id == run.id {
                        Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                    }
                    Text(run.total.map { String(format: "%.2f s", $0) } ?? "–")
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Tacho-Ring 0–120 km/h mit 100er-Markierung.
struct SpeedRing: View {
    var speed: Double
    var tint: Color

    private let diameter: CGFloat = 230

    var body: some View {
        let fraction = min(max(speed / 120, 0), 1)
        ZStack {
            Circle()
                .trim(from: 0, to: 0.75)
                .stroke(.white.opacity(0.08), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: 0.75 * fraction)
                .stroke(AngularGradient(colors: [Theme.accent, Theme.violet, Theme.magenta, Theme.severe],
                                        center: .center, startAngle: .degrees(0), endAngle: .degrees(270)),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(.linear(duration: 0.12), value: speed)
            // Markierung bei 100 km/h
            Capsule()
                .fill(.white)
                .frame(width: 3, height: 22)
                .offset(y: -diameter / 2)
                .rotationEffect(.degrees(-135 + 270 * 100 / 120))
            VStack(spacing: 0) {
                Text("\(Int(speed))")
                    .font(Theme.display(54))
                    .monospacedDigit()
                Text("km/h")
                    .font(Theme.rounded(14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .frame(width: diameter, height: diameter)
        .background { Glow(color: tint, opacity: 0.3).frame(width: diameter * 1.3, height: diameter * 1.3) }
    }
}
