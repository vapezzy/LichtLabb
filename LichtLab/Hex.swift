import Foundation

enum Hex {
    /// "2F 12 34" oder "2f1234" → [0x2F, 0x12, 0x34]; nil bei ungültiger Eingabe.
    static func bytes(_ text: String) -> [UInt8]? {
        let hex = text.filter { !$0.isWhitespace }
        guard hex.count % 2 == 0, hex.allSatisfy(\.isHexDigit) else { return nil }
        var result: [UInt8] = []
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }

    static func string(_ bytes: [UInt8], separator: String = " ") -> String {
        bytes.map { String(format: "%02X", $0) }.joined(separator: separator)
    }
}

/// Zerlegt ELM327-Antwortzeilen (Header an, Leerzeichen aus) in UDS-Nachrichten.
/// BMW nutzt erweiterte CAN-Adressierung: nach dem 11-Bit-Header (z. B. 672)
/// folgt F1 (Tester-Adresse), danach das ISO-TP-PCI-Byte.
enum ISOTP {
    static func messages(from lines: [String]) -> [[UInt8]] {
        var result: [[UInt8]] = []
        var current: [UInt8] = []
        var expected = 0

        for line in lines {
            guard line.count >= 5, line.allSatisfy(\.isHexDigit), (line.count - 3) % 2 == 0,
                  var bytes = Hex.bytes(String(line.dropFirst(3)))
            else { continue }
            if bytes.first == 0xF1 { bytes.removeFirst() }
            guard let pci = bytes.first else { continue }

            switch pci >> 4 {
            case 0x0: // Single Frame
                let data = Array(bytes.dropFirst().prefix(Int(pci & 0x0F)))
                if !data.isEmpty { result.append(data) }
            case 0x1: // First Frame
                guard bytes.count >= 2 else { continue }
                expected = Int(pci & 0x0F) << 8 | Int(bytes[1])
                current = Array(bytes.dropFirst(2))
            case 0x2: // Consecutive Frame
                guard expected > 0 else { continue }
                current += bytes.dropFirst()
                if current.count >= expected {
                    result.append(Array(current.prefix(expected)))
                    current = []
                    expected = 0
                }
            default: // Flow Control o. ä.
                continue
            }
        }
        if expected > 0, !current.isEmpty { result.append(current) }
        return result
    }
}
