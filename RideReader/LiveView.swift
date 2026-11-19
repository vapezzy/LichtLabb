import SwiftUI

/// Tab „Live“: Batterie, Batterietest und Echtzeitdaten.
struct LiveView: View {
    @EnvironmentObject private var monitor: LiveMonitor
    @EnvironmentObject private var session: ELMSession

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(tint: Theme.accent)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    switch monitor.state {
                    case .failed(let message):
                        InfoCard(icon: "exclamationmark.triangle.fill", color: Theme.fault, title: "Keine Live-Daten", text: message)
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
                    case .idle, .discovering:
                        ProgressView().tint(Theme.accent).scaleEffect(1.3).padding(40)
                    case .live:
                        batteryCard.buildIn(1)
                        batteryTestCard.buildIn(2)
                        if let readiness = monitor.readiness {
                            readinessCard(readiness).buildIn(3)
                        }
                        liveGrid.buildIn(4)
                        Text("Nur lesen – RideReader verändert nichts am Auto.")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                .pageWidth()
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
        .onChange(of: session.isInitialized) { _ in monitor.start() }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "waveform.path.ecg")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(Theme.brandGradient)
                .background(Glow(color: Theme.accent, opacity: 0.4).frame(width: 110, height: 110))
            Text("Live")
                .font(Theme.display(36))
                .foregroundStyle(Theme.titleGradient)
            Text("Was dein Auto gerade so treibt.")
                .font(Theme.rounded(15, weight: .medium))
                .foregroundStyle(.white.opacity(0.65))
            HStack(spacing: 7) {
                let color = monitor.isDemo ? Theme.violet : Theme.ok
                Circle().fill(color).frame(width: 7, height: 7)
                Text(monitor.isDemo ? "Beispieldaten · kein Stecker verbunden" : "Live vom Auto")
                    .font(Theme.rounded(12, weight: .bold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frosted(cornerRadius: 16)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .buildIn(0)
    }

    // MARK: - Batterie

    private var running: Bool { (monitor.voltage ?? 0) >= 13.2 || (monitor.values[0x0C] ?? 0) > 300 }

    private var batteryCard: some View {
        let v = monitor.voltage
        let soc = v.map(LiveMonitor.stateOfCharge) ?? 0
        let color: Color = {
            guard let v else { return .gray }
            if running { return LiveMonitor.gradeCharging(v) == .good ? Theme.ok : Theme.fault }
            switch LiveMonitor.gradeRest(v) {
            case .good: return Theme.ok
            case .okay: return Theme.accent
            case .weak: return Theme.fault
            case .bad: return Theme.severe
            }
        }()
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "minus.plus.batteryblock.fill")
                    .foregroundStyle(color)
                Text("BATTERIE")
                    .font(.system(size: 12, weight: .heavy))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(v.map { String(format: "%.2f", $0) } ?? "–")
                    .font(Theme.display(52))
                    .monospacedDigit()
                    .foregroundStyle(LinearGradient(colors: [.white, color], startPoint: .top, endPoint: .bottom))
                Text("V")
                    .font(Theme.display(22))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            }
            Text(running ? "Motor läuft – die Lichtmaschine lädt."
                 : "Motor aus · Ladezustand ca. \(Int(soc.rounded())) %")
                .font(Theme.rounded(14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
            if !running {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(.white.opacity(0.08))
                        Capsule()
                            .fill(LinearGradient(colors: [Theme.severe, Theme.fault, Theme.ok], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(10, geo.size.width * soc / 100))
                    }
                }
                .frame(height: 10)
                .animation(.easeOut(duration: 0.5), value: Int(soc))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    // MARK: - Batterietest

    @ViewBuilder
    private var batteryTestCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("BATTERIETEST")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))

            switch monitor.testStep {
            case .none:
                Text("Misst Ruhespannung, Spannungseinbruch beim Anlassen und Ladespannung. Dauert etwa eine halbe Minute.")
                    .font(Theme.rounded(13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if monitor.isDemo {
                    Text("Verbinde den OBD-Stecker, um den Test zu starten.")
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(Theme.fault)
                }
                testButton("Test starten", icon: "bolt.badge.checkmark.fill") { monitor.startBatteryTest() }
                    .disabled(monitor.isDemo || running)
                    .opacity(monitor.isDemo || running ? 0.4 : 1)
                if running && !monitor.isDemo {
                    Text("Erst den Motor ausschalten (Zündung an lassen).")
                        .font(Theme.rounded(12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
            case .rest(let progress):
                stepView(1, "Ruhespannung messen …", "Motor aus lassen, nichts einschalten.", progress: progress)
            case .waitForStart(let seconds):
                stepView(2, "Jetzt den Motor starten!", "Ich messe den Spannungseinbruch beim Anlassen · noch \(seconds) s", progress: nil)
            case .charging(let progress):
                stepView(3, "Ladespannung messen …", "Motor im Leerlauf laufen lassen.", progress: progress)
            case .done:
                resultView
                testButton("Nochmal testen", icon: "arrow.clockwise") { monitor.resetBatteryTest() }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.violet)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: monitor.testStep)
    }

    private func testButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.rounded(15, weight: .bold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Capsule().fill(LinearGradient(colors: [Theme.accentDeep, Theme.violet, Theme.magenta.opacity(0.9)],
                                                          startPoint: .leading, endPoint: .trailing)))
        }
        .buttonStyle(PressableStyle())
    }

    private func stepView(_ number: Int, _ title: String, _ text: String, progress: Double?) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("\(number)/3")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Theme.violet.opacity(0.3)))
                Text(title).font(Theme.rounded(17, weight: .bold))
            }
            Text(text)
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.7))
            if let progress {
                ProgressView(value: min(max(progress, 0), 1)).tint(Theme.accent)
            } else {
                Button {
                    monitor.cancelBatteryTest()
                } label: {
                    Text("Abbrechen")
                        .font(Theme.rounded(14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
        }
    }

    private var resultView: some View {
        let r = monitor.result
        return VStack(spacing: 10) {
            resultRow("Ruhespannung", r.rest, r.rest.map(LiveMonitor.gradeRest),
                      note: r.rest.map { "≈ \(Int(LiveMonitor.stateOfCharge($0).rounded())) % geladen" })
            resultRow("Beim Anlassen (Minimum)", r.crankMin, r.crankMin.map(LiveMonitor.gradeCrank),
                      note: r.crankMin == nil ? "kein Start erkannt" : nil)
            resultRow("Ladespannung", r.charging, r.charging.map(LiveMonitor.gradeCharging),
                      note: r.charging == nil ? "Motor lief nicht" : nil)
        }
    }

    private func resultRow(_ title: String, _ value: Double?, _ grade: LiveMonitor.Grade?, note: String?) -> some View {
        let (label, color): (String, Color) = {
            switch grade {
            case .good: return ("gut", Theme.ok)
            case .okay: return ("ok", Theme.accent)
            case .weak: return ("schwach", Theme.fault)
            case .bad: return ("prüfen", Theme.severe)
            case nil: return ("–", .gray)
            }
        }()
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Theme.rounded(14, weight: .semibold))
                if let note {
                    Text(note).font(Theme.rounded(12, weight: .medium)).foregroundStyle(.white.opacity(0.5))
                }
            }
            Spacer()
            Text(value.map { String(format: "%.2f V", $0) } ?? "–")
                .font(.system(size: 15, weight: .bold, design: .monospaced))
            Text(label)
                .font(Theme.rounded(12, weight: .heavy))
                .foregroundStyle(color)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule().fill(color.opacity(0.16)))
        }
    }

    // MARK: - AU-Bereitschaft

    private func readinessCard(_ r: LiveMonitor.Readiness) -> some View {
        let color: Color = r.mil ? Theme.severe : r.ready ? Theme.ok : Theme.fault
        let title = r.mil ? "Motorkontrollleuchte an" : r.ready ? "Bereit für die AU" : "Noch nicht AU-bereit"
        let text = r.mil
            ? "Mit leuchtender Motorkontrollleuchte gibt's keine Plakette. Erst den Fehler beheben."
            : r.ready
                ? "Alle Abgas-Selbsttests sind durch – ab zur Untersuchung."
                : "\(r.openCount) von \(r.monitors.count) Selbsttests noch offen. Nach dem Fehlerlöschen oder Batterieabklemmen ein paar normale Fahrten machen (Stadt, Landstraße, Autobahn)."
        return VStack(alignment: .leading, spacing: 14) {
            Text("AU-BEREITSCHAFT")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 12) {
                Image(systemName: r.mil ? "exclamationmark.octagon.fill" : r.ready ? "checkmark.seal.fill" : "hourglass")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(color)
                    .background(Glow(color: color, opacity: 0.45).frame(width: 64, height: 64))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(Theme.rounded(17, weight: .bold))
                    Text(text)
                        .font(Theme.rounded(13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                ForEach(r.monitors, id: \.name) { m in
                    HStack {
                        Image(systemName: m.complete ? "checkmark.circle.fill" : "clock.fill")
                            .foregroundStyle(m.complete ? Theme.ok : Theme.fault)
                        Text(m.name).font(Theme.rounded(14, weight: .semibold))
                        Spacer()
                        Text(m.complete ? "fertig" : "offen")
                            .font(Theme.rounded(12, weight: .bold))
                            .foregroundStyle(m.complete ? Theme.ok : Theme.fault)
                    }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    // MARK: - Echtzeitdaten

    private var liveGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ECHTZEITDATEN")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
                .padding(.leading, 6)
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                ForEach(monitor.visibleSignals) { signal in
                    ValueTile(icon: signal.icon, title: signal.title, value: monitor.values[signal.pid],
                              unit: signal.unit, digits: signal.digits, supported: true)
                }
            }
            if !monitor.supported.contains(0xA6) {
                Text("Kilometerstand: Dein Motorsteuergerät liefert ihn nicht über die genormte Schnittstelle.")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .padding(.horizontal, 6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
