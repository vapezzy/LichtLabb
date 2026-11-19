import Foundation
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Daten, die die App für die Widgets hinterlegt (App-Gruppe, gemeinsam für App und Widget-Erweiterung).
enum WidgetShared {
    static let appGroup = "group.local.ridereader"
    static let kind = "RideReaderStatus"
    private static let key = "widgetSnapshot"

    struct Snapshot: Codable, Equatable {
        /// Batteriespannung an der OBD-Buchse
        var voltage: Double?
        var voltageDate: Date?
        /// Letzte Kontrolle
        var faults: Int?
        var severe: Int?
        var scanDate: Date?
        /// Rußfilter
        var dpfLoad: Double?
        var regenerating = false
        var dpfDate: Date?
        /// Design: Edition und Farben (sRGB 0…1) für Akzent, Mitte, Ende
        var edition: String?
        var colors: [[Double]]?
    }

    static var defaults: UserDefaults { UserDefaults(suiteName: appGroup) ?? .standard }

    static func load() -> Snapshot {
        guard let data = defaults.data(forKey: key),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return Snapshot() }
        return snapshot
    }

    static func save(_ snapshot: Snapshot) {
        if let data = try? JSONEncoder().encode(snapshot) {
            defaults.set(data, forKey: key)
        }
    }
}

#if canImport(ActivityKit) && os(iOS)
/// Live-Aktivität (Sperrbildschirm + Dynamic Island), solange der Rußfilter regeneriert.
struct RegenActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var inletTemp: Double?
        var load: Double?
        var finished: Bool
    }

    var startedAt: Date
}
#endif
