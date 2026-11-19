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

    /// Protokoll in eigenem Objekt: neue Zeilen lassen nur die Konsole neu zeichnen, nicht die ganze App.
    final class LogStore: ObservableObject {
        @Published fileprivate(set) var entries: [LogEntry] = []
    }

    let logStore = LogStore()
    var log: [LogEntry] { logStore.entries }
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
    /// Physische Adressierung des Motorsteuergeräts (7E0 → 7E8) für Messwerte aktiv
    private var engineAddressed = false
    /// Zwischenspeicher der unterstützten Messwerte (gilt bis zur nächsten Initialisierung)
    private var pidCache: Set<UInt8>?

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
        engineAddressed = false
        pidCache = nil
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
        isInitialized = false
        currentECU = nil
        baseAddressed = false
        engineAddressed = false
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
        engineAddressed = false
        currentECU = ecu
    }

    // MARK: - Fehlerspeicher lesen

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
        try await useOBDAddressing()

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

    /// BMW-Adressierung ausschalten, Standard-OBD-Header (Funktionsadresse 7DF) setzen.
    private func useOBDAddressing() async throws {
        guard isInitialized else { throw SessionError.notInitialized }
        for cmd in ["ATCEA", "ATCRA", "ATFCSM0", "ATSH7DF"] { try await expectOK(cmd) }
        currentECU = nil
        baseAddressed = false
        engineAddressed = false
    }

    // MARK: - Messwerte (nur lesen)

    /// Liest einen genormten Messwert (OBD-II Modus 01) direkt vom Motorsteuergerät.
    /// Liefert die Datenbytes nach `41 <PID>` oder nil, wenn das Steuergerät den Wert nicht kennt.
    func readPID(_ pid: UInt8, quiet: Bool = true) async throws -> [UInt8]? {
        try await useEngineAddressing(quiet: quiet)
        let lines = try await command(String(format: "01%02X", pid), timeout: 2, quiet: quiet)
        if lines.contains(where: { $0.contains("NO DATA") }) { return nil }
        for message in ISOTP.messages(from: lines) where message.count >= 2 && message[0] == 0x41 && message[1] == pid {
            return Array(message.dropFirst(2))
        }
        return nil
    }

    /// Batteriespannung direkt an der OBD-Buchse (Pin 16), gemessen vom Adapter selbst – braucht kein Steuergerät.
    func readVoltage(quiet: Bool = true) async throws -> Double? {
        let lines = try await command("ATRV", timeout: 2, quiet: quiet)
        for line in lines {
            let digits = line.uppercased().replacingOccurrences(of: "V", with: "").replacingOccurrences(of: ",", with: ".")
            if let value = Double(digits.trimmingCharacters(in: .whitespaces)), value > 3, value < 30 { return value }
        }
        return nil
    }

    /// Welche Messwerte (Modus 01) das Motorsteuergerät kennt – einmal pro Verbindung abgefragt.
    func supportedPIDs() async throws -> Set<UInt8> {
        if let cached = pidCache { return cached }
        var result: Set<UInt8> = []
        var base: UInt8 = 0x00
        while true {
            guard let data = try await readPID(base, quiet: false) else { break }
            let pids = Self.decodeSupport(base: base, data: data)
            result.formUnion(pids)
            // Bit für base+0x20 sagt, ob der nächste Bereich existiert
            guard base < 0xC0, pids.contains(base &+ 0x20) else { break }
            base += 0x20
        }
        pidCache = result
        return result
    }

    /// Unterstützte PIDs aus einer 4-Byte-Bitmap: höchstes Bit = base+1.
    nonisolated static func decodeSupport(base: UInt8, data: [UInt8]) -> Set<UInt8> {
        var result: Set<UInt8> = []
        for (byteIndex, byte) in data.prefix(4).enumerated() {
            for bit in 0..<8 where byte & (0x80 >> bit) != 0 {
                result.insert(base &+ UInt8(byteIndex * 8 + bit + 1))
            }
        }
        return result
    }

    /// Standard-OBD-Header physisch auf das Motorsteuergerät: Anfrage an 7E0, nur Antworten von 7E8.
    private func useEngineAddressing(quiet: Bool) async throws {
        guard isInitialized else { throw SessionError.notInitialized }
        guard !engineAddressed else { return }
        for cmd in ["ATCEA", "ATFCSM0", "ATSH7E0", "ATCRA7E8"] {
            let lines = try await command(cmd, quiet: quiet)
            guard lines.contains(where: { $0.contains("OK") }) else {
                throw SessionError.unexpected("\(cmd) → \(lines.joined(separator: " "))")
            }
        }
        currentECU = nil
        baseAddressed = false
        engineAddressed = true
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

    // MARK: - Fehlerspeicher löschen

    /// Löscht alle Fehler eines Steuergeräts: ClearDiagnosticInformation (14) für alle Gruppen (FF FF FF).
    /// Lehnt das Steuergerät das in der normalen Sitzung ab, wird es einmal in der erweiterten Sitzung versucht.
    func clearDTCs(ecu: UInt8) async throws {
        let request: [UInt8] = [0x14, 0xFF, 0xFF, 0xFF]
        do {
            try await uds(request, ecu: ecu, timeout: 8)
        } catch SessionError.negative(_, let code) where code == 0x7F {
            try await uds([0x10, 0x03], ecu: ecu)
            do {
                try await uds(request, ecu: ecu, timeout: 8)
            } catch {
                _ = try? await uds([0x10, 0x01], ecu: ecu)
                throw error
            }
            _ = try? await uds([0x10, 0x01], ecu: ecu)
        }
    }

    /// Löscht die genormten OBD-II-Fehler (Modus 04). Setzt auch die Bereitschaftstests (Readiness) zurück.
    func clearOBDCodes() async throws {
        try await useOBDAddressing()
        let lines = try await command("04", timeout: 8)
        let replies = ISOTP.messages(from: lines)
        if replies.contains(where: { $0.first == 0x7F }) {
            let code = replies.first { $0.first == 0x7F }.flatMap { $0.count >= 3 ? $0[2] : nil } ?? 0
            throw SessionError.negative(service: 0x04, code: code)
        }
        guard replies.contains(where: { $0.first == 0x44 }) else {
            throw lines.contains(where: { $0.contains("NO DATA") }) ? SessionError.noResponse : SessionError.unexpected(lines.joined(separator: " "))
        }
    }

    // MARK: - Log

    func info(_ text: String) { append(.info, text) }
    func error(_ text: String) { append(.error, text) }
    func clearLog() { logStore.entries = [] }

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
        var entries = logStore.entries
        entries.append(LogEntry(kind: kind, text: text))
        if entries.count > 1000 { entries.removeFirst(entries.count - 1000) }
        logStore.entries = entries
    }
}
