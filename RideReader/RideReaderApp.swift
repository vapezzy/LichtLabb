import SwiftUI

@main
@MainActor
struct RideReaderApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: ELMSession
    @StateObject private var scanner: FaultScanner
    @StateObject private var dpf: DPFMonitor
    @StateObject private var live: LiveMonitor
    @StateObject private var history = FaultHistory()
    @StateObject private var perf: PerformanceMonitor

    init() {
        let ble = BLEManager(startBluetooth: LaunchOptions.shot == nil)
        let session = ELMSession(ble: ble)
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: session)
        let scanner = FaultScanner(session: session)
        let dpf = DPFMonitor(session: session)
        let perf = PerformanceMonitor(session: session)
        _perf = StateObject(wrappedValue: perf)
        // DPF-Überwachung pausiert während Kontrolle und 0–100-Messung
        dpf.pauseWhen = { [weak scanner, weak perf] in (scanner?.isBusy ?? false) || (perf?.isActive ?? false) }
        dpf.onRegenChange = { RegenAlerts.regenChanged($0) }
        dpf.onAlarmToggle = { on in if on { RegenAlerts.requestPermission() } }
        RegenAlerts.setUp()
        _scanner = StateObject(wrappedValue: scanner)
        _dpf = StateObject(wrappedValue: dpf)
        _live = StateObject(wrappedValue: LiveMonitor(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(session)
                .environmentObject(scanner)
                .environmentObject(dpf)
                .environmentObject(live)
                .environmentObject(history)
                .environmentObject(perf)
                .preferredColorScheme(.dark)
        }
    }
}

/// Startparameter für automatische Screenshots im CI (z. B. `-shot results`). Im normalen Betrieb leer.
enum LaunchOptions {
    static var shot: String? { UserDefaults.standard.string(forKey: "shot") }

    static var introTime: Double? {
        UserDefaults.standard.object(forKey: "introTime") == nil ? nil : UserDefaults.standard.double(forKey: "introTime")
    }
}

enum AppTab: String, CaseIterable {
    case home, dpf, live, settings

    var title: String {
        switch self {
        case .home: return "Zuhause"
        case .dpf: return "DPF"
        case .live: return "Live"
        case .settings: return "Einstellungen"
        }
    }

    /// SF-Symbol; der DPF-Tab nutzt stattdessen die gezeichnete Kontrollleuchte
    var icon: String? {
        switch self {
        case .home: return "house.fill"
        case .dpf: return nil
        case .live: return "waveform.path.ecg"
        case .settings: return "gearshape.fill"
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var scanner: FaultScanner
    @EnvironmentObject private var session: ELMSession
    @EnvironmentObject private var dpf: DPFMonitor

    @State private var showIntro: Bool
    /// Startseite sichtbar – wird schon während des Intros gesetzt, damit sie sich unter dem Schriftzug aufbaut
    @State private var revealed: Bool
    @State private var tab: AppTab

    init() {
        let shot = LaunchOptions.shot
        let intro = shot == nil || shot == "intro"
        _showIntro = State(initialValue: intro)
        _revealed = State(initialValue: !intro)
        _tab = State(initialValue: shot == "settings" ? .settings : shot == "dpf" ? .dpf : .home)
    }

    var body: some View {
        ZStack {
            ZStack {
                switch tab {
                case .home:
                    HomeView(tab: $tab)
                        .transition(.blurFade)
                case .dpf:
                    DPFView(showsClose: false)
                        .transition(.blurFade)
                case .live:
                    LiveView()
                        .transition(.blurFade)
                case .settings:
                    SettingsTab(tab: $tab, replayIntro: replayIntro)
                        .transition(.blurFade)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabBar(tab: $tab)
                    .padding(.bottom, 4)
                    .buildIn(7, rise: 40)
            }
            .environment(\.pageRevealed, revealed)
            // Während Kontrolle/Löschen ist alles darunter verdeckt – nicht weiter animieren und zeichnen
            .opacity(scanner.isBusy ? 0 : 1)

            // Regeneration läuft – Banner über allen Tabs, solange der Alarm an ist
            if dpf.alarmEnabled && !dpf.isDemo && dpf.reading.regenerating && !scanner.isBusy {
                RegenBanner()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .dpf }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .pageWidth()
                    .padding(.top, 6)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(4)
            }

            if scanner.isBusy {
                ScanOverlay()
                    .transition(.blurFade)
                    .zIndex(5)
            }

            if showIntro {
                IntroView(onReveal: {
                    revealed = true
                }, onFinish: {
                    revealed = true
                    withAnimation(.easeOut(duration: 0.5)) { showIntro = false }
                }, frozenTime: LaunchOptions.introTime)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: scanner.isBusy)
        .onAppear(perform: applyShot)
        .onChange(of: session.isInitialized) { connected in dpf.connectionChanged(connected) }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: dpf.reading.regenerating)
    }

    private func replayIntro() {
        revealed = false
        withAnimation(.easeInOut(duration: 0.4)) { showIntro = true }
    }

    private func applyShot() {
        switch LaunchOptions.shot {
        case "results", "clear":
            scanner.loadDemo()
        case "loading":
            scanner.runDemoScan(seconds: 600)
        default:
            break
        }
    }
}

/// Schwebende Tab-Leiste; die Markierung gleitet zwischen den Tabs, der Name steht nur beim aktiven Tab.
struct TabBar: View {
    @Binding var tab: AppTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { item in
                let selected = tab == item
                Button {
                    guard !selected else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) { tab = item }
                } label: {
                    HStack(spacing: 8) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 22, height: 22)
                        } else {
                            DPFLampIcon(size: 22)
                        }
                        if selected {
                            Text(item.title)
                                .font(Theme.rounded(14, weight: .bold))
                                .lineLimit(1)
                                .fixedSize()
                                .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                        }
                    }
                    .foregroundStyle(selected ? Color.white : .white.opacity(0.6))
                    .padding(.horizontal, selected ? 18 : 16)
                    .padding(.vertical, 12)
                    .background {
                        if selected {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.accentDeep, Theme.violet, Theme.magenta.opacity(0.9)],
                                                     startPoint: .leading, endPoint: .trailing))
                                .overlay(Capsule().strokeBorder(.white.opacity(0.25), lineWidth: 1))
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel(item.title)
            }
        }
        .padding(6)
        .frosted(cornerRadius: 32)
    }
}

/// Vollbild während Kontrolle oder Löschen: die Mechaniker-Crew bei der Arbeit.
struct ScanOverlay: View {
    @EnvironmentObject private var scanner: FaultScanner

    var body: some View {
        let scanning = scanner.phase == .scanning
        ZStack {
            // Deckender Hintergrund statt Live-Blur: spart in jedem Bild einen Weichzeichner über den ganzen Bildschirm
            // Glow nur als Overlay – darf das Layout nie breiter als den Bildschirm machen
            Theme.background
                .overlay {
                    Glow(color: scanning ? Theme.violet : Theme.ok, opacity: 0.22)
                        .frame(width: 700, height: 700)
                        .offset(y: -120)
                }
                .clipped()
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                VStack(spacing: 6) {
                    Text(scanning ? "Kontrolle läuft" : "Die Crew räumt auf")
                        .font(Theme.display(26))
                        .foregroundStyle(scanning ? Theme.titleGradient
                                         : LinearGradient(colors: [.white, Theme.ok], startPoint: .leading, endPoint: .trailing))
                    Text(subtitle(scanning))
                        .font(Theme.rounded(15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(minHeight: 40)
                        .animation(.easeInOut(duration: 0.25), value: scanner.currentStep)
                }
                .padding(.horizontal, 24)

                MechanicsLoader(progress: scanning ? scanner.progress : nil, calm: !scanning)
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 16)

                if scanning {
                    Text("\(Int(scanner.progress * 100)) %")
                        .font(Theme.display(34))
                        .monospacedDigit()
                        .foregroundStyle(Theme.brandGradient)
                        .contentTransition(.numericText())
                        .animation(.easeOut(duration: 0.2), value: Int(scanner.progress * 100))
                }

                Spacer()

                if scanning {
                    Button {
                        Haptics.tap()
                        scanner.cancel()
                    } label: {
                        Text("Abbrechen")
                            .font(Theme.rounded(15, weight: .bold))
                            .padding(.horizontal, 26)
                            .padding(.vertical, 12)
                            .frosted(cornerRadius: 22)
                    }
                    .buttonStyle(PressableStyle())
                    .padding(.bottom, 30)
                }
            }
        }
        .foregroundStyle(.white)
    }

    private func subtitle(_ scanning: Bool) -> String {
        if scanning {
            return scanner.currentStep.isEmpty ? "Die Crew krempelt die Ärmel hoch …" : "Die Crew klopft bei „\(scanner.currentStep)“ an"
        }
        if let address = scanner.clearingAddress {
            return address == FaultScanner.obdAddress ? "OBD-II wird geputzt …" : "\(FaultScanner.name(for: address)) wird geputzt …"
        }
        return "Einen Moment …"
    }
}

/// Hinweis oben auf allen Seiten: Der Rußfilter regeneriert gerade.
struct RegenBanner: View {
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "flame.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LinearGradient(colors: [.yellow, Theme.fault, Theme.severe], startPoint: .top, endPoint: .bottom))
                .scaleEffect(pulse ? 1.15 : 0.92)
                .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: pulse)
            VStack(alignment: .leading, spacing: 1) {
                Text("Regeneration läuft")
                    .font(Theme.rounded(15, weight: .bold))
                Text("Motor jetzt nicht abstellen.")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Spacer(minLength: 0)
            DPFLampIcon(size: 22)
                .foregroundStyle(Theme.fault)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.35, green: 0.12, blue: 0.05), Color(red: 0.22, green: 0.06, blue: 0.12)],
                                     startPoint: .leading, endPoint: .trailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Theme.fault, Theme.magenta.opacity(0.6)], startPoint: .leading, endPoint: .trailing),
                              lineWidth: 1.2)
        )
        .foregroundStyle(.white)
        .onAppear { pulse = true }
    }
}
