import Foundation

/// Simuliert einen ELM327-kompatiblen Adapter (vLinker) an einem BMW mit D-CAN.
/// Hält sich an die ELM327-Regeln, die für LichtLab wichtig sind – z. B. antwortet
/// ATFCSM1 mit "?", solange ATFCSH und ATFCSD nicht gesetzt sind.
final class ELMSimulator: ELMTransport {
    var isReady = true
    var onReceive: ((String) -> Void)?
    var onReady: (() -> Void)?
    var onDisconnect: (() -> Void)?

    /// Alle empfangenen Befehle, zum Prüfen in Tests
    private(set) var received: [String] = []

    // Adapter-Zustand
    private var echo = true
    private var header = "7DF"
    private var extendedAddress: UInt8?
    private var flowHeader: String?
    private var flowData: [UInt8]?
    private var flowMode = 0

    // Simulierte Steuergeräte: Adresse → Antwort auf eine UDS-Anfrage (nil = keine Antwort)
    var ecus: [UInt8: ([UInt8]) -> [UInt8]?] = [:]
    var obdStored: [UInt16] = []
    /// Simuliert einen Adapter ohne CAN-Extended-Addressing
    var rejectExtendedAddressing = false

    func send(_ line: String) {
        received.append(line)
        let reply = respond(to: line.trimmingCharacters(in: .whitespaces).uppercased())
        let text = (echo ? line + "\r" : "") + reply + "\r\r>"
        // Wie über BLE: in kleinen Stücken und leicht verzögert
        let chunks = stride(from: 0, to: text.count, by: 20).map { start -> String in
            let from = text.index(text.startIndex, offsetBy: start)
            let to = text.index(from, offsetBy: min(20, text.count - start))
            return String(text[from..<to])
        }
        for (i, chunk) in chunks.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.002 * Double(i + 1)) { [weak self] in
                self?.onReceive?(chunk)
            }
        }
    }

    private func respond(to cmd: String) -> String {
        if cmd.hasPrefix("AT") { return at(String(cmd.dropFirst(2))) }
        guard let request = Hex.bytes(cmd), !request.isEmpty else { return "?" }
        return data(request)
    }

    private func at(_ c: String) -> String {
        switch c {
        case "Z": echo = true; extendedAddress = nil; flowHeader = nil; flowData = nil; flowMode = 0; header = "7DF"
            return "\r\rELM327 v2.2"
        case "E0": echo = false; return "OK"
        case "E1": echo = true; return "OK"
        case "L0", "S0", "H1", "AL", "SP6", "CAF1": return "OK"
        case "CEA": extendedAddress = nil; return "OK"
        case "CRA": return "OK"
        default: break
        }
        if c.hasPrefix("ST"), Hex.bytes(String(c.dropFirst(2)))?.count == 1 { return "OK" }
        if c.hasPrefix("SH"), c.count == 5 { header = String(c.dropFirst(2)); return "OK" }
        if c.hasPrefix("CEA"), let b = Hex.bytes(String(c.dropFirst(3))), b.count == 1 {
            if rejectExtendedAddressing { return "?" }
            extendedAddress = b[0]
            return "OK"
        }
        if c.hasPrefix("CRA"), c.count == 6 { return "OK" }
        if c.hasPrefix("FCSH"), c.count == 7 { flowHeader = String(c.dropFirst(4)); return "OK" }
        if c.hasPrefix("FCSD"), let b = Hex.bytes(String(c.dropFirst(4))), (1...5).contains(b.count) { flowData = b; return "OK" }
        if c == "FCSM0" { flowMode = 0; return "OK" }
        if c == "FCSM1" {
            // ELM327-Regel: eigene Flow-Control erst, wenn Header und Daten definiert sind
            guard flowHeader != nil, flowData != nil else { return "?" }
            flowMode = 1
            return "OK"
        }
        return "?"
    }

    private func data(_ request: [UInt8]) -> String {
        // Standard-OBD über die Funktionsadresse
        if header == "7DF", extendedAddress == nil {
            guard request == [0x03] || request == [0x07] else { return "NO DATA" }
            let codes = request == [0x03] ? obdStored : []
            var payload: [UInt8] = [request[0] + 0x40, UInt8(codes.count)]
            for code in codes { payload += [UInt8(code >> 8), UInt8(code & 0xFF)] }
            return "7E8" + Hex.string([UInt8(payload.count)] + payload, separator: "")
        }
        // BMW: Tester 6F1, erweiterte Adresse = Steuergerät
        guard header == "6F1", let address = extendedAddress, let ecu = ecus[address],
              let response = ecu(request) else { return "NO DATA" }
        let head = String(format: "6%02X", address)
        if response.count <= 6 {
            return head + Hex.string([0xF1, UInt8(response.count)] + response, separator: "")
        }
        // Mehrteilige Antwort: Folgeframes kommen nur, wenn die Flow-Control richtig adressiert ist
        var lines = [head + Hex.string([0xF1, 0x10 | UInt8(response.count >> 8), UInt8(response.count & 0xFF)] + response.prefix(5), separator: "")]
        guard flowMode == 1, flowHeader == "6F1", flowData?.first == address else { return lines[0] }
        var rest = Array(response.dropFirst(5))
        var index: UInt8 = 1
        while !rest.isEmpty {
            let chunk = Array(rest.prefix(6))
            rest.removeFirst(chunk.count)
            lines.append(head + Hex.string([0xF1, 0x20 | (index & 0x0F)] + chunk, separator: ""))
            index += 1
        }
        return lines.joined(separator: "\r")
    }
}
