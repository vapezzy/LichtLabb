import Foundation

/// Eine Lichtszene: eine Folge von Schritten, in denen bestimmte Leuchten an sind.
/// Das Xenon-Abblendlicht und das Fernlicht kommen absichtlich in keiner Szene vor.
struct LightShow: Identifiable {
    struct Step {
        var spots: Set<LightSpot>
        var duration: Double
    }

    let id: String
    let name: String
    let subtitle: String
    let icon: String
    let steps: [Step]

    var duration: Double { steps.reduce(0) { $0 + $1.duration } }

    static func all(for style: RearLightStyle) -> [LightShow] {
        var shows = [welcome, goodbye, runner, scanner, hazard, alternate, pulse]
        if style == .oled { shows.insert(oledWelcome, at: 0) }
        return shows
    }

    // MARK: - Bausteine

    private static let eyes: Set<LightSpot> = [.angelEyeLeft, .angelEyeRight]
    private static let tails: Set<LightSpot> = [.tailLeft, .tailRight]
    private static let fog: Set<LightSpot> = [.fogLeft, .fogRight]
    private static let brake: Set<LightSpot> = [.brakeLeft, .brakeRight]
    private static let blinkLeft: Set<LightSpot> = [.blinkerFrontLeft, .blinkerRearLeft]
    private static let blinkRight: Set<LightSpot> = [.blinkerFrontRight, .blinkerRearRight]
    private static var blinkAll: Set<LightSpot> { blinkLeft.union(blinkRight) }

    private static func step(_ spots: Set<LightSpot>, _ duration: Double) -> Step {
        Step(spots: spots, duration: duration)
    }

    private static func repeated(_ steps: [Step], times: Int) -> [Step] {
        Array(repeating: steps, count: times).flatMap { $0 }
    }

    // MARK: - Szenen

    static let welcome = LightShow(
        id: "welcome", name: "Welcome", subtitle: "Angel Eyes, Rücklichter, Doppelblinken", icon: "sparkles",
        steps: [
            step(eyes, 0.8),
            step(eyes.union(tails), 0.8),
            step(eyes.union(tails).union(blinkAll), 0.5),
            step(eyes.union(tails), 0.4),
            step(eyes.union(tails).union(blinkAll), 0.5),
            step(eyes.union(tails).union(fog), 2.0),
            step([], 0.3),
        ])

    static let goodbye = LightShow(
        id: "goodbye", name: "Goodbye", subtitle: "Langsames Ausblenden von außen nach innen", icon: "moon.stars",
        steps: [
            step(eyes.union(tails).union(fog), 1.0),
            step(eyes.union(tails), 0.8),
            step(eyes, 0.8),
            step(blinkAll, 0.5),
            step([], 0.4),
            step(blinkAll, 0.5),
            step([], 0.3),
        ])

    static let runner = LightShow(
        id: "runner", name: "Lauflicht", subtitle: "Von vorne nach hinten durchs Auto", icon: "arrow.right.circle",
        steps: [
            step([.blinkerFrontLeft, .blinkerFrontRight], 0.45),
            step(fog, 0.45),
            step(eyes, 0.45),
            step(tails, 0.45),
            step(brake, 0.45),
            step([.blinkerRearLeft, .blinkerRearRight], 0.45),
            step([], 0.3),
        ])

    static let scanner = LightShow(
        id: "scanner", name: "Scanner", subtitle: "Links–rechts-Wischer über die Front", icon: "wave.3.right",
        steps: repeated([
            step([.blinkerFrontLeft], 0.35),
            step([.angelEyeLeft], 0.35),
            step([.angelEyeRight], 0.35),
            step([.blinkerFrontRight], 0.35),
            step([.angelEyeRight], 0.35),
            step([.angelEyeLeft], 0.35),
        ], times: 2) + [step([], 0.3)])

    static let hazard = LightShow(
        id: "hazard", name: "Warnblinker", subtitle: "Alle Blinker im Takt", icon: "exclamationmark.triangle",
        steps: repeated([step(blinkAll, 0.5), step([], 0.5)], times: 5))

    static let alternate = LightShow(
        id: "alternate", name: "Wechselblinker", subtitle: "Links und rechts im Wechsel", icon: "arrow.left.arrow.right",
        steps: repeated([step(blinkLeft, 0.5), step(blinkRight, 0.5)], times: 5) + [step([], 0.3)])

    static let pulse = LightShow(
        id: "pulse", name: "Puls", subtitle: "Angel Eyes atmen", icon: "waveform.path.ecg",
        steps: repeated([step(eyes, 0.6), step([], 0.5)], times: 4))

    static let oledWelcome = LightShow(
        id: "oledWelcome", name: "OLED Welcome", subtitle: "Startet die eigene Animation der OLED-Leuchten", icon: "rays",
        steps: [
            step([], 0.6),
            step(tails, 3.5),
            step(tails.union(eyes), 1.5),
            step([], 0.3),
        ])
}
