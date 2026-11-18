import SwiftUI

/// Tab „Einstellungen“: OBD-Stecker verbinden, Scan-Art, Werkzeuge und Hinweise.
struct SettingsTab: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession
    @EnvironmentObject private var scanner: FaultScanner
    @Binding var tab: AppTab
    var replayIntro: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                AmbientBackground(tint: session.isInitialized ? Theme.ok : Theme.accent)
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(spacing: 6) {
                            Text("Einstellungen")
                                .font(Theme.display(34))
                                .foregroundStyle(Theme.titleGradient)
                                .minimumScaleFactor(0.7)
                                .lineLimit(1)
                            Text("Hier wird geschraubt – an der App.")
                                .font(Theme.rounded(16, weight: .medium))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 20)
                        .buildIn(0)

                        connectionCard.buildIn(1)
                        section("Kontrolle") { ModePicker(mode: $scanner.mode) }.buildIn(2)
                        toolsCard.buildIn(3)
                        tipsCard.buildIn(4)

                        Text("RideReader \(version) · gebaut mit Liebe und einem 10er-Schlüssel")
                            .font(Theme.rounded(12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity)
                            .padding(.top, 6)
                    }
                    .pageWidth()
                    .padding(.bottom, 30)
                }
                .scrollIndicators(.hidden)
            }
            .foregroundStyle(.white)
            #if os(iOS)
            .toolbar(.hidden, for: .navigationBar)
            #endif
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    // MARK: - OBD-Stecker

    private var statusColor: Color {
        if session.isInitialized { return Theme.ok }
        switch ble.status {
        case .scanning, .connecting, .ready: return .yellow
        case .failed, .bluetoothOff, .unauthorized: return Theme.fault
        case .idle: return .gray
        }
    }

    private var statusTitle: String {
        if session.isInitialized { return "Verbunden & bereit" }
        if ble.status == .ready { return "Initialisiere Adapter …" }
        return ble.status.text
    }

    private var connectionCard: some View {
        section("OBD-Stecker") {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    StatusOrb(color: statusColor, active: ble.status == .scanning || ble.status == .connecting)
                        .frame(width: 58, height: 58)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(Theme.rounded(17, weight: .bold))
                        if let name = ble.connectedName {
                            Text(name).font(Theme.rounded(13, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                        }
                        if let info = session.adapterInfo {
                            Text(info).font(.caption.monospaced()).foregroundStyle(.white.opacity(0.45)).lineLimit(1)
                        }
                    }
                    Spacer(minLength: 0)
                }

                connectionButtons

                if ble.status != .ready && !ble.devices.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(ble.devices) { device in
                            Button {
                                Haptics.tap()
                                ble.connect(device)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: device.looksLikeOBDAdapter ? "car.side.fill" : "dot.radiowaves.left.and.right")
                                        .foregroundStyle(device.looksLikeOBDAdapter ? Theme.accent : .white.opacity(0.5))
                                        .frame(width: 26)
                                    Text(device.name)
                                        .font(Theme.rounded(15, weight: .semibold))
                                    Spacer()
                                    SignalBars(rssi: device.rssi)
                                    Text("Verbinden")
                                        .font(Theme.rounded(12, weight: .bold))
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(12)
                                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.05)))
                            }
                            .buttonStyle(PressableStyle())
                            .transition(.blurFade)
                        }
                    }
                }

                Text("Zündung an (Start/Stopp ohne Bremse), Motor aus, vLinker in die OBD-Buchse unten links im Fußraum. Bitte hier verbinden, nicht in den iOS-Bluetooth-Einstellungen.")
                    .font(Theme.rounded(12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.85), value: ble.devices.map(\.id))
        }
    }

    @ViewBuilder
    private var connectionButtons: some View {
        switch ble.status {
        case .ready:
            HStack(spacing: 10) {
                pillButton("Neu initialisieren", icon: "arrow.triangle.2.circlepath", filled: false) {
                    Task { await session.initialize() }
                }
                pillButton("Trennen", icon: "xmark", filled: false, color: Theme.severe) {
                    ble.disconnect()
                }
            }
            if session.isInitialized {
                pillButton("Zur Kontrolle", icon: "wrench.and.screwdriver.fill", filled: true) {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .home }
                }
            }
        case .scanning:
            pillButton("Suche stoppen", icon: "stop.fill", filled: false) { ble.stopScan() }
        case .connecting:
            pillButton("Verbinde …", icon: "hourglass", filled: false) {}
                .disabled(true)
        case .bluetoothOff, .unauthorized:
            Text(ble.status == .bluetoothOff ? "Bitte Bluetooth im Kontrollzentrum einschalten."
                 : "Bitte in den iOS-Einstellungen Bluetooth für RideReader erlauben.")
                .font(Theme.rounded(14, weight: .semibold))
                .foregroundStyle(Theme.fault)
        default:
            pillButton("OBD-Stecker suchen", icon: "antenna.radiowaves.left.and.right", filled: true) {
                ble.startScan()
            }
        }
    }

    private func pillButton(_ title: String, icon: String, filled: Bool, color: Color = Theme.accent,
                            action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            Label(title, systemImage: icon)
                .font(Theme.rounded(15, weight: .bold))
                .foregroundStyle(filled ? Color.white : color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(
                    Capsule().fill(filled
                                   ? AnyShapeStyle(LinearGradient(colors: [color, Theme.violet.opacity(0.85)],
                                                                  startPoint: .leading, endPoint: .trailing))
                                   : AnyShapeStyle(color.opacity(0.12)))
                )
                .overlay(Capsule().strokeBorder(color.opacity(filled ? 0 : 0.45), lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
    }

    // MARK: - Werkzeuge & Hinweise

    private var toolsCard: some View {
        section("Werkzeuge") {
            VStack(spacing: 4) {
                NavigationLink {
                    ConsoleView()
                } label: {
                    row("Diagnose-Konsole", icon: "terminal.fill", detail: "Befehle & Protokoll")
                }
                Divider().overlay(.white.opacity(0.08))
                NavigationLink {
                    DPFView()
                        #if os(iOS)
                        .toolbar(.hidden, for: .navigationBar)
                        #endif
                } label: {
                    row("Rußfilter", icon: "aqi.medium", detail: "Live-Werte")
                }
                Divider().overlay(.white.opacity(0.08))
                Button {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { tab = .home }
                    scanner.runDemoScan()
                } label: {
                    row("Beispiel-Kontrolle", icon: "sparkles", detail: "ohne Auto")
                }
                .disabled(scanner.isBusy)
                Divider().overlay(.white.opacity(0.08))
                Button(action: replayIntro) {
                    row("Intro nochmal ansehen", icon: "film.fill", detail: nil)
                }
            }
            .buttonStyle(.plain)
        }
    }

    private func row(_ title: String, icon: String, detail: String?) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.brandGradient)
                .frame(width: 26)
            Text(title).font(Theme.rounded(15, weight: .semibold))
            Spacer()
            if let detail {
                Text(detail).font(Theme.rounded(12, weight: .medium)).foregroundStyle(.white.opacity(0.45))
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.3))
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private var tipsCard: some View {
        section("Vor dem Löschen") {
            VStack(alignment: .leading, spacing: 12) {
                tip("key.fill", "Zündung an, Motor aus, Auto steht.")
                tip("square.and.arrow.up", "Erst auslesen und den Bericht teilen – gelöschte Codes sind weg.")
                tip("wrench.adjustable.fill", "Löschen ersetzt keine Reparatur. Kommt ein Fehler sofort wieder, besteht die Ursache noch.")
                tip("exclamationmark.octagon.fill", "Rote Fehler (Airbag, Bremse, Lenkung) nicht einfach löschen, sondern prüfen lassen.", color: Theme.severe)
                tip("engine.combustion.fill", "OBD-II-Löschen setzt die Bereitschaftstests zurück – vor der AU/HU erst wieder ein Stück fahren.")
            }
        }
    }

    private func tip(_ icon: String, _ text: String, color: Color = Theme.fault) -> some View {
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

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(LinearGradient(colors: [Theme.accent, Theme.violet], startPoint: .leading, endPoint: .trailing))
                .padding(.leading, 6)
            content()
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }
}

/// Pulsierender Status-Punkt mit Wellenringen während der Suche.
struct StatusOrb: View {
    var color: Color
    var active: Bool

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                if active {
                    ForEach(0..<3) { i in
                        let p = fmod(t * 0.8 + Double(i) / 3, 1)
                        Circle()
                            .strokeBorder(color.opacity(1 - p), lineWidth: 2)
                            .scaleEffect(0.4 + 0.6 * p)
                    }
                }
                Circle()
                    .fill(RadialGradient(colors: [color, color.opacity(0.3)], center: .center, startRadius: 0, endRadius: 18))
                    .frame(width: 26, height: 26)
                    .shadow(color: color, radius: 10 + 4 * sin(t * 3))
                Image(systemName: "cable.connector")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black.opacity(0.7))
            }
        }
    }
}

struct SignalBars: View {
    var rssi: Int

    var body: some View {
        let level = rssi > -60 ? 3 : rssi > -75 ? 2 : 1
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(1...3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 1)
                    .fill(i <= level ? Theme.accent : .white.opacity(0.2))
                    .frame(width: 3, height: CGFloat(4 + i * 3))
            }
        }
    }
}
