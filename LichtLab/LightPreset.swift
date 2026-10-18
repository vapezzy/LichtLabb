import Foundation

/// Lichtfarbe einer Leuchte.
enum LightTint {
    case coolWhite, warmWhite, amber, red

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .coolWhite: return (0.80, 0.90, 1.00)
        case .warmWhite: return (1.00, 0.93, 0.80)
        case .amber: return (1.00, 0.52, 0.02)
        case .red: return (1.00, 0.04, 0.05)
        }
    }
}

/// Position einer Leuchte am 3D-Auto.
enum LightSpot: String, Codable, CaseIterable, Identifiable {
    case angelEyeLeft, angelEyeRight
    case highBeamLeft, highBeamRight
    case blinkerFrontLeft, blinkerFrontRight
    case fogLeft, fogRight
    case tailLeft, tailRight
    case brakeLeft, brakeRight
    case blinkerRearLeft, blinkerRearRight
    case reverseLeft, reverseRight
    case rearFog

    var id: String { rawValue }

    var isFront: Bool {
        switch self {
        case .angelEyeLeft, .angelEyeRight, .highBeamLeft, .highBeamRight,
             .blinkerFrontLeft, .blinkerFrontRight, .fogLeft, .fogRight:
            return true
        default:
            return false
        }
    }

    var tint: LightTint {
        switch self {
        case .angelEyeLeft, .angelEyeRight, .highBeamLeft, .highBeamRight, .reverseLeft, .reverseRight: return .coolWhite
        case .fogLeft, .fogRight: return .warmWhite
        case .blinkerFrontLeft, .blinkerFrontRight, .blinkerRearLeft, .blinkerRearRight: return .amber
        case .tailLeft, .tailRight, .brakeLeft, .brakeRight, .rearFog: return .red
        }
    }

    var title: String {
        switch self {
        case .angelEyeLeft: return "Angel Eye links"
        case .angelEyeRight: return "Angel Eye rechts"
        case .highBeamLeft: return "Fernlicht links"
        case .highBeamRight: return "Fernlicht rechts"
        case .blinkerFrontLeft: return "Blinker vorne links"
        case .blinkerFrontRight: return "Blinker vorne rechts"
        case .fogLeft: return "Nebel links"
        case .fogRight: return "Nebel rechts"
        case .tailLeft: return "Rücklicht links"
        case .tailRight: return "Rücklicht rechts"
        case .brakeLeft: return "Bremslicht links"
        case .brakeRight: return "Bremslicht rechts"
        case .blinkerRearLeft: return "Blinker hinten links"
        case .blinkerRearRight: return "Blinker hinten rechts"
        case .reverseLeft: return "Rückfahrlicht links"
        case .reverseRight: return "Rückfahrlicht rechts"
        case .rearFog: return "Nebelschluss"
        }
    }
}

/// Bauart der Rückleuchten – bestimmt das 3D-Modell und die verfügbaren Szenen.
enum RearLightStyle: String, CaseIterable, Identifiable {
    case original, led, oled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Original"
        case .led: return "LED-Nachrüstung"
        case .oled: return "OLED-Nachbau"
        }
    }

    var footer: String {
        switch self {
        case .original:
            return "Serienmäßige BMW-Rückleuchten."
        case .led:
            return "Nachgerüstete LED-Rückleuchten mit dynamischem Blinker. Sie hängen an denselben FRM-Ausgängen wie die Originale."
        case .oled:
            return "OLED-Nachbau: hängt an denselben FRM-Ausgängen. Viele Module spielen beim Einschalten des Rücklichts eine eigene Welcome-Animation ab – dafür gibt es die Szene „OLED Welcome“. Bei Fehlermeldungen im Kombi muss ggf. die Lampenüberwachung per Codierung angepasst werden."
        }
    }
}

enum PaintColor: String, CaseIterable, Identifiable {
    case saphirSchwarz, alpinWeiss, estorilBlau, mineralGrau, melbourneRot, glacierSilber

    var id: String { rawValue }

    var title: String {
        switch self {
        case .saphirSchwarz: return "Saphirschwarz"
        case .alpinWeiss: return "Alpinweiß"
        case .estorilBlau: return "Estorilblau"
        case .mineralGrau: return "Mineralgrau"
        case .melbourneRot: return "Melbourne Rot"
        case .glacierSilber: return "Glaciersilber"
        }
    }

    var rgb: (r: Double, g: Double, b: Double) {
        switch self {
        case .saphirSchwarz: return (0.015, 0.016, 0.022)
        case .alpinWeiss: return (0.90, 0.90, 0.88)
        case .estorilBlau: return (0.03, 0.14, 0.50)
        case .mineralGrau: return (0.22, 0.24, 0.26)
        case .melbourneRot: return (0.42, 0.02, 0.03)
        case .glacierSilber: return (0.62, 0.64, 0.66)
        }
    }
}

/// Eine schaltbare Leuchte. Die DID (Datenkennung) muss für das jeweilige Steuergerät
/// erst herausgefunden werden – die Vorlagen sind deshalb leer.
struct LightPreset: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    /// Positionen am 3D-Auto, die diese Leuchte darstellt
    var spots: [LightSpot] = []
    /// Steuergeräte-Adresse in Hex, FRM beim F3x = 72
    var ecu: String = "72"
    /// 2 Byte Datenkennung in Hex, z. B. "D1 23"
    var did: String = ""
    /// Optionale Steuerdaten nach dem 03-Byte, z. B. "01" oder "FF FF"
    var controlData: String = ""

    var isFront: Bool { spots.first?.isFront ?? true }
    var tint: LightTint { spots.first?.tint ?? .coolWhite }

    var ecuByte: UInt8? {
        guard let bytes = Hex.bytes(ecu), bytes.count == 1 else { return nil }
        return bytes[0]
    }

    var didBytes: [UInt8]? {
        guard let bytes = Hex.bytes(did), bytes.count == 2 else { return nil }
        return bytes
    }

    var controlBytes: [UInt8]? { Hex.bytes(controlData) }

    var isConfigured: Bool { ecuByte != nil && didBytes != nil && controlBytes != nil }

    var onCommand: String? {
        guard let did = didBytes, let data = controlBytes else { return nil }
        return Hex.string([0x2F] + did + [0x03] + data)
    }

    var offCommand: String? {
        guard let did = didBytes else { return nil }
        return Hex.string([0x2F] + did + [0x00])
    }
}

@MainActor
final class PresetStore: ObservableObject {
    @Published var presets: [LightPreset] {
        didSet { save() }
    }

    private static let key = "lightPresets.v2"

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode([LightPreset].self, from: data) {
            presets = saved
        } else {
            presets = Self.defaults
        }
    }

    static let defaults: [LightPreset] = [
        LightPreset(name: "Angel Eyes links", spots: [.angelEyeLeft]),
        LightPreset(name: "Angel Eyes rechts", spots: [.angelEyeRight]),
        LightPreset(name: "Fernlicht", spots: [.highBeamLeft, .highBeamRight]),
        LightPreset(name: "Blinker vorne links", spots: [.blinkerFrontLeft]),
        LightPreset(name: "Blinker vorne rechts", spots: [.blinkerFrontRight]),
        LightPreset(name: "Nebelscheinwerfer", spots: [.fogLeft, .fogRight]),
        LightPreset(name: "Rücklicht links", spots: [.tailLeft]),
        LightPreset(name: "Rücklicht rechts", spots: [.tailRight]),
        LightPreset(name: "Bremslicht", spots: [.brakeLeft, .brakeRight]),
        LightPreset(name: "Blinker hinten links", spots: [.blinkerRearLeft]),
        LightPreset(name: "Blinker hinten rechts", spots: [.blinkerRearRight]),
        LightPreset(name: "Rückfahrlicht", spots: [.reverseLeft, .reverseRight]),
        LightPreset(name: "Nebelschluss", spots: [.rearFog]),
    ]

    // MARK: - Profil

    struct ProfileEntry: Equatable {
        var name: String
        var ecu: String
        var did: String
        var controlData: String
        var spots: [LightSpot]
    }

    /// Liest ein Licht-Profil: eine Leuchte pro Zeile,
    /// `Name; Steuergerät; DID; Steuerdaten; Positionen (optional, mit , getrennt)`.
    /// Leere Zeilen und Zeilen mit # werden übersprungen. Liefert die Einträge und die Nummern ungültiger Zeilen.
    nonisolated static func parseProfile(_ text: String) -> (entries: [ProfileEntry], invalidLines: [Int]) {
        var entries: [ProfileEntry] = []
        var invalid: [Int] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let separator: Character = line.contains(";") ? ";" : (line.contains("\t") ? "\t" : ",")
            let fields = line.split(separator: separator, omittingEmptySubsequences: false)
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 3, !fields[0].isEmpty,
                  let ecu = Hex.bytes(fields[1]), ecu.count == 1,
                  let did = Hex.bytes(fields[2]), did.count == 2
            else { invalid.append(index + 1); continue }
            let data = fields.count > 3 ? fields[3] : ""
            guard Hex.bytes(data) != nil else { invalid.append(index + 1); continue }
            let spots = fields.count > 4
                ? fields[4].split(separator: ",").compactMap { name in
                    LightSpot.allCases.first { $0.title.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame
                        || $0.rawValue.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }
                }
                : []
            entries.append(ProfileEntry(name: fields[0], ecu: Hex.string(ecu, separator: ""),
                                        did: Hex.string(did), controlData: Hex.string(Hex.bytes(data) ?? []), spots: spots))
        }
        return (entries, invalid)
    }

    /// Übernimmt ein Profil: Leuchten mit gleichem Namen werden aktualisiert, neue angehängt.
    @discardableResult
    func importProfile(_ text: String) -> (updated: Int, added: Int, invalidLines: [Int]) {
        let parsed = Self.parseProfile(text)
        var updated = 0, added = 0
        for entry in parsed.entries {
            if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(entry.name) == .orderedSame }) {
                presets[index].ecu = entry.ecu
                presets[index].did = entry.did
                presets[index].controlData = entry.controlData
                if !entry.spots.isEmpty { presets[index].spots = entry.spots }
                updated += 1
            } else {
                presets.append(LightPreset(name: entry.name, spots: entry.spots, ecu: entry.ecu,
                                           did: entry.did, controlData: entry.controlData))
                added += 1
            }
        }
        return (updated, added, parsed.invalidLines)
    }

    /// Aktuelles Profil als Text zum Sichern oder Teilen.
    var profileText: String {
        var lines = ["# LichtLab Licht-Profil", "# Name; Steuergerät; DID; Steuerdaten; Positionen"]
        for preset in presets {
            lines.append([preset.name, preset.ecu, preset.did, preset.controlData,
                          preset.spots.map(\.title).joined(separator: ", ")].joined(separator: "; "))
        }
        return lines.joined(separator: "\n")
    }

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
