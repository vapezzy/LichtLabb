import Foundation
import WidgetKit
#if canImport(ActivityKit) && os(iOS)
import ActivityKit
#endif

/// Schreibt aktuelle Werte für die Widgets und steuert die Live-Aktivität während einer DPF-Regeneration.
@MainActor
enum WidgetBridge {
    private static var lastVoltageWrite = Date.distantPast
    private static var lastDPFWrite = Date.distantPast

    private static func update(_ change: (inout WidgetShared.Snapshot) -> Void) {
        let old = WidgetShared.load()
        var snapshot = old
        change(&snapshot)
        let p = Palette.current
        snapshot.colors = [p.accent, p.violet, p.magenta].compactMap(\.rgba)
        guard snapshot != old else { return }
        WidgetShared.save(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetShared.kind)
    }

    /// Batteriespannung – höchstens einmal pro Minute schreiben
    static func voltage(_ volts: Double) {
        guard Date().timeIntervalSince(lastVoltageWrite) > 60 else { return }
        lastVoltageWrite = Date()
        update {
            $0.voltage = volts
            $0.voltageDate = Date()
        }
    }

    static func scanFinished(_ scanner: FaultScanner) {
        guard !scanner.isDemo else { return }
        let infos = scanner.results.flatMap { r in r.faults.map { FaultCatalog.info(for: $0, ecu: r.address) } }
            + scanner.obdCodes.map { FaultCatalog.info(for: $0, ecu: nil) }
        update {
            $0.faults = infos.count
            $0.severe = infos.filter { $0.severity == .severe }.count
            $0.scanDate = Date()
        }
    }

    static func themeChanged(edition: String?) {
        update { $0.edition = edition }
    }

    /// Neue Rußfilter-Werte: Widget aktualisieren (Regenerationswechsel sofort, sonst 1× pro Minute) und Live-Aktivität führen.
    static func dpf(_ reading: DPFMonitor.Reading) {
        let old = WidgetShared.load()
        let changed = old.regenerating != reading.regenerating
        if changed || Date().timeIntervalSince(lastDPFWrite) > 60 {
            lastDPFWrite = Date()
            update {
                $0.regenerating = reading.regenerating
                if let load = reading.regenTrigger { $0.dpfLoad = load }
                $0.dpfDate = Date()
            }
        }
        regenActivity(active: reading.regenerating, temp: reading.inletTemp, load: reading.regenTrigger)
    }

    #if canImport(ActivityKit) && os(iOS)
    private static var activity: Activity<RegenActivityAttributes>?

    private static func regenActivity(active: Bool, temp: Double?, load: Double?) {
        let state = RegenActivityAttributes.ContentState(inletTemp: temp, load: load, finished: !active)
        if active {
            if let activity {
                Task { await activity.update(ActivityContent(state: state, staleDate: nil)) }
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                activity = try? Activity.request(attributes: RegenActivityAttributes(startedAt: Date()),
                                                 content: ActivityContent(state: state, staleDate: nil),
                                                 pushType: nil)
            }
        } else if let current = activity {
            activity = nil
            Task {
                await current.end(ActivityContent(state: state, staleDate: nil),
                                  dismissalPolicy: .after(Date().addingTimeInterval(600)))
            }
        }
    }
    #else
    private static func regenActivity(active: Bool, temp: Double?, load: Double?) {}
    #endif
}
