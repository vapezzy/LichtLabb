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

    private func save() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
