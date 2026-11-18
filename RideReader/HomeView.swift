import SwiftUI

/// Tab „Zuhause“: Auto, Kontrolle-Knopf und – nach der Kontrolle – die gefundenen Fehler.
struct HomeView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession
    @EnvironmentObject private var scanner: FaultScanner
    @Binding var tab: AppTab

    @State private var clearTarget: ClearTarget?
    @State private var webLink: WebLink?
    @State private var showNotConnected = false
    @State private var showHealthy = false

    private var finished: Bool {
        if case .finished = scanner.phase { return true }
        return false
    }

    private var showFaults: Bool { finished && scanner.totalFaults > 0 }

    /// Schwerster Fehler über alle Steuergeräte und OBD-II
    private var worst: Severity? {
        let ecu = scanner.results.compactMap { FaultCatalog.worst($0.faults, ecu: $0.address) }.max()
        let obd = FaultCatalog.worst(scanner.obdCodes, ecu: nil)
        return [ecu, obd].compactMap { $0 }.max()
    }

    private var stateTint: Color {
        if showFaults { return Theme.color(worst) }
        if finished && scanner.abortReason == nil { return Theme.ok }
        return Theme.accent
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Hintergrund – tritt weich und abgedunkelt zurück, sobald Fehler gefunden wurden
            AmbientBackground(tint: stateTint, dimmed: showFaults)

            ScrollView {
                VStack(spacing: 22) {
                    header
                    if showFaults {
                        faultsContent
                            .transition(.blurRise)
                    } else {
                        startContent
                            .transition(.blurRise)
                    }
                }
                .pageWidth()
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)

            if let message = scanner.clearMessage {
                Toast(text: message, color: message.contains("wiedergekommen") || message.hasPrefix("Fehler") ? Theme.fault : Theme.ok)
                    .padding(.top, 8)
                    .pageWidth()
                    .transition(.move(edge: .top).combined(with: .blurFade))
                    .zIndex(3)
                    .onTapGesture { scanner.clearMessage = nil }
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 4_500_000_000)
                        if scanner.clearMessage == message { scanner.clearMessage = nil }
                    }
            }

            if let target = clearTarget {
                ClearWarningPopup(target: target, includesSevere: includesSevere(target)) {
                    clearTarget = nil
                    Haptics.warning()
                    Task { await perform(target) }
                } onCancel: {
                    clearTarget = nil
                }
                .transition(.blurFade)
                .zIndex(4)
            }
        }
        .foregroundStyle(.white)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: showFaults)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: clearTarget)
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: scanner.clearMessage)
        .sheet(item: $webLink) { link in
            WebSheet(url: link.url)
                .ignoresSafeArea()
        }
        .onAppear {
            if LaunchOptions.shot == "clear" { clearTarget = .all }
        }
        .onChange(of: scanner.phase) { phase in
            if case .finished = phase {
                scanner.totalFaults > 0 ? Haptics.warning() : Haptics.confirm()
            }
        }
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(spacing: 18) {
            // Schriftzug – an genau der Stelle, an der das Intro ihn absetzt
            LogoMark(size: IntroView.headerLogoSize)
                .frame(height: 32)
                .buildIn(delay: 0.85)

            ConnectionChip()
                .onTapGesture {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .settings }
                }
                .buildIn(0)

            VStack(spacing: 6) {
                Text("Zuhause")
                    .font(Theme.display(40))
                    .foregroundStyle(Theme.titleGradient)
                Text(greeting)
                    .font(Theme.rounded(16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .animation(.easeInOut, value: greeting)
            }
            .buildIn(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private var greeting: String {
        if showFaults {
            return worst == .severe ? "Uff. Die Crew hat was Ernstes gefunden." : "Die Crew hat was gefunden."
        }
        if finished && scanner.abortReason == nil { return "Alles sauber. Die Crew macht Kaffeepause." }
        return "Na, wie geht's der Karre heute?"
    }

    // MARK: - Start

    private var startContent: some View {
        VStack(spacing: 22) {
            if let reason = scanner.abortReason {
                InfoCard(icon: "exclamationmark.triangle.fill", color: Theme.fault,
                         title: "Kontrolle abgebrochen", text: reason)
            }

            if finished && scanner.abortReason == nil {
                allGoodCard
            }

            ControlOrb(subtitle: finished ? "Nochmal durchchecken" : "Fehlerspeicher lesen",
                       healthy: finished && scanner.abortReason == nil) {
                Haptics.tap()
                if session.isInitialized {
                    showNotConnected = false
                    scanner.start()
                } else {
                    showNotConnected = true
                }
            }
            .padding(.vertical, 6)
            .buildIn(2, rise: 40)

            if showNotConnected && !session.isInitialized {
                notConnectedCard
                    .transition(.blurRise)
            }

            ModePicker(mode: $scanner.mode)
                .buildIn(3)

            dpfTile
                .buildIn(4)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showNotConnected)
    }

    /// Einstieg zur Rußfilter-Seite
    private var dpfTile: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .dpf }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(LinearGradient(colors: [Theme.violet.opacity(0.35), Theme.magenta.opacity(0.2)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    DPFLampIcon(size: 24)
                        .foregroundStyle(Theme.brandGradient)
                }
                .frame(width: 46, height: 46)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Rußfilter")
                        .font(Theme.rounded(17, weight: .bold))
                    Text("Beladung, Temperaturen & Regeneration – live")
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card(tint: Theme.violet)
        }
        .buttonStyle(PressableStyle())
    }

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Kein OBD-Stecker verbunden", systemImage: "cable.connector.slash")
                .font(Theme.rounded(16, weight: .bold))
            Text("Die Crew braucht eine Leitung zum Auto. Verbinde den Adapter unter Einstellungen – oder schau dir erst eine Beispiel-Kontrolle an.")
                .font(Theme.rounded(14, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .settings }
                } label: {
                    Text("Verbinden")
                        .font(Theme.rounded(14, weight: .bold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(LinearGradient(colors: [Theme.accent, Theme.violet.opacity(0.9)],
                                                                  startPoint: .leading, endPoint: .trailing)))
                }
                Button {
                    showNotConnected = false
                    scanner.runDemoScan()
                } label: {
                    Text("Beispiel ansehen")
                        .font(Theme.rounded(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().strokeBorder(.white.opacity(0.3)))
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.violet)
    }

    private var allGoodCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(Theme.ok)
                .background(Glow(color: Theme.ok, opacity: 0.5).frame(width: 70, height: 70))
            VStack(alignment: .leading, spacing: 4) {
                Text("Alles im grünen Bereich")
                    .font(Theme.rounded(18, weight: .bold))
                Text("\(scanner.results.count) Steuergeräte befragt – keins hat gemeckert.")
                    .font(Theme.rounded(14, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(18)
        .card(tint: Theme.ok)
    }

    // MARK: - Fehler

    private var faultsContent: some View {
        VStack(spacing: 16) {
            summaryCard

            ForEach(faultyECUs) { result in
                ECUSection(
                    title: result.name,
                    subtitle: result.hexAddress,
                    faults: result.faults,
                    ecu: result.address,
                    isClearing: scanner.clearingAddress == result.address,
                    onClear: { clearTarget = .ecu(result.address, result.name) },
                    onWeb: { webLink = WebLink(url: $0) },
                    onDPF: openDPF)
            }

            if !scanner.obdCodes.isEmpty {
                ECUSection(
                    title: "OBD-II · Motor & Abgas",
                    subtitle: "genormt",
                    faults: scanner.obdCodes,
                    ecu: nil,
                    isClearing: scanner.clearingAddress == FaultScanner.obdAddress,
                    onClear: { clearTarget = .obd },
                    onWeb: { webLink = WebLink(url: $0) },
                    onDPF: openDPF)
            }

            healthyList

            Button {
                Haptics.tap()
                clearTarget = .all
            } label: {
                Label("Alle Fehler löschen", systemImage: "eraser.fill")
                    .font(Theme.rounded(16, weight: .bold))
                    .foregroundStyle(Theme.color(worst))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Theme.color(worst).opacity(0.12))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .strokeBorder(Theme.color(worst).opacity(0.6), lineWidth: 1.2)
                    )
            }
            .buttonStyle(PressableStyle())
            .disabled(scanner.isBusy || faultyECUs.isEmpty)
            .opacity(faultyECUs.isEmpty ? 0.4 : 1)
        }
    }

    private var faultyECUs: [ECUResult] {
        scanner.results
            .filter { !$0.faults.isEmpty }
            .sorted {
                (FaultCatalog.worst($0.faults, ecu: $0.address) ?? .fault) > (FaultCatalog.worst($1.faults, ecu: $1.address) ?? .fault)
            }
    }

    private var summaryCard: some View {
        let all = scanner.results.flatMap { r in r.faults.map { FaultCatalog.info(for: $0, ecu: r.address) } }
            + scanner.obdCodes.map { FaultCatalog.info(for: $0, ecu: nil) }
        let severe = all.filter { $0.severity == .severe }.count
        let normal = all.count - severe
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(all.count)")
                    .font(Theme.display(64))
                    .foregroundStyle(LinearGradient(colors: [.white, Theme.color(worst)], startPoint: .top, endPoint: .center))
                    .contentTransition(.numericText())
                VStack(alignment: .leading, spacing: 2) {
                    Text(all.count == 1 ? "Fehler gefunden" : "Fehler gefunden")
                        .font(Theme.rounded(18, weight: .bold))
                    Text(scanner.isDemo ? "Beispieldaten" : "in \(faultyECUs.count + (scanner.obdCodes.isEmpty ? 0 : 1)) Bereichen")
                        .font(Theme.rounded(13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            HStack(spacing: 8) {
                if severe > 0 {
                    CountChip(count: severe, label: "schwerwiegend", color: Theme.severe)
                }
                if normal > 0 {
                    CountChip(count: normal, label: normal == 1 ? "Fehler" : "Fehler", color: Theme.fault)
                }
            }
            HStack(spacing: 10) {
                Button {
                    Haptics.tap()
                    scanner.reset()
                } label: {
                    Label("Neue Kontrolle", systemImage: "arrow.clockwise")
                        .font(Theme.rounded(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
                ShareLink(item: scanner.reportText) {
                    Label("Bericht", systemImage: "square.and.arrow.up")
                        .font(Theme.rounded(14, weight: .bold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
            }
            .buttonStyle(PressableStyle())
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.color(worst))
    }

    private var healthyList: some View {
        let healthy = scanner.results.filter { $0.faults.isEmpty }
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showHealthy.toggle() }
            } label: {
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.ok)
                    Text("\(healthy.count) Steuergeräte ohne Fehler")
                        .font(Theme.rounded(15, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showHealthy ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            if showHealthy {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(healthy) { result in
                        HStack {
                            Text(result.name)
                            Spacer()
                            Text(result.error == nil ? result.hexAddress : "nicht lesbar")
                                .foregroundStyle(result.error == nil ? .white.opacity(0.4) : Theme.fault)
                        }
                        .font(Theme.rounded(13, weight: .medium))
                    }
                }
                .transition(.blurFade)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(cornerRadius: 22)
        .opacity(healthy.isEmpty ? 0 : 1)
    }

    private func openDPF() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .dpf }
    }

    // MARK: - Löschen

    private func includesSevere(_ target: ClearTarget) -> Bool {
        switch target {
        case .ecu(let address, _):
            let faults = scanner.results.first { $0.address == address }?.faults ?? []
            return FaultCatalog.worst(faults, ecu: address) == .severe
        case .obd:
            return FaultCatalog.worst(scanner.obdCodes, ecu: nil) == .severe
        case .all:
            return scanner.results.contains { FaultCatalog.worst($0.faults, ecu: $0.address) == .severe }
        }
    }

    private func perform(_ target: ClearTarget) async {
        switch target {
        case .ecu(let address, _): await scanner.clear(address)
        case .all: await scanner.clearAll()
        case .obd: await scanner.clearOBD()
        }
    }
}

// MARK: - Bausteine der Startseite

/// Der große runde „Kontrolle“-Knopf: rotierender Verlaufsring, atmendes Leuchten, kreisender Lichtpunkt.
/// Alle Bewegungen laufen als Core-Animation (kein Neuzeichnen pro Bild) – dadurch butterweich.
struct ControlOrb: View {
    var subtitle: String
    var healthy: Bool = false
    var action: () -> Void

    @State private var spin = false
    @State private var breathe = false

    private let diameter: CGFloat = 236

    private var ringColors: [Color] {
        healthy ? [Theme.ok, Theme.accent, Theme.ok.opacity(0.6), Theme.accent, Theme.ok] : Theme.brandLoop
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                // Leuchten: drei weiche Farbflecken (Radialverläufe statt Blur), drehen sich mit dem Ring
                ZStack {
                    Glow(color: ringColors[0], opacity: 0.5)
                        .frame(width: diameter * 1.1, height: diameter * 1.1)
                        .offset(x: -diameter * 0.12, y: -diameter * 0.1)
                    Glow(color: ringColors[2], opacity: 0.45)
                        .frame(width: diameter * 1.1, height: diameter * 1.1)
                        .offset(x: diameter * 0.14, y: -diameter * 0.02)
                    Glow(color: ringColors[3], opacity: 0.4)
                        .frame(width: diameter * 1.1, height: diameter * 1.1)
                        .offset(x: -diameter * 0.02, y: diameter * 0.14)
                }
                .opacity(breathe ? 1 : 0.6)
                .scaleEffect(breathe ? 1.05 : 0.95)
                .rotationEffect(.degrees(spin ? 360 : 0))

                // Verlaufsring
                Circle()
                    .strokeBorder(AngularGradient(colors: ringColors, center: .center), lineWidth: 3.5)
                    .rotationEffect(.degrees(spin ? 360 : 0))

                // Innere Glasscheibe
                Circle()
                    .fill(RadialGradient(colors: [Color(red: 0.11, green: 0.12, blue: 0.2), Theme.background],
                                         center: UnitPoint(x: 0.35, y: 0.25), startRadius: 0, endRadius: diameter * 0.7))
                    .overlay(Circle().strokeBorder(
                        LinearGradient(colors: [.white.opacity(0.3), .white.opacity(0.02)], startPoint: .top, endPoint: .bottom),
                        lineWidth: 1))
                    .padding(9)

                // Feine Skala, dreht gegenläufig
                Circle()
                    .stroke(.white.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [1.5, 7]))
                    .padding(22)
                    .rotationEffect(.degrees(spin ? -360 : 0))

                // Kreisender Lichtpunkt auf dem Ring
                ZStack {
                    Glow(color: Theme.accent, opacity: 0.9).frame(width: 30, height: 30)
                    Circle().fill(.white).frame(width: 7, height: 7)
                }
                .offset(y: -(diameter / 2 - 1.75))
                    .rotationEffect(.degrees(spin ? 360 : 0))

                VStack(spacing: 8) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundStyle(healthy ? LinearGradient(colors: [Theme.ok, Theme.accent], startPoint: .topLeading, endPoint: .bottomTrailing)
                                         : Theme.brandGradient)
                    Text("Kontrolle")
                        .font(Theme.display(27))
                        .foregroundStyle(Theme.titleGradient)
                    Text(subtitle)
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                }
                .overlay(Shimmer().mask {
                    Text("Kontrolle").font(Theme.display(27))
                })
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(PressableStyle())
        .onAppear {
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { breathe = true }
        }
        .animation(.easeInOut(duration: 0.8), value: healthy)
    }
}

/// Glanzstreifen, der regelmäßig über einen Knopf läuft.
/// Läuft als eine einzige Core-Animation (kein Neuaufbau der Ansicht pro Bild).
struct Shimmer: View {
    @State private var move = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            LinearGradient(colors: [.clear, .white.opacity(0.55), .clear], startPoint: .leading, endPoint: .trailing)
                .frame(width: w * 0.35)
                .rotationEffect(.degrees(18))
                // Weg ist viel länger als der Knopf → nach dem Durchlauf ~2 s Pause, ohne Timer
                .offset(x: move ? w * 3.2 : -w * 0.5)
        }
        .clipped()
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 3.2).repeatForever(autoreverses: false)) { move = true }
        }
    }
}

struct ConnectionChip: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession

    var body: some View {
        let color: Color = session.isInitialized ? Theme.ok
            : (ble.status == .ready || ble.status == .connecting || ble.status == .scanning) ? .yellow : .gray
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(session.isInitialized ? "Verbunden" : ble.status == .idle ? "Nicht verbunden" : ble.status.text)
                .font(Theme.rounded(12, weight: .bold))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frosted(cornerRadius: 18)
    }
}

/// Schnell- oder Vollscan.
struct ModePicker: View {
    @Binding var mode: FaultScanner.Mode

    var body: some View {
        HStack(spacing: 8) {
            ForEach(FaultScanner.Mode.allCases) { item in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { mode = item }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Image(systemName: item == .quick ? "hare.fill" : "tortoise.fill")
                            Text(item == .quick ? "Schnell" : "Gründlich")
                        }
                        .font(Theme.rounded(14, weight: .bold))
                        Text(item == .quick ? "Wichtigste Steuergeräte · ~10 s" : "Alle Adressen · ~1 min")
                            .font(Theme.rounded(11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(mode == item
                                  ? AnyShapeStyle(LinearGradient(colors: [Theme.accent.opacity(0.2), Theme.violet.opacity(0.16)],
                                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                                  : AnyShapeStyle(Color.white.opacity(0.04)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .strokeBorder(mode == item
                                          ? AnyShapeStyle(LinearGradient(colors: [Theme.accent, Theme.violet, Theme.magenta],
                                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                                          : AnyShapeStyle(Color.white.opacity(0.08)), lineWidth: 1.2)
                    )
                }
                .buttonStyle(PressableStyle())
            }
        }
    }
}

struct InfoCard: View {
    var icon: String
    var color: Color
    var title: String
    var text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(Theme.rounded(16, weight: .bold))
                Text(text)
                    .font(Theme.rounded(13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .card(tint: color)
    }
}

struct Toast: View {
    var text: String
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: color == Theme.ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(color)
            Text(text)
                .font(Theme.rounded(14, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .frosted(cornerRadius: 20)
    }
}

struct CountChip: View {
    var count: Int
    var label: String
    var color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text("\(count) \(label)")
        }
        .font(Theme.rounded(13, weight: .bold))
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Capsule().fill(color.opacity(0.14)))
        .overlay(Capsule().strokeBorder(color.opacity(0.4), lineWidth: 1))
    }
}
