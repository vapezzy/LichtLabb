import Foundation

/// Ein Eintrag im Fehlerspeicher.
struct FaultCode: Identifiable, Hashable {
    let id = UUID()
    /// BMW-Code als 6-stelliger Hex-Wert (z. B. "801C20") oder OBD-Code (z. B. "P0300")
    let code: String
    let status: UInt8
    var isOBD = false

    var isActive: Bool { status & 0x01 != 0 }
    var isPending: Bool { status & 0x04 != 0 }
    var isConfirmed: Bool { status & 0x08 != 0 }
    var warningLamp: Bool { status & 0x80 != 0 }

    var statusText: String {
        var parts: [String] = []
        if isActive { parts.append("aktiv") }
        if isConfirmed { parts.append("gespeichert") }
        if isPending { parts.append("sporadisch") }
        if warningLamp { parts.append("Warnlampe") }
        return parts.isEmpty ? "nicht aktiv" : parts.joined(separator: ", ")
    }

    /// Genormter OBD-II-Code aus zwei Bytes, z. B. 0x0300 → "P0300".
    static func obdString(_ raw: UInt16) -> String {
        let letters = ["P", "C", "B", "U"]
        let letter = letters[Int(raw >> 14)]
        return letter + String(format: "%01X%03X", (raw >> 12) & 0x3, raw & 0x0FFF)
    }
}

struct ECUResult: Identifiable {
    let address: UInt8
    let name: String
    var faults: [FaultCode]
    var error: String?

    var id: UInt8 { address }
    var hexAddress: String { String(format: "0x%02X", address) }
}

/// Liest die Fehlerspeicher aller Steuergeräte aus und löscht sie auf Wunsch.
@MainActor
final class FaultScanner: ObservableObject {
    enum Mode: String, CaseIterable, Identifiable {
        case quick = "Schnell", full = "Vollständig"
        var id: String { rawValue }
        var subtitle: String {
            switch self {
            case .quick: return "Bekannte F-Serien-Steuergeräte · ca. 10 s"
            case .full: return "Alle Adressen 01–7F · ca. 1 min"
            }
        }
    }

    enum Phase: Equatable {
        case idle
        case scanning
        case finished(Date)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var currentStep = ""
    @Published private(set) var results: [ECUResult] = []
    @Published private(set) var obdCodes: [FaultCode] = []
    @Published private(set) var vin: String?
    @Published private(set) var isDemo = false
    /// Grund, falls der Scan abgebrochen werden musste
    @Published private(set) var abortReason: String?
    @Published var mode: Mode = .quick
    /// Steuergerät, das gerade gelöscht wird (0x00 = OBD-II, nil = keins)
    @Published private(set) var clearingAddress: UInt8?
    @Published private(set) var isClearingAll = false
    /// Ergebnis des letzten Löschvorgangs für die Anzeige
    @Published var clearMessage: String?

    static let obdAddress: UInt8 = 0x00

    let session: ELMSession
    private var task: Task<Void, Never>?

    init(session: ELMSession) {
        self.session = session
    }

    var totalFaults: Int { results.reduce(0) { $0 + $1.faults.count } + obdCodes.count }
    var activeFaults: Int { results.reduce(0) { $0 + $1.faults.filter(\.isActive).count } }

    // Typische Adressen der F-Serie. Die Namen sind Richtwerte und können je nach Ausstattung abweichen.
    nonisolated static let knownECUs: [UInt8: String] = [
        0x01: "ACSM · Airbag",
        0x10: "ZGM · Gateway",
        0x12: "DME/DDE · Motor",
        0x18: "EGS · Getriebe",
        0x1C: "ICM · Fahrdynamik",
        0x29: "DSC · Bremsregelung",
        0x30: "EPS · Lenkung",
        0x40: "FEM/BDC · Karosserie",
        0x56: "FZD · Dachfunktionen",
        0x5D: "KAFAS · Kamera",
        0x60: "KOMBI · Instrumente",
        0x63: "HU · Headunit",
        0x64: "PDC · Parkhilfe",
        0x67: "ZBE · Controller",
        0x6D: "SPEG · Sitze",
        0x72: "FRM/REM · Licht",
        0x78: "IHKA · Klima",
    ]

    nonisolated static func name(for address: UInt8) -> String {
        knownECUs[address] ?? String(format: "Steuergerät %02X", address)
    }

    // MARK: - Scan

    func start() {
        guard phase != .scanning, session.isInitialized else { return }
        task = Task { [weak self] in await self?.scan() }
    }

    func cancel() {
        task?.cancel()
    }

    var isBusy: Bool { phase == .scanning || clearingAddress != nil || isClearingAll }

    // MARK: - Löschen

    /// Löscht den Fehlerspeicher eines Steuergeräts und liest ihn danach neu aus.
    func clear(_ address: UInt8) async {
        guard !isBusy else { return }
        clearingAddress = address
        clearMessage = await clearOne(address)
        clearingAddress = nil
    }

    /// Löscht alle Steuergeräte mit Einträgen (ohne OBD-II) und liest jedes danach neu aus.
    func clearAll() async {
        guard !isBusy else { return }
        isClearingAll = true
        var cleared = 0, remaining = 0, failed = 0
        for result in results where !result.faults.isEmpty {
            clearingAddress = result.address
            let message = await clearOne(result.address)
            let after = results.first { $0.address == result.address }
            if after?.error != nil || message.hasPrefix("Fehler") { failed += 1 }
            else if after?.faults.isEmpty == true { cleared += 1 }
            else { remaining += 1 }
        }
        clearingAddress = nil
        isClearingAll = false
        var parts = ["\(cleared) Steuergerät\(cleared == 1 ? "" : "e") gelöscht"]
        if remaining > 0 { parts.append("bei \(remaining) sind Fehler sofort wiedergekommen (Ursache besteht noch)") }
        if failed > 0 { parts.append("\(failed) konnte\(failed == 1 ? "" : "n") nicht gelöscht werden") }
        clearMessage = parts.joined(separator: ", ") + "."
    }

    /// Löscht die genormten OBD-II-Fehler und liest sie neu aus.
    func clearOBD() async {
        guard !isBusy else { return }
        clearingAddress = Self.obdAddress
        defer { clearingAddress = nil }
        if isDemo {
            try? await Task.sleep(nanoseconds: 600_000_000)
            obdCodes = []
            clearMessage = "OBD-II-Fehler gelöscht (Beispieldaten)."
            return
        }
        do {
            try await session.clearOBDCodes()
            try? await Task.sleep(nanoseconds: 500_000_000)
            let codes = try await session.readOBDCodes()
            obdCodes = Self.obdFaults(codes)
            clearMessage = obdCodes.isEmpty
                ? "OBD-II-Fehler gelöscht."
                : "OBD-II gelöscht, aber \(obdCodes.count) Fehler sofort wiedergekommen (Ursache besteht noch)."
        } catch {
            clearMessage = "Fehler beim Löschen von OBD-II: \(error.localizedDescription)"
        }
    }

    private func clearOne(_ address: UInt8) async -> String {
        guard let index = results.firstIndex(where: { $0.address == address }) else { return "" }
        let name = results[index].name
        if isDemo {
            try? await Task.sleep(nanoseconds: 600_000_000)
            results[index].faults = []
            return "\(name): gelöscht (Beispieldaten)."
        }
        var clearError: Error?
        do {
            try await session.clearDTCs(ecu: address)
        } catch {
            clearError = error
        }
        // Immer neu auslesen – das zeigt, was wirklich noch im Speicher steht.
        try? await Task.sleep(nanoseconds: 400_000_000)
        do {
            let dtcs = try await session.readDTCs(ecu: address)
            results[index].faults = dtcs.map { FaultCode(code: Hex.string($0.bytes, separator: ""), status: $0.status) }
            results[index].error = nil
        } catch {
            results[index].error = error.localizedDescription
        }
        if let clearError, !results[index].faults.isEmpty {
            return "Fehler beim Löschen (\(name)): \(clearError.localizedDescription)"
        }
        return results[index].faults.isEmpty
            ? "\(name): Fehlerspeicher gelöscht."
            : "\(name): \(results[index].faults.count) Fehler sofort wiedergekommen – die Ursache besteht noch."
    }

    static func obdFaults(_ codes: (stored: [UInt16], pending: [UInt16])) -> [FaultCode] {
        codes.stored.map { FaultCode(code: FaultCode.obdString($0), status: 0x08, isOBD: true) }
            + codes.pending.map { FaultCode(code: FaultCode.obdString($0), status: 0x04, isOBD: true) }
    }

    private func scan() async {
        isDemo = false
        abortReason = nil
        clearMessage = nil
        results = []
        obdCodes = []
        vin = nil
        progress = 0
        phase = .scanning

        let addresses: [UInt8] = mode == .quick
            ? Self.knownECUs.keys.sorted()
            : Array(0x01...0x7F)
        let steps = Double(addresses.count + 2)

        // Kurze Wartezeit pro Adresse, damit fehlende Steuergeräte den Scan nicht ausbremsen (100 ms).
        try? await session.setResponseTimeout(0x19)

        currentStep = "Fahrgestellnummer"
        if let response = try? await session.uds([0x22, 0xF1, 0x90], ecu: 0x12, quiet: true), response.count > 3 {
            let text = String(decoding: response.dropFirst(3).filter { (0x20...0x7E).contains($0) }, as: UTF8.self)
            if text.count >= 7 { vin = text }
        }
        progress = 1 / steps

        for (index, address) in addresses.enumerated() {
            if Task.isCancelled { break }
            currentStep = Self.name(for: address)
            do {
                let dtcs = try await session.readDTCs(ecu: address, quiet: true)
                let faults = dtcs.map { FaultCode(code: Hex.string($0.bytes, separator: ""), status: $0.status) }
                results.append(ECUResult(address: address, name: Self.name(for: address), faults: faults))
            } catch ELMSession.SessionError.noResponse {
                // Kein Steuergerät unter dieser Adresse
            } catch ELMSession.SessionError.timeout {
                // ebenso
            } catch ELMSession.SessionError.adapter(let message) {
                // Der Adapter selbst hat etwas abgelehnt – dann scheitern alle weiteren Adressen genauso.
                abortReason = "Der Adapter hat einen Befehl abgelehnt („\(message)“). Bitte das Protokoll aus Einstellungen → Diagnose-Konsole teilen."
                break
            } catch ELMSession.SessionError.unexpected(let message) where message.hasPrefix("AT") {
                abortReason = "Adapter-Einstellung fehlgeschlagen: \(message)"
                break
            } catch {
                results.append(ECUResult(address: address, name: Self.name(for: address), faults: [], error: error.localizedDescription))
            }
            progress = Double(index + 2) / steps
        }

        if !Task.isCancelled {
            currentStep = "OBD-II Motor & Abgas"
            if let codes = try? await session.readOBDCodes() {
                obdCodes = Self.obdFaults(codes)
            }
        }
        try? await session.setResponseTimeout(0x32)

        progress = 1
        currentStep = ""
        phase = .finished(Date())
        task = nil
    }

    /// Spielt einen Scan mit Beispieldaten ab (Mechaniker-Animation, dann Ergebnis) – ganz ohne Auto.
    func runDemoScan(seconds: Double = 4.5) {
        guard !isBusy else { return }
        task = Task { [weak self] in
            guard let self else { return }
            self.results = []
            self.obdCodes = []
            self.clearMessage = nil
            self.abortReason = nil
            self.progress = 0
            self.phase = .scanning
            let steps = Self.knownECUs.keys.sorted()
            for (index, address) in steps.enumerated() {
                if Task.isCancelled { break }
                self.currentStep = Self.name(for: address)
                try? await Task.sleep(nanoseconds: UInt64(seconds / Double(steps.count) * 1_000_000_000))
                self.progress = Double(index + 1) / Double(steps.count)
            }
            self.currentStep = ""
            if Task.isCancelled {
                self.phase = .idle
            } else {
                self.loadDemo()
            }
            self.task = nil
        }
    }

    /// Setzt alles auf den Startzustand zurück (neue Kontrolle).
    func reset() {
        guard !isBusy else { return }
        results = []
        obdCodes = []
        vin = nil
        isDemo = false
        abortReason = nil
        clearMessage = nil
        progress = 0
        phase = .idle
    }

    /// Beispieldaten, um die Ansicht ohne Auto auszuprobieren.
    func loadDemo() {
        isDemo = true
        clearMessage = nil
        abortReason = nil
        vin = "WBA4A31070GXXXXXX"
        results = [
            ECUResult(address: 0x12, name: Self.name(for: 0x12), faults: [
                FaultCode(code: "120308", status: 0x08),
                FaultCode(code: "1B2A00", status: 0x09),
            ]),
            ECUResult(address: 0x40, name: Self.name(for: 0x40), faults: [
                FaultCode(code: "801C20", status: 0x04),
            ]),
            ECUResult(address: 0x60, name: Self.name(for: 0x60), faults: []),
            ECUResult(address: 0x72, name: Self.name(for: 0x72), faults: [
                FaultCode(code: "A6A610", status: 0x08),
            ]),
            ECUResult(address: 0x29, name: Self.name(for: 0x29), faults: [
                FaultCode(code: "480A1C", status: 0x89),
            ]),
        ]
        obdCodes = [FaultCode(code: "P2463", status: 0x08, isOBD: true),
                    FaultCode(code: "P0420", status: 0x08, isOBD: true)]
        progress = 1
        phase = .finished(Date())
    }

    // MARK: - Bericht

    var reportText: String {
        var lines = ["RideReader – Fehlerspeicher"]
        if isDemo { lines.append("(Beispieldaten)") }
        if case .finished(let date) = phase {
            lines.append(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
        }
        if let vin { lines.append("FIN: \(vin)") }
        if let abortReason { lines.append("Scan abgebrochen: \(abortReason)") }
        lines.append("")
        for result in results {
            lines.append("\(result.name) (\(result.hexAddress))")
            if let error = result.error {
                lines.append("  Fehler beim Lesen: \(error)")
            } else if result.faults.isEmpty {
                lines.append("  keine Einträge")
            } else {
                for fault in result.faults {
                    let info = FaultCatalog.info(for: fault, ecu: result.address)
                    lines.append("  \(fault.code)  [\(fault.statusText)]  \(info.severity.label): \(info.area)")
                }
            }
        }
        lines.append("")
        lines.append("OBD-II (Motor & Abgas)")
        if obdCodes.isEmpty {
            lines.append("  keine Einträge")
        } else {
            for fault in obdCodes {
                let info = FaultCatalog.info(for: fault, ecu: nil)
                lines.append("  \(fault.code)  [\(fault.statusText)]  \(info.title)")
            }
        }
        return lines.joined(separator: "\n")
    }
}
