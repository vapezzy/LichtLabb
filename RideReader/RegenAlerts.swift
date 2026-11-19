import Foundation
import UserNotifications

/// Meldungen für den Regenerations-Alarm: Vibration und Mitteilung (auch als Banner, wenn die App offen ist).
enum RegenAlerts {
    private static let delegate = ForegroundBanner()

    static func setUp() {
        UNUserNotificationCenter.current().delegate = delegate
    }

    static func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    @MainActor
    static func regenChanged(_ active: Bool) {
        // Dreimal deutlich vibrieren, wenn es losgeht
        Task { @MainActor in
            for _ in 0..<(active ? 3 : 1) {
                Haptics.warning()
                try? await Task.sleep(nanoseconds: 450_000_000)
            }
        }
        let content = UNMutableNotificationContent()
        content.title = active ? "Regeneration läuft" : "Regeneration fertig"
        content.body = active
            ? "Der Rußfilter brennt frei. Motor jetzt nicht abstellen – am besten noch 10–15 Minuten weiterfahren."
            : "Der Rußfilter ist wieder frei. Du kannst jetzt ganz normal abstellen."
        content.sound = .default
        let request = UNNotificationRequest(identifier: "dpf-regen", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}

/// Zeigt Mitteilungen auch dann als Banner, wenn RideReader gerade im Vordergrund ist.
private final class ForegroundBanner: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
