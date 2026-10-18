import Foundation

/// Verbindung zum Adapter: Bluetooth in der App, ein Simulator in den Tests.
protocol ELMTransport: AnyObject {
    var isReady: Bool { get }
    var onReceive: ((String) -> Void)? { get set }
    var onReady: (() -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    func send(_ line: String)
}

/// Spricht ELM327-Befehle mit dem Adapter und UDS mit den BMW-Steuergeräten (D-CAN, 500 kBit/s).
@MainActor
final class ELMSession: ObservableObject {
    struct LogEntry: Identifiable {
        enum Kind { case sent, received, info, error }
        let id = UUID()
        let date = Date()
        let kind: Kind
        let text: String
    }

    enum SessionError: LocalizedError {
        case notConnected
        case notInitialized
        case timeout
        case adapter(String)
        case noResponse
        case negative(service: UInt8, code: UInt8)
        case invalidHex
        case unexpected(String)

        var errorDescription: String? {
            switch self {
            case .notConnected: return "Adapter nicht verbunden"
            case .notInitialized: return "Adapter nicht initialisiert"
            case .timeout: return "Zeitüberschreitung"
            case .adapter(let text): return "Adapter meldet: \(text)"
            case .noResponse: return "Keine Antwort vom Steuergerät"
            case .negative(let service, let code):
                return String(format: "Negative Antwort auf %02X: %02X (%@)", service, code, Self.nrcName(code))
            case .invalidHex: return "Ungültige Hex-Eingabe"
            case .unexpected(let text): return "Unerwartete Antwort: \(text)"
            }
        }

        static func nrcName(_ code: UInt8) -> String {
            switch code {
            case 0x11: return "Dienst nicht unterstützt"
            case 0x12: return "Unterfunktion nicht unterstützt"
            case 0x13: return "Falsche Länge"
            case 0x22: return "Bedingungen nicht erfüllt"
            case 0x31: return "Wert außerhalb des Bereichs / DID unbekannt"
            case 0x33: return "Security Access nötig"
            case 0x78: return "Antwort ausstehend"
            case 0x7E: return "Unterfunktion in dieser Sitzung nicht erlaubt"
            case 0x7F: return "Dienst in dieser Sitzung nicht erlaubt"
            default: return "unbekannt"
            }
        }
    }

    @Published private(set) var log: [LogEntry] = []
    @Published private(set) var isInitialized = false
    @Published private(set) var adapterInfo: String?

    let transport: ELMTransport

    private var buffer = ""
    private var pending: CheckedContinuation<String, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var lastCommand: Task<[String], Error>?
    private var currentECU: UInt8?
    /// Tester-Header und Flow-Control für die BMW-Adressierung sind gesetzt (gilt bis OBD-Modus oder Neustart).
    private var baseAddressed = false
    private var activeSessions: Set<UInt8> = []
    private var keepAlive: Task<Void, Never>?

    convenience init(ble: BLEManager) {
        self.init(transport: ble)
    }

    init(transport: ELMTransport) {
        self.transport = transport
        transport.onReceive = { [weak self] text in self?.receive(text) }
        transport.onReady = { [weak self] in
            Task { await self?.initialize() }
        }
        transport.onDisconnect = { [weak self] in self?.handleDisconnect() }
    }

    // MARK: - Adapter

    func initialize() async {
        isInitialized = false
        currentECU = nil
        baseAddressed = false
        activeSessions = []
        do {
            let reset = try await command("ATZ", timeout: 5)
            adapterInfo = reset.first { $0.uppercased().contains("ELM") || $0.lowercased().contains("vlinker") } ?? reset.last
            // Echo aus, Zeilenumbrüche aus, Leerzeichen aus, CAN-Header an, lange Nachrichten, ISO 15765-4 CAN 11 Bit 500 kBit/s
            for cmd in ["ATE0", "ATL0", "ATS0", "ATH1", "ATAL", "ATSP6"] {
                try await expectOK(cmd)
            }
            isInitialized = true
            info("Adapter bereit (D-CAN, 500 kBit/s)")
        } catch {
            self.error("Initialisierung fehlgeschlagen: \(error.localizedDescription)")
        }
    }

    /// Schickt einen rohen Befehl und liefert die Antwortzeilen bis zum ">"-Prompt.
    /// Befehle laufen strikt nacheinander.
    @discardableResult
    func command(_ cmd: String, timeout: Double = 3, quiet: Bool = false) async throws -> [String] {
        let previous = lastCommand
        let task = Task { () async throws -> [String] in
            _ = try? await previous?.value
            return try await self.transmit(cmd, timeout: timeout, quiet: quiet)
        }
        lastCommand = task
        return try await task.value
    }

    private func transmit(_ cmd: String, timeout: Double, quiet: Bool) async throws -> [String] {
        guard transport.isReady else { throw SessionError.notConnected }
        buffer = ""
        if !quiet { append(.sent, cmd) }

        let raw: String = try await withCheckedThrowingContinuation { continuation in
            pending = continuation
            transport.send(cmd)
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self?.finish(.failure(SessionError.timeout))
            }
        }

        let lines = raw
            .components(separatedBy: CharacterSet(charactersIn: "\r\n"))
            .map { $0.replacingOccurrences(of: "SEARCHING...", with: "").trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if !quiet { append(.received, lines.isEmpty ? "(leer)" : lines.joined(separator: "  |  ")) }

        let adapterErrors = ["?", "UNABLE TO CONNECT", "CAN ERROR", "BUS INIT", "BUS ERROR", "BUFFER FULL", "STOPPED", "ERR"]
        if let bad = lines.first(where: { line in adapterErrors.contains { line == $0 || ($0.count > 1 && line.hasPrefix($0)) } }) {
            throw SessionError.adapter(bad)
        }
        return lines
    }

    private func receive(_ text: String) {
        buffer += text
        guard let prompt = buffer.firstIndex(of: ">") else { return }
        let response = String(buffer[..<prompt])
        buffer = String(buffer[buffer.index(after: prompt)...])
        finish(.success(response))
    }

    private func finish(_ result: Result<String, Error>) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation = pending else { return }
        pending = nil
        continuation.resume(with: result)
    }

    private func expectOK(_ cmd: String) async throws {
        let lines = try await command(cmd)
        guard lines.contains(where: { $0.contains("OK") }) else {
            throw SessionError.unexpected("\(cmd) → \(lines.joined(separator: " "))")
        }
    }

    private func handleDisconnect() {
        finish(.failure(SessionError.notConnected))
        keepAlive?.cancel()
        keepAlive = nil
        isInitialized = false
        currentECU = nil
        baseAddressed = false
        activeSessions = []
        info("Verbindung getrennt")
    }

    // MARK: - UDS

    /// Stellt Header und Filter für die BMW-Adressierung ein: Tester 0x6F1 → Steuergerät, Antwort von 0x600 + Adresse.
    private func select(ecu: UInt8, quiet: Bool) async throws {
        guard currentECU != ecu else { return }
        let a = String(format: "%02X", ecu)
        // Reihenfolge ist wichtig: ATFCSM1 akzeptiert der ELM327 erst, wenn ATFCSH und ATFCSD gesetzt sind.
        var commands = baseAddressed ? [] : ["ATSH6F1", "ATFCSH6F1"]
        commands += ["ATCEA\(a)", "ATCRA6\(a)", "ATFCSD\(a)300000"]
        if !baseAddressed { commands.append("ATFCSM1") }
        for cmd in commands {
            let lines = try await command(cmd, quiet: quiet)
            guard lines.contains(where: { $0.contains("OK") }) else {
                throw SessionError.unexpected("\(cmd) → \(lines.joined(separator: " "))")
            }
        }
        baseAddressed = true
        currentECU = ecu
    }

    // MARK: - Fehlerspeicher (nur lesen)

    struct StoredDTC {
        let bytes: [UInt8]
        let status: UInt8
    }

    /// Wie lange der Adapter auf eine Antwort wartet, in 4-ms-Schritten (Standard 0x32 = 200 ms).
    func setResponseTimeout(_ value: UInt8) async throws {
        try await expectOK(String(format: "ATST%02X", value))
    }

    /// Liest den Fehlerspeicher eines Steuergeräts: ReadDTCInformation (19 02), Maske aktiv + sporadisch + bestätigt.
    func readDTCs(ecu: UInt8, quiet: Bool = false) async throws -> [StoredDTC] {
        let response = try await uds([0x19, 0x02, 0x0D], ecu: ecu, timeout: 4, quiet: quiet)
        guard response.count >= 3 else { return [] }
        let records = Array(response.dropFirst(3))
        return stride(from: 0, to: records.count - 3, by: 4).map { i in
            StoredDTC(bytes: Array(records[i..<i + 3]), status: records[i + 3])
        }
    }

    /// Liest die genormten OBD-II-Fehler (Modus 03 gespeichert, 07 sporadisch) über die Funktionsadresse 7DF.
    func readOBDCodes() async throws -> (stored: [UInt16], pending: [UInt16]) {
        guard isInitialized else { throw SessionError.notInitialized }
        // BMW-Adressierung ausschalten, Standard-OBD-Header setzen
        for cmd in ["ATCEA", "ATCRA", "ATFCSM0", "ATSH7DF"] { try await expectOK(cmd) }
        currentECU = nil
        baseAddressed = false

        func read(_ mode: String, reply: UInt8) async throws -> [UInt16] {
            let lines = try await command(mode, timeout: 4)
            if lines.contains(where: { $0.contains("NO DATA") }) { return [] }
            var codes: [UInt16] = []
            for message in ISOTP.messages(from: lines) where message.first == reply && message.count >= 2 {
                // CAN: 43 <Anzahl> <Code-Hi> <Code-Lo> …
                let payload = Array(message.dropFirst(2))
                for i in stride(from: 0, to: payload.count - 1, by: 2) {
                    let code = UInt16(payload[i]) << 8 | UInt16(payload[i + 1])
                    if code != 0 { codes.append(code) }
                }
            }
            return codes
        }
        return (try await read("03", reply: 0x43), try await read("07", reply: 0x47))
    }

    /// Sendet eine UDS-Anfrage und liefert die positive Antwort (ab dem Service-Byte).
    @discardableResult
    func uds(_ request: [UInt8], ecu: UInt8, timeout: Double = 3, quiet: Bool = false) async throws -> [UInt8] {
        guard isInitialized else { throw SessionError.notInitialized }
        guard let service = request.first else { throw SessionError.invalidHex }
        try await select(ecu: ecu, quiet: quiet)

        let lines = try await command(Hex.string(request, separator: ""), timeout: timeout, quiet: quiet)
        let suppressPositive = request.count >= 2 && [0x10, 0x11, 0x3E, 0x31, 0x85].contains(service) && request[1] & 0x80 != 0
        if lines.contains(where: { $0.contains("NO DATA") }) {
            if suppressPositive { return [] }
            throw SessionError.noResponse
        }

        // "Antwort ausstehend" (7F xx 78) überspringen, falls danach noch etwas kam.
        let messages = ISOTP.messages(from: lines).filter { !($0.count >= 3 && $0[0] == 0x7F && $0[2] == 0x78) }
        guard let response = messages.last ?? ISOTP.messages(from: lines).last else {
            throw SessionError.unexpected(lines.joined(separator: " "))
        }
        if response[0] == 0x7F, response.count >= 3 {
            throw SessionError.negative(service: response[1], code: response[2])
        }
        guard response[0] == service &+ 0x40 else {
            throw SessionError.unexpected(Hex.string(response))
        }
        return response
    }

    // MARK: - Lichter

    /// Schaltet eine Leuchte per InputOutputControlByIdentifier (0x2F).
    /// An: 2F DID 03 <Daten> (shortTermAdjustment), Aus: 2F DID 00 (returnControlToECU).
    func setLight(_ preset: LightPreset, on: Bool) async throws {
        guard let ecu = preset.ecuByte, let did = preset.didBytes, let data = preset.controlBytes else {
            throw SessionError.invalidHex
        }
        if on {
            try await ensureExtendedSession(ecu)
            try await uds([0x2F] + did + [0x03] + data, ecu: ecu)
        } else {
            try await uds([0x2F] + did + [0x00], ecu: ecu)
        }
    }

    /// Zurück in die Default-Sitzung: Die Steuergeräte geben dann alle Ausgänge wieder selbst frei.
    func endAllSessions() async {
        keepAlive?.cancel()
        keepAlive = nil
        for ecu in activeSessions {
            _ = try? await uds([0x10, 0x01], ecu: ecu)
        }
        activeSessions = []
    }

    private func ensureExtendedSession(_ ecu: UInt8) async throws {
        guard !activeSessions.contains(ecu) else { return }
        try await uds([0x10, 0x03], ecu: ecu)
        activeSessions.insert(ecu)
        startKeepAlive()
    }

    /// Tester Present alle 2 s, sonst fällt das Steuergerät nach ca. 5 s in die Default-Sitzung zurück.
    private func startKeepAlive() {
        guard keepAlive == nil else { return }
        keepAlive = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard let self, !Task.isCancelled else { return }
                for ecu in self.activeSessions {
                    _ = try? await self.uds([0x3E, 0x80], ecu: ecu, timeout: 1, quiet: true)
                }
            }
        }
    }

    // MARK: - Log

    func info(_ text: String) { append(.info, text) }
    func error(_ text: String) { append(.error, text) }
    func clearLog() { log = [] }

    var logText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return log.map { entry in
            let prefix: String
            switch entry.kind {
            case .sent: prefix = "→"
            case .received: prefix = "←"
            case .info: prefix = "·"
            case .error: prefix = "!"
            }
            return "\(formatter.string(from: entry.date)) \(prefix) \(entry.text)"
        }.joined(separator: "\n")
    }

    private func append(_ kind: LogEntry.Kind, _ text: String) {
        log.append(LogEntry(kind: kind, text: text))
        if log.count > 1000 { log.removeFirst(log.count - 1000) }
    }
}
