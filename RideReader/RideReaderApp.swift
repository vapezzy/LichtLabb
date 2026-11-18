import SwiftUI

@main
@MainActor
struct RideReaderApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: ELMSession
    @StateObject private var scanner: FaultScanner

    init() {
        let ble = BLEManager(startBluetooth: LaunchOptions.shot == nil)
        let session = ELMSession(ble: ble)
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: session)
        _scanner = StateObject(wrappedValue: FaultScanner(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(session)
                .environmentObject(scanner)
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
    case home, settings

    var title: String { self == .home ? "Zuhause" : "Einstellungen" }
    var icon: String { self == .home ? "house.fill" : "gearshape.fill" }
}

struct RootView: View {
    @EnvironmentObject private var scanner: FaultScanner

    @State private var showIntro: Bool
    @State private var tab: AppTab

    init() {
        let shot = LaunchOptions.shot
        _showIntro = State(initialValue: shot == nil || shot == "intro")
        _tab = State(initialValue: shot == "settings" ? .settings : .home)
    }

    var body: some View {
        ZStack {
            ZStack {
                switch tab {
                case .home:
                    HomeView(tab: $tab)
                        .transition(.blurFade)
                case .settings:
                    SettingsTab(tab: $tab, replayIntro: replayIntro)
                        .transition(.blurFade)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TabBar(tab: $tab)
                    .padding(.bottom, 4)
            }
            .blur(radius: showIntro ? 30 : 0)
            .scaleEffect(showIntro ? 1.06 : 1)

            if scanner.isBusy {
                ScanOverlay()
                    .transition(.blurFade)
                    .zIndex(5)
            }

            if showIntro {
                IntroView(onFinish: {
                    withAnimation(.easeInOut(duration: 0.8)) { showIntro = false }
                }, frozenTime: LaunchOptions.introTime)
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(.spring(response: 0.5, dampingFraction: 0.86), value: scanner.isBusy)
        .onAppear(perform: applyShot)
    }

    private func replayIntro() {
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

/// Schwebende Tab-Leiste aus Milchglas; die Markierung gleitet zwischen den Tabs.
struct TabBar: View {
    @Binding var tab: AppTab
    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 6) {
            ForEach(AppTab.allCases, id: \.self) { item in
                Button {
                    guard tab != item else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = item }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.icon)
                            .font(.system(size: 15, weight: .bold))
                        Text(item.title)
                            .font(Theme.rounded(14, weight: .bold))
                    }
                    .foregroundStyle(tab == item ? Color.black : .white.opacity(0.65))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background {
                        if tab == item {
                            Capsule()
                                .fill(LinearGradient(colors: [Theme.accent, Theme.accent.opacity(0.75)],
                                                     startPoint: .top, endPoint: .bottom))
                                .shadow(color: Theme.accent.opacity(0.55), radius: 12)
                                .matchedGeometryEffect(id: "pill", in: namespace)
                        }
                    }
                }
                .buttonStyle(PressableStyle())
            }
        }
        .padding(6)
        .frosted(cornerRadius: 32)
        .shadow(color: .black.opacity(0.45), radius: 20, y: 10)
    }
}

/// Vollbild während Kontrolle oder Löschen: die Mechaniker-Crew bei der Arbeit.
struct ScanOverlay: View {
    @EnvironmentObject private var scanner: FaultScanner

    var body: some View {
        let scanning = scanner.phase == .scanning
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Theme.background.opacity(0.55))
                .ignoresSafeArea()

            VStack(spacing: 18) {
                Spacer()
                VStack(spacing: 6) {
                    Text(scanning ? "Kontrolle läuft" : "Radiergummi im Einsatz")
                        .font(Theme.display(26))
                    Text(subtitle(scanning))
                        .font(Theme.rounded(15, weight: .medium))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .frame(minHeight: 40)
                        .animation(.easeInOut(duration: 0.25), value: scanner.currentStep)
                }
                .padding(.horizontal, 24)

                MechanicsLoader(progress: scanning ? scanner.progress : nil)
                    .padding(.horizontal, 12)

                if scanning {
                    Text("\(Int(scanner.progress * 100)) %")
                        .font(Theme.display(34))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
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
            return address == FaultScanner.obdAddress ? "Lösche OBD-II-Fehler …" : "Lösche \(FaultScanner.name(for: address)) …"
        }
        return "Einen Moment …"
    }
}
