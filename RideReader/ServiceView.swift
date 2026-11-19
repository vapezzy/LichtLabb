import SwiftUI

/// Tab „Service“: Rußfilter, AGR-Überwachung und eigene Service-Routinen.
struct ServiceView: View {
    enum Section: String, CaseIterable, Identifiable {
        case dpf, egr, routines
        var id: String { rawValue }
        var title: String {
            switch self {
            case .dpf: return "DPF"
            case .egr: return "AGR"
            case .routines: return "Routinen"
            }
        }
    }

    static let sectionKey = "serviceSection"

    /// Vor dem Tabwechsel aufrufen, um direkt einen Bereich zu öffnen
    static func open(_ section: Section) {
        UserDefaults.standard.set(section.rawValue, forKey: sectionKey)
    }

    @AppStorage(ServiceView.sectionKey) private var section: Section = .dpf
    @Namespace private var namespace

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(tint: Theme.violet)

            ScrollView {
                VStack(spacing: 22) {
                    VStack(spacing: 6) {
                        Image(systemName: "wrench.and.screwdriver.fill")
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.brandGradient)
                            .background(Glow(color: Theme.violet, opacity: 0.4).frame(width: 100, height: 100))
                        Text("Service")
                            .font(Theme.display(36))
                            .foregroundStyle(Theme.titleGradient)
                        Text("Rußfilter, AGR und Werkstatt-Routinen.")
                            .font(Theme.rounded(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(maxWidth: .infinity)
                    .buildIn(0)

                    picker.buildIn(1)

                    switch section {
                    case .dpf: DPFView(showsClose: false, embedded: true).transition(.blurFade)
                    case .egr: EGRSection().transition(.blurFade)
                    case .routines: RoutineSection().transition(.blurFade)
                    }
                }
                .pageWidth()
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: section)
    }

    private var picker: some View {
        HStack(spacing: 4) {
            ForEach(Section.allCases) { item in
                let selected = section == item
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    section = item
                } label: {
                    HStack(spacing: 6) {
                        switch item {
                        case .dpf: DPFLampIcon(size: 17)
                        case .egr: Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 14, weight: .bold))
                        case .routines: Image(systemName: "wrench.adjustable.fill").font(.system(size: 14, weight: .bold))
                        }
                        Text(item.title).font(Theme.rounded(14, weight: .bold))
                    }
                    .foregroundStyle(selected ? Theme.onButton : .white.opacity(0.65))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background {
                        if selected {
                            Capsule()
                                .fill(Theme.buttonGradient)
                                .matchedGeometryEffect(id: "segment", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(5)
        .frosted(cornerRadius: 26)
    }
}

// MARK: - AGR

/// AGR-Überwachung über genormte Messwerte: Sollwert, Abweichung, Temperatur, Luftmasse.
struct EGRSection: View {
    @EnvironmentObject private var live: LiveMonitor
    @EnvironmentObject private var session: ELMSession

    private var commanded: Double? { live.values[0x2C] }
    private var error: Double? { live.values[0x2D] }
    private var hasEGR: Bool { live.supported.contains(0x2C) || live.supported.contains(0x2D) }

    var body: some View {
        VStack(spacing: 22) {
            VStack(spacing: 4) {
                Text("AGR")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.titleGradient)
                Text(live.isDemo ? "Beispieldaten · kein Stecker verbunden" : "Live vom Motorsteuergerät")
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            switch live.state {
            case .failed(let message):
                InfoCard(icon: "exclamationmark.triangle.fill", color: Theme.fault, title: "Keine AGR-Werte", text: message)
            case .idle, .discovering:
                ProgressView().tint(Theme.accent).scaleEffect(1.3).padding(30)
            case .live:
                if hasEGR {
                    gauge
                    statusCard
                } else {
                    InfoCard(icon: "info.circle.fill", color: Theme.violet, title: "AGR-Werte nicht verfügbar",
                             text: "Dein Motorsteuergerät liefert Soll- und Istwert der AGR nicht über die genormte Schnittstelle. Luftmasse und Saugrohrdruck unten zeigen aber, ob Luft fehlt.")
                }
                tiles
                tipsCard
            }
        }
        .onAppear { live.start() }
        .onDisappear { live.stop() }
        .onChange(of: session.isInitialized) { _ in live.start() }
    }

    /// Zwei Balken: Sollwert und daraus berechneter Istwert
    private var gauge: some View {
        let soll = commanded ?? 0
        let ist = max(0, min(100, soll * (1 + (error ?? 0) / 100)))
        return VStack(alignment: .leading, spacing: 14) {
            bar("Sollwert", soll, colors: [Theme.accent, Theme.violet])
            bar("Istwert (berechnet)", ist, colors: [Theme.violet, Theme.magenta])
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.violet)
    }

    private func bar(_ title: String, _ value: Double, colors: [Color]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title).font(Theme.rounded(14, weight: .semibold))
                Spacer()
                Text(String(format: "%.0f %%", value))
                    .font(.system(size: 16, weight: .bold, design: .monospaced))
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.08))
                    Capsule()
                        .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(8, geo.size.width * value / 100))
                }
            }
            .frame(height: 12)
            .animation(.easeOut(duration: 0.3), value: Int(value))
        }
    }

    private var statusCard: some View {
        let e = abs(error ?? 0)
        let running = (live.values[0x0C] ?? 0) > 300
        let (icon, color, title, text): (String, Color, String, String) = {
            if !running {
                return ("pause.circle.fill", .gray, "Motor läuft nicht",
                        "Die AGR regelt nur bei laufendem Motor. Am besten warm im Leerlauf und bei leichter Teillast beobachten.")
            }
            if e < 10 { return ("checkmark.seal.fill", Theme.ok, "AGR regelt sauber", "Ist- und Sollwert liegen eng beieinander.") }
            if e < 25 { return ("exclamationmark.circle.fill", Theme.fault, "Leichte Abweichung",
                                "Kurzzeitig normal bei Lastwechseln. Bleibt sie dauerhaft, kann das Ventil schwergängig sein.") }
            return ("exclamationmark.octagon.fill", Theme.severe, "Starke Abweichung",
                    "Das AGR-Ventil folgt dem Sollwert nicht – typisch für Verkokung oder ein hängendes Ventil. Bleibt das so, prüfen lassen.")
        }()
        return HStack(spacing: 14) {
            Image(systemName: icon)
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
            Spacer(minLength: 0)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    private var tiles: some View {
        let pids: [UInt8] = [0x2C, 0x2D, 0x6B, 0x10, 0x0B, 0x0F, 0x0C, 0x05]
        let signals = LiveMonitor.signals.filter { pids.contains($0.pid) && live.supported.contains($0.pid) }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            ForEach(signals) { signal in
                ValueTile(icon: signal.icon, title: signal.title, value: live.values[signal.pid],
                          unit: signal.unit, digits: signal.digits, supported: true)
            }
        }
    }

    private var tipsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GUT ZU WISSEN")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
            Label("Abweichung = wie weit der Istwert vom Sollwert weg ist. ±10 % sind normal.", systemImage: "plusminus")
            Label("Nach dem Tausch des AGR-Ventils werden die Lernwerte zurückgesetzt – unter „Routinen“, sobald der Befehl aus einem Mitschnitt hinterlegt ist.", systemImage: "arrow.counterclockwise")
            Label("Viel Kurzstrecke verkokt AGR und Ansaugtrakt – regelmäßig längere Fahrten helfen.", systemImage: "road.lanes")
        }
        .font(Theme.rounded(13, weight: .medium))
        .foregroundStyle(.white.opacity(0.8))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}
