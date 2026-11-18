import SwiftUI
#if os(iOS)
import SafariServices
#endif

/// Ein Steuergerät mit seinen Fehlern.
struct ECUSection: View {
    var title: String
    var subtitle: String
    var faults: [FaultCode]
    var ecu: UInt8?
    var isClearing: Bool
    var onClear: () -> Void
    var onWeb: (URL) -> Void
    var onDPF: () -> Void = {}

    var body: some View {
        let infos = faults.map { FaultCatalog.info(for: $0, ecu: ecu) }
        let color = Theme.color(infos.map(\.severity).max())
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Circle()
                    .fill(color)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(Theme.rounded(16, weight: .bold))
                    Text("\(subtitle) · \(faults.count) \(faults.count == 1 ? "Eintrag" : "Einträge")")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                Button {
                    Haptics.tap()
                    onClear()
                } label: {
                    HStack(spacing: 6) {
                        if isClearing {
                            ProgressView().controlSize(.small).tint(color)
                        } else {
                            Image(systemName: "eraser.fill")
                        }
                        Text("Löschen")
                    }
                    .font(Theme.rounded(13, weight: .bold))
                    .foregroundStyle(color)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(color.opacity(0.14)))
                    .overlay(Capsule().strokeBorder(color.opacity(0.45), lineWidth: 1))
                }
                .buttonStyle(PressableStyle())
                .disabled(isClearing)
            }
            .padding(.horizontal, 4)

            ForEach(Array(zip(faults, infos)), id: \.0.id) { fault, info in
                FaultCard(fault: fault, info: info, onWeb: { onWeb(info.searchURL) }, onDPF: onDPF)
            }
        }
    }
}

/// Ein einzelner Fehler: Code, Klartext, Erklärung, Tipp, Status – und daneben der Web-Knopf.
/// Bei Rußfilter-Fehlern steht dort stattdessen der DPF-Knopf, und Kenji gibt einen Tipp.
struct FaultCard: View {
    var fault: FaultCode
    var info: FaultInfo
    var onWeb: () -> Void
    var onDPF: () -> Void = {}

    @State private var expanded = false

    var body: some View {
        let color = Theme.color(info.severity)
        HStack(alignment: .top, spacing: 14) {
            Capsule()
                .fill(LinearGradient(colors: [color, color.opacity(0.35)], startPoint: .top, endPoint: .bottom))
                .frame(width: 4)

            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Text(info.code)
                        .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        .foregroundStyle(color)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(color.opacity(0.14)))
                    Text(info.severity.label.uppercased())
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.2)
                        .foregroundStyle(color.opacity(0.9))
                    Spacer(minLength: 0)
                }

                Text(info.headline)
                    .font(Theme.rounded(16, weight: .bold))
                    .fixedSize(horizontal: false, vertical: true)

                Text(info.explanation)
                    .font(Theme.rounded(13, weight: .regular))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)

                if expanded {
                    Label(info.hint, systemImage: "lightbulb.fill")
                        .font(Theme.rounded(13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .transition(.blurFade)
                }

                HStack(spacing: 6) {
                    ForEach(fault.statusText.components(separatedBy: ", "), id: \.self) { part in
                        Text(part)
                            .font(Theme.rounded(11, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(.white.opacity(part == "aktiv" || part == "Warnlampe" ? 0.16 : 0.07)))
                            .foregroundStyle(part == "aktiv" || part == "Warnlampe" ? color : .white.opacity(0.7))
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.4))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
            }

            if !info.isDPF {
                // Web-Knopf
                Button {
                    Haptics.tap()
                    onWeb()
                } label: {
                    VStack(spacing: 4) {
                        ZStack {
                            Circle()
                                .fill(color.opacity(0.16))
                            Circle()
                                .strokeBorder(color.opacity(0.5), lineWidth: 1)
                            Image(systemName: "safari.fill")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(color)
                        }
                        .frame(width: 44, height: 44)
                        Text("Web")
                            .font(Theme.rounded(10, weight: .bold))
                            .foregroundStyle(color.opacity(0.9))
                    }
                }
                .buttonStyle(PressableStyle())
                .accessibilityLabel("\(info.code) im Internet nachschlagen")
            }
        }
        .padding(16)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if info.isDPF {
                // Sprechblase → Kenji → DPF-Knopf
                HStack(alignment: .bottom, spacing: 6) {
                    Spacer(minLength: 0)
                    CrewHint(text: "Versuch's doch mal mit einer Regeneration!")
                        .onTapGesture {
                            Haptics.tap()
                            onDPF()
                        }
                    dpfButton(color)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .card(cornerRadius: 22, tint: color)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded.toggle() }
        }
    }

    /// Knopf mit DPF-Kontrollleuchte – öffnet den Rußfilter-Tab.
    private func dpfButton(_ color: Color) -> some View {
        Button {
            Haptics.tap()
            onDPF()
        } label: {
            VStack(spacing: 4) {
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.fault.opacity(0.28), Theme.magenta.opacity(0.18)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    Circle()
                        .strokeBorder(LinearGradient(colors: [Theme.fault, Theme.magenta.opacity(0.7)],
                                                     startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2)
                    DPFLampIcon(size: 26)
                        .foregroundStyle(Theme.fault)
                }
                .frame(width: 44, height: 44)
                Text("DPF")
                    .font(Theme.rounded(10, weight: .bold))
                    .foregroundStyle(Theme.fault)
            }
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel("Rußfilter öffnen")
    }
}

// MARK: - Löschen

enum ClearTarget: Equatable {
    case ecu(UInt8, String)
    case all
    case obd

    var description: String {
        switch self {
        case .ecu(_, let name): return "Fehlerspeicher von \(name)"
        case .all: return "Fehler aller Steuergeräte (OBD-II separat)"
        case .obd: return "genormte OBD-II-Fehler (Motor & Abgas)"
        }
    }
}

/// Warnung vor dem Löschen: Löschen ersetzt keine Reparatur.
struct ClearWarningPopup: View {
    var target: ClearTarget
    var includesSevere: Bool
    var onConfirm: () -> Void
    var onCancel: () -> Void

    @State private var appeared = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(spacing: 16) {
                ZStack {
                    Glow(color: Theme.fault, opacity: 0.45)
                        .frame(width: 110, height: 110)
                        .scaleEffect(appeared ? 1.08 : 0.92)
                    Circle()
                        .fill(Theme.fault.opacity(0.16))
                        .frame(width: 84, height: 84)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 38, weight: .bold))
                        .foregroundStyle(LinearGradient(colors: [Theme.fault, Theme.severe], startPoint: .top, endPoint: .bottom))
                        .rotationEffect(.degrees(appeared ? 5 : -5))
                }
                .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: appeared)
                .frame(height: 90)

                VStack(spacing: 8) {
                    Text("Moment mal!")
                        .font(Theme.display(24))
                    Text("Löschen ersetzt keine Reparatur.")
                        .font(Theme.rounded(18, weight: .bold))
                        .foregroundStyle(Theme.fault)
                        .multilineTextAlignment(.center)
                    Text("Ein gelöschter Fehler ist nur aus dem Speicher verschwunden – die Ursache bleibt. Nur eine Reparatur löst den Fehler wirklich. Solange das Problem besteht, kommt er wieder.")
                        .font(Theme.rounded(14, weight: .regular))
                        .foregroundStyle(.white.opacity(0.75))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Label("Gelöscht wird: \(target.description)", systemImage: "eraser")
                    if includesSevere {
                        Label("Darunter sind schwerwiegende Fehler (z. B. Bremse, Airbag, Lenkung). Bitte unbedingt prüfen lassen.",
                              systemImage: "exclamationmark.octagon.fill")
                            .foregroundStyle(Theme.severe)
                    }
                    if target == .obd {
                        Label("Setzt auch die Abgas-Bereitschaftstests zurück – vor der AU/HU erst ein Stück fahren.",
                              systemImage: "engine.combustion")
                    }
                    Label("Tipp: Vorher den Bericht teilen, dann sind die Codes gesichert.", systemImage: "square.and.arrow.up")
                }
                .font(Theme.rounded(13, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.06)))

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Verstanden, trotzdem löschen")
                            .font(Theme.rounded(16, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 15)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(includesSevere ? Theme.severe : Theme.fault)
                            )
                    }
                    Button(action: onCancel) {
                        Text("Lieber nicht")
                            .font(Theme.rounded(16, weight: .bold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                    }
                }
                .buttonStyle(PressableStyle())
            }
            .padding(22)
            .frosted(cornerRadius: 32)
            .padding(.horizontal, 20)
            .scaleEffect(appeared ? 1 : 0.9)
            .onAppear {
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7)) { appeared = true }
            }
        }
        .foregroundStyle(.white)
    }
}

// MARK: - Web

struct WebLink: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

/// In-App-Browser (Safari) für die Websuche zum Fehlercode.
#if os(iOS)
struct WebSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let controller = SFSafariViewController(url: url)
        controller.preferredControlTintColor = UIColor(Theme.accent)
        controller.preferredBarTintColor = UIColor(Theme.background)
        controller.dismissButtonStyle = .close
        return controller
    }

    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
#else
struct WebSheet: View {
    let url: URL
    var body: some View { Link(url.absoluteString, destination: url).padding() }
}
#endif
