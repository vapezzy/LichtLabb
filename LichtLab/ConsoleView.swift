import SwiftUI

/// Rohe Befehle senden: AT-Befehle an den Adapter oder UDS-Hex an ein Steuergerät.
struct ConsoleView: View {
    @EnvironmentObject private var session: ELMSession
    @State private var ecu = "72"
    @State private var input = ""

    private let quickCommands: [(title: String, hex: String)] = [
        ("Fahrgestellnr.", "22 F1 90"),
        ("Extended", "10 03"),
        ("Default", "10 01"),
        ("Fehlerspeicher", "19 02 0C"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            logView
            Divider()
            controls
        }
        .navigationTitle("Konsole")
        .toolbar {
            ToolbarItemGroup {
                ShareLink(item: session.logText) {
                    Label("Log teilen", systemImage: "square.and.arrow.up")
                }
                Button {
                    session.clearLog()
                } label: {
                    Label("Leeren", systemImage: "trash")
                }
            }
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(session.log) { entry in
                        Text(prefix(entry.kind) + entry.text)
                            .font(.caption.monospaced())
                            .foregroundStyle(color(entry.kind))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                    }
                }
                .padding()
            }
            .onReceive(session.$log) { log in
                if let last = log.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var controls: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    Button("Init") { Task { await session.initialize() } }
                    ForEach(quickCommands, id: \.hex) { quick in
                        Button(quick.title) { send(quick.hex) }
                    }
                }
                .buttonStyle(.bordered)
                .font(.footnote)
            }
            HStack {
                TextField("SG", text: $ecu)
                    .hexInput()
                    .frame(width: 44)
                TextField("UDS-Hex oder AT-Befehl", text: $input)
                    .hexInput()
                    .onSubmit { send(input) }
                Button("Senden") { send(input) }
                    .buttonStyle(.borderedProminent)
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)
        }
        .padding()
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        Task {
            do {
                if trimmed.uppercased().hasPrefix("AT") {
                    try await session.command(trimmed.uppercased())
                } else {
                    guard let request = Hex.bytes(trimmed), !request.isEmpty,
                          let ecuBytes = Hex.bytes(ecu), ecuBytes.count == 1
                    else { throw ELMSession.SessionError.invalidHex }
                    let response = try await session.uds(request, ecu: ecuBytes[0])
                    session.info("✅ \(Hex.string(response))\(ascii(response))")
                }
                input = ""
            } catch {
                session.error(error.localizedDescription)
            }
        }
    }

    /// Lesbaren Text zeigen, z. B. bei der Fahrgestellnummer (62 F1 90 …).
    private func ascii(_ response: [UInt8]) -> String {
        guard response.first == 0x62, response.count > 3 else { return "" }
        let text = String(decoding: response.dropFirst(3).filter { (0x20...0x7E).contains($0) }, as: UTF8.self)
        return text.count >= 3 ? "  „\(text)“" : ""
    }

    private func prefix(_ kind: ELMSession.LogEntry.Kind) -> String {
        switch kind {
        case .sent: return "→ "
        case .received: return "← "
        case .info: return "· "
        case .error: return "! "
        }
    }

    private func color(_ kind: ELMSession.LogEntry.Kind) -> Color {
        switch kind {
        case .sent: return .blue
        case .received: return .primary
        case .info: return .green
        case .error: return .red
        }
    }
}
