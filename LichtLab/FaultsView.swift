import SwiftUI

/// Fehlerspeicher auslesen – reine Leseansicht, es wird nichts gelöscht.
struct FaultsView: View {
    @EnvironmentObject private var scanner: FaultScanner
    @EnvironmentObject private var session: ELMSession
    var onConnect: () -> Void

    @State private var expanded: Set<UInt8> = []
    @State private var showOnlyFaulty = false
    @Namespace private var namespace

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                header

                if !session.isInitialized && scanner.phase != .scanning && !scanner.isDemo {
                    notConnectedCard.transition(.blurFade)
                }

                modePicker
                scanButton

                if case .finished = scanner.phase {
                    summary.transition(.blurFade)
                    resultsList.transition(.blurFade)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 40)
            .animation(.spring(response: 0.5, dampingFraction: 0.85), value: scanner.phase)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: expanded)
            .animation(.spring(response: 0.45, dampingFraction: 0.85), value: showOnlyFaulty)
        }
        .foregroundStyle(.white)
    }

    // MARK: - Kopf

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Fehlerspeicher")
                    .font(.largeTitle.weight(.semibold))
                Spacer()
                if case .finished = scanner.phase {
                    ShareLink(item: scanner.reportText) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 15, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .glass(cornerRadius: 19)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 6) {
                Image(systemName: "lock.fill").font(.caption2)
                Text("Nur auslesen – es wird nichts gelöscht oder verändert.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            if let vin = scanner.vin {
                Text("FIN \(vin)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var notConnectedCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Adapter nicht verbunden", systemImage: "antenna.radiowaves.left.and.right.slash")
                .font(.headline)
            Text("Zündung einschalten, vLinker einstecken und verbinden. Oder schau dir die Ansicht mit Beispieldaten an.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button("Verbinden", action: onConnect)
                    .buttonStyle(CapsuleButtonStyle(prominent: true))
                Button("Beispiel ansehen") {
                    Haptics.tap()
                    scanner.loadDemo()
                }
                .buttonStyle(CapsuleButtonStyle(prominent: false))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 24)
    }

    // MARK: - Scan

    private var modePicker: some View {
        VStack(spacing: 6) {
            HStack(spacing: 2) {
                ForEach(FaultScanner.Mode.allCases) { mode in
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { scanner.mode = mode }
                    } label: {
                        Text(mode.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .foregroundStyle(scanner.mode == mode ? Color.black : Color.white.opacity(0.8))
                            .background {
                                if scanner.mode == mode {
                                    Capsule().fill(.white).matchedGeometryEffect(id: "mode", in: namespace)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(.white.opacity(0.08)))
            Text(scanner.mode.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .disabled(scanner.phase == .scanning)
    }

    private var scanButton: some View {
        let scanning = scanner.phase == .scanning
        return Button {
            Haptics.confirm()
            if scanning { scanner.cancel() } else { scanner.start() }
        } label: {
            ZStack {
                if scanning {
                    // Radar-Wellen
                    TimelineView(.animation) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        ZStack {
                            ForEach(0..<3) { i in
                                let phase = (t / 2.4 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                                Circle()
                                    .stroke(Color.cyan.opacity(0.5 * (1 - phase)), lineWidth: 1.5)
                                    .scaleEffect(1 + phase * 0.6)
                            }
                            Circle()
                                .trim(from: 0, to: 0.25)
                                .stroke(AngularGradient(colors: [.clear, .cyan], center: .center), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(t * 240))
                        }
                    }
                }

                Circle()
                    .fill(.ultraThinMaterial)
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))

                Circle()
                    .trim(from: 0, to: scanner.progress)
                    .stroke(Color.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(6)
                    .opacity(scanning ? 1 : 0)
                    .animation(.easeInOut(duration: 0.3), value: scanner.progress)

                VStack(spacing: 6) {
                    if scanning {
                        Text("\(Int(scanner.progress * 100)) %")
                            .font(.system(size: 34, weight: .light).monospacedDigit())
                        Text(scanner.currentStep)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(maxWidth: 130)
                        Text("Abbrechen")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.cyan)
                    } else {
                        Image(systemName: "stethoscope")
                            .font(.system(size: 34, weight: .light))
                        Text(scanner.phase == .idle ? "Scan starten" : "Erneut scannen")
                            .font(.subheadline.weight(.semibold))
                    }
                }
                .transition(.blurFade)
            }
            .frame(width: 190, height: 190)
            .shadow(color: scanning ? .cyan.opacity(0.35) : .clear, radius: 30)
        }
        .buttonStyle(PressScaleStyle())
        .disabled(!session.isInitialized && !scanning)
        .opacity(!session.isInitialized && !scanning ? 0.5 : 1)
        .padding(.vertical, 8)
    }

    // MARK: - Ergebnis

    private var summary: some View {
        HStack(spacing: 10) {
            StatTile(value: "\(scanner.results.count)", label: "Steuergeräte", tint: .white)
            StatTile(value: "\(scanner.totalFaults)", label: "Einträge", tint: scanner.totalFaults == 0 ? .green : .orange)
            StatTile(value: "\(scanner.activeFaults)", label: "aktiv", tint: scanner.activeFaults == 0 ? .green : .red)
        }
    }

    private var visibleResults: [ECUResult] {
        showOnlyFaulty ? scanner.results.filter { !$0.faults.isEmpty || $0.error != nil } : scanner.results
    }

    private var resultsList: some View {
        VStack(spacing: 10) {
            HStack {
                Text(scanner.isDemo ? "Beispieldaten" : "Steuergeräte")
                    .font(.headline)
                Spacer()
                Toggle("Nur mit Fehlern", isOn: $showOnlyFaulty)
                    .toggleStyle(.button)
                    .font(.caption.weight(.semibold))
                    .tint(.cyan)
            }

            ForEach(visibleResults) { result in
                ECUCard(result: result, isExpanded: expanded.contains(result.address)) {
                    Haptics.tap()
                    if expanded.contains(result.address) {
                        expanded.remove(result.address)
                    } else {
                        expanded.insert(result.address)
                    }
                }
                .transition(.blurFade)
            }

            OBDCard(codes: scanner.obdCodes)

            Text("BMW-Codes sind herstellerspezifisch. Die Bedeutung findest du z. B. per Suche nach „BMW <Code>“.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }
}

// MARK: - Bausteine

private struct StatTile: View {
    let value: String
    let label: String
    let tint: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                .foregroundStyle(tint)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .glass(cornerRadius: 20)
    }
}

private struct ECUCard: View {
    let result: ECUResult
    let isExpanded: Bool
    let toggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: toggle) {
                HStack(spacing: 12) {
                    badge
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name)
                            .font(.subheadline.weight(.semibold))
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !result.faults.isEmpty {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(result.faults.isEmpty)

            if isExpanded {
                VStack(spacing: 8) {
                    ForEach(result.faults) { fault in
                        FaultRow(fault: fault)
                    }
                }
                .padding(.top, 12)
                .transition(.blurFade)
            }
        }
        .padding(14)
        .glass(cornerRadius: 20)
    }

    private var subtitle: String {
        if let error = result.error { return "\(result.hexAddress) · \(error)" }
        switch result.faults.count {
        case 0: return "\(result.hexAddress) · keine Einträge"
        case 1: return "\(result.hexAddress) · 1 Eintrag"
        default: return "\(result.hexAddress) · \(result.faults.count) Einträge"
        }
    }

    @ViewBuilder private var badge: some View {
        let count = result.faults.count
        ZStack {
            Circle()
                .fill(color.opacity(0.18))
            if result.error != nil {
                Image(systemName: "questionmark").font(.caption.weight(.bold))
            } else if count == 0 {
                Image(systemName: "checkmark").font(.caption.weight(.bold))
            } else {
                Text("\(count)").font(.caption.weight(.bold).monospacedDigit())
            }
        }
        .foregroundStyle(color)
        .frame(width: 32, height: 32)
    }

    private var color: Color {
        if result.error != nil { return .gray }
        if result.faults.contains(where: \.isActive) { return .red }
        return result.faults.isEmpty ? .green : .orange
    }
}

private struct FaultRow: View {
    let fault: FaultCode

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(fault.code)
                .font(.callout.monospaced().weight(.semibold))
                .textSelection(.enabled)
            Spacer()
            HStack(spacing: 4) {
                if fault.isActive { chip("Aktiv", .red) }
                if fault.isConfirmed { chip("Gespeichert", .orange) }
                if fault.isPending { chip("Sporadisch", .yellow) }
                if fault.warningLamp { chip("Lampe", .red) }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(color)
            .background(Capsule().fill(color.opacity(0.16)))
    }
}

private struct OBDCard: View {
    let codes: [FaultCode]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: "engine.combustion")
                    .frame(width: 32, height: 32)
                    .background(Circle().fill((codes.isEmpty ? Color.green : Color.orange).opacity(0.18)))
                    .foregroundStyle(codes.isEmpty ? Color.green : Color.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("OBD-II · Motor & Abgas")
                        .font(.subheadline.weight(.semibold))
                    Text(codes.isEmpty ? "Genormte Codes · keine Einträge" : "Genormte Codes · \(codes.count) Einträge")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(codes) { fault in
                FaultRow(fault: fault)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glass(cornerRadius: 20)
    }
}

private struct CapsuleButtonStyle: ButtonStyle {
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .foregroundStyle(prominent ? Color.black : Color.white)
            .background(Capsule().fill(prominent ? Color.white : Color.white.opacity(0.12)))
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct PressScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
