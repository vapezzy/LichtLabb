import Foundation

/// Echtzeitdaten und Batterie: genormte OBD-II-Messwerte (Modus 01) vom Motorsteuergerät
/// plus die Spannung an der OBD-Buchse. Nur lesen – es wird nichts angesteuert.
@MainActor
final class LiveMonitor: ObservableObject {

    /// Ein genormter Messwert mit Umrechnung nach SAE J1979.
    struct Signal: Identifiable, Equatable {
        let pid: UInt8
        let title: String
        let unit: String
        let icon: String
        let digits: Int
        /// schnell = jede Runde, sonst nur jede fünfte Runde
        let fast: Bool
        var id: UInt8 { pid }

        static func == (a: Signal, b: Signal) -> Bool { a.pid == b.pid }
    }

    static let signals: [Signal] = [
        Signal(pid: 0x0C, title: "Drehzahl", unit: "U/min", icon: "speedometer", digits: 0, fast: true),
        Signal(pid: 0x0D, title: "Tempo", unit: "km/h", icon: "gauge.with.dots.needle.67percent", digits: 0, fast: true),
        Signal(pid: 0x04, title: "Motorlast", unit: "%", icon: "engine.combustion", digits: 0, fast: true),
        Signal(pid: 0x11, title: "Gaspedal", unit: "%", icon: "pedal.accelerator", digits: 0, fast: true),
        Signal(pid: 0x0B, title: "Saugrohrdruck", unit: "bar", icon: "wind", digits: 2, fast: true),
        Signal(pid: 0x10, title: "Luftmasse", unit: "g/s", icon: "aqi.low", digits: 1, fast: true),
        Signal(pid: 0x23, title: "Raildruck", unit: "bar", icon: "drop.triangle", digits: 0, fast: true),
        Signal(pid: 0x5E, title: "Verbrauch", unit: "l/h", icon: "fuelpump", digits: 1, fast: true),
        Signal(pid: 0x05, title: "Kühlmittel", unit: "°C", icon: "thermometer.medium", digits: 0, fast: false),
        Signal(pid: 0x5C, title: "Motoröl", unit: "°C", icon: "oilcan.fill", digits: 0, fast: false),
        Signal(pid: 0x0F, title: "Ansaugluft", unit: "°C", icon: "thermometer.low", digits: 0, fast: false),
        Signal(pid: 0x46, title: "Außen", unit: "°C", icon: "sun.max", digits: 0, fast: false),
        Signal(pid: 0x2F, title: "Tank", unit: "%", icon: "fuelpump.fill", digits: 0, fast: false),
        Signal(pid: 0x33, title: "Luftdruck", unit: "mbar", icon: "barometer", digits: 0, fast: false),
        Signal(pid: 0x42, title: "Steuergerät-Spannung", unit: "V", icon: "bolt.fill", digits: 2, fast: false),
        Signal(pid: 0x1F, title: "Seit Motorstart", unit: "min", icon: "timer", digits: 0, fast: false),
        Signal(pid: 0x31, title: "km seit Fehler löschen", unit: "km", icon: "eraser", digits: 0, fast: false),
        Signal(pid: 0xA6, title: "Kilometerstand", unit: "km", icon: "road.lanes", digits: 1, fast: false),
        Signal(pid: 0x2C, title: "AGR Sollwert", unit: "%", icon: "arrow.triangle.2.circlepath", digits: 0, fast: true),
        Signal(pid: 0x2D, title: "AGR Abweichung", unit: "%", icon: "plusminus", digits: 0, fast: true),
        Signal(pid: 0x6B, title: "AGR Temperatur", unit: "°C", icon: "thermometer.sun", digits: 0, fast: false),
    ]

    /// Umrechnung der Datenbytes nach `41 <PID>` in den angezeigten Wert.
    nonisolated static func decode(pid: UInt8, data d: [UInt8]) -> Double? {
        func a() -> Double? { d.first.map(Double.init) }
        func ab() -> Double? { d.count >= 2 ? Double(UInt16(d[0]) << 8 | UInt16(d[1])) : nil }
        switch pid {
        case 0x04, 0x11, 0x2F: return a().map { $0 * 100 / 255 }
        case 0x05, 0x0F, 0x46, 0x5C: return a().map { $0 - 40 }
        case 0x0B: return a().map { $0 / 100 }                 // kPa absolut → bar
        case 0x0C: return ab().map { $0 / 4 }
        case 0x0D: return a()
        case 0x10: return ab().map { $0 / 100 }
        case 0x1F: return ab().map { $0 / 60 }                 // s → min
        case 0x23: return ab().map { $0 * 10 / 100 }           // 10 kPa je Bit → bar
        case 0x31: return ab()
        case 0x33: return a().map { $0 * 10 }                  // kPa → mbar
        case 0x42: return ab().map { $0 / 1000 }
        case 0x5E: return ab().map { $0 / 20 }
        case 0x2C: return a().map { $0 * 100 / 255 }          // Sollwert AGR
        case 0x2D: return a().map { ($0 - 128) * 100 / 128 }    // Abweichung Ist/Soll
        case 0x6B:                                              // AGR-Temperatur, Sensor A (Bit0 im Unterstützungsbyte)
            guard d.count >= 2, d[0] & 0x01 != 0 else { return nil }
            return Double(d[1]) - 40
        case 0xA6:
            guard d.count >= 4 else { return nil }
            let raw = UInt32(d[0]) << 24 | UInt32(d[1]) << 16 | UInt32(d[2]) << 8 | UInt32(d[3])
            return Double(raw) / 10
        default: return nil
        }
    }

    // MARK: - AU-Bereitschaft (Modus 01, PID 01)

    struct Readiness: Equatable {
        struct Monitor: Equatable {
            let name: String
            let complete: Bool
        }
        /// Motorkontrollleuchte an
        var mil: Bool
        var dtcCount: Int
        var diesel: Bool
        var monitors: [Monitor]

        var openCount: Int { monitors.filter { !$0.complete }.count }
        var ready: Bool { !mil && openCount == 0 }
    }

    /// Bereitschaftstests nach SAE J1979: B = gemeinsame Tests (verfügbar Bit 0–2, unvollständig Bit 4–6),
    /// C = verfügbare und D = unvollständige motorspezifische Tests (Diesel oder Benziner, je nach B3).
    nonisolated static func decodeReadiness(_ d: [UInt8]) -> Readiness? {
        guard d.count >= 4 else { return nil }
        let a = d[0], b = d[1], c = d[2], e = d[3]
        var monitors: [Readiness.Monitor] = []
        for (bit, name) in [(0, "Zündaussetzer"), (1, "Kraftstoffsystem"), (2, "Bauteile")] where b & (UInt8(1) << bit) != 0 {
            monitors.append(.init(name: name, complete: b & (UInt8(1) << (bit + 4)) == 0))
        }
        let diesel = b & 0x08 != 0
        let names: [Int: String] = diesel
            ? [0: "NMHC-Katalysator", 1: "NOx-Nachbehandlung", 3: "Ladedruck", 5: "Abgassensor", 6: "Partikelfilter", 7: "AGR/VVT"]
            : [0: "Katalysator", 1: "Kat-Heizung", 2: "Tankentlüftung", 3: "Sekundärluft", 4: "Klimaanlage",
               5: "Lambdasonde", 6: "Lambdasonden-Heizung", 7: "AGR/VVT"]
        for bit in 0..<8 {
            if let name = names[bit], c & (UInt8(1) << bit) != 0 {
                monitors.append(.init(name: name, complete: e & (UInt8(1) << bit) == 0))
            }
        }
        return Readiness(mil: a & 0x80 != 0, dtcCount: Int(a & 0x7F), diesel: diesel, monitors: monitors)
    }

    @Published private(set) var readiness: Readiness?

    enum State: Equatable {
        case idle, discovering, live
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var values: [UInt8: Double] = [:]
    @Published private(set) var supported: Set<UInt8> = []
    /// Spannung an der OBD-Buchse
    @Published private(set) var voltage: Double?
    @Published private(set) var isDemo = false

    // Batterietest
    enum TestStep: Equatable {
        case none
        case rest(progress: Double)
        case waitForStart(seconds: Int)
        case charging(progress: Double)
        case done
    }

    struct TestResult: Equatable {
        var rest: Double?
        var crankMin: Double?
        var charging: Double?
    }

    @Published private(set) var testStep: TestStep = .none
    @Published private(set) var result = TestResult()

    private let session: ELMSession
    private var task: Task<Void, Never>?
    private var testTask: Task<Void, Never>?

    init(session: ELMSession) {
        self.session = session
    }

    var visibleSignals: [Signal] {
        Self.signals.filter { supported.contains($0.pid) }
    }

    // MARK: - Echtzeit

    func start() {
        task?.cancel()
        task = nil
        guard testTask == nil else { return }
        guard session.isInitialized else {
            startDemo()
            return
        }
        isDemo = false
        values = [:]
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        testTask?.cancel()
        testTask = nil
        if case .done = testStep {} else { testStep = .none }
        if case .failed = state { return }
        state = .idle
    }

    private func run() async {
        state = .discovering
        do {
            supported = try await session.supportedPIDs()
            state = .live
            var round = 0
            while !Task.isCancelled {
                if supported.contains(0x01), round % 40 == 0,
                   let data = try await session.readPID(0x01), let r = Self.decodeReadiness(data) {
                    readiness = r
                }
                let due = Self.signals.filter { supported.contains($0.pid) && ($0.fast || round % 5 == 0) }
                var next = values
                for signal in due {
                    if Task.isCancelled { return }
                    if let data = try await session.readPID(signal.pid), let value = Self.decode(pid: signal.pid, data: data) {
                        next[signal.pid] = value
                    }
                }
                if round % 2 == 0, let v = try await session.readVoltage() { voltage = v }
                values = next
                round += 1
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        } catch {
            if !Task.isCancelled { state = .failed(error.localizedDescription) }
        }
    }

    // MARK: - Batterietest

    /// Geführter Test: 1. Ruhespannung (Motor aus) · 2. Startspannung (Motor starten) · 3. Ladespannung (Motor läuft).
    func startBatteryTest() {
        guard session.isInitialized else { return }
        task?.cancel()
        task = nil
        result = TestResult()
        testTask = Task { [weak self] in
            await self?.runBatteryTest()
            self?.testTask = nil
            self?.start()
        }
    }

    func cancelBatteryTest() {
        testTask?.cancel()
        testTask = nil
        testStep = .none
        start()
    }

    func resetBatteryTest() {
        testStep = .none
        result = TestResult()
    }

    private func runBatteryTest() async {
        do {
            // 1. Ruhespannung: 3 s mitteln
            var samples: [Double] = []
            let restEnd = Date().addingTimeInterval(3)
            while Date() < restEnd {
                if Task.isCancelled { return }
                if let v = try await session.readVoltage() { samples.append(v); voltage = v }
                testStep = .rest(progress: 1 - restEnd.timeIntervalSinceNow / 3)
            }
            result.rest = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)

            // 2. Startspannung: so schnell wie möglich messen, tiefster Wert beim Anlassen
            var minimum = Double.infinity
            var started = false
            let crankEnd = Date().addingTimeInterval(20)
            var sawDrop = false
            while Date() < crankEnd {
                if Task.isCancelled { return }
                testStep = .waitForStart(seconds: max(0, Int(crankEnd.timeIntervalSinceNow.rounded(.up))))
                guard let v = try await session.readVoltage() else { continue }
                voltage = v
                minimum = min(minimum, v)
                if let rest = result.rest, v < rest - 1.0 { sawDrop = true }
                // Motor läuft, sobald die Lichtmaschine lädt (deutlich über der Ruhespannung) – nach einem Spannungseinbruch
                if sawDrop, v > max(13.0, (result.rest ?? 12.6) + 0.4) {
                    started = true
                    break
                }
            }
            result.crankMin = minimum.isFinite && sawDrop ? minimum : nil

            // 3. Ladespannung: 5 s mitteln (nur wenn der Motor läuft)
            if started {
                samples = []
                let chargeEnd = Date().addingTimeInterval(5)
                while Date() < chargeEnd {
                    if Task.isCancelled { return }
                    if let v = try await session.readVoltage() { samples.append(v); voltage = v }
                    testStep = .charging(progress: 1 - chargeEnd.timeIntervalSinceNow / 5)
                }
                result.charging = samples.isEmpty ? nil : samples.reduce(0, +) / Double(samples.count)
            }
            testStep = .done
        } catch {
            testStep = .none
            state = .failed(error.localizedDescription)
        }
    }

    // MARK: - Bewertung

    enum Grade { case good, okay, weak, bad }

    /// Ruhespannung (Motor aus) → geschätzter Ladezustand in % (AGM/Blei, grob).
    nonisolated static func stateOfCharge(_ volts: Double) -> Double {
        let table: [(Double, Double)] = [(11.8, 0), (12.0, 20), (12.2, 45), (12.4, 70), (12.6, 90), (12.8, 100)]
        if volts <= table[0].0 { return 0 }
        for i in 1..<table.count where volts <= table[i].0 {
            let (v0, p0) = table[i - 1], (v1, p1) = table[i]
            return p0 + (p1 - p0) * (volts - v0) / (v1 - v0)
        }
        return 100
    }

    nonisolated static func gradeRest(_ v: Double) -> Grade {
        v >= 12.5 ? .good : v >= 12.3 ? .okay : v >= 12.0 ? .weak : .bad
    }

    nonisolated static func gradeCrank(_ v: Double) -> Grade {
        v >= 10.2 ? .good : v >= 9.6 ? .okay : v >= 9.0 ? .weak : .bad
    }

    /// BMW lädt „intelligent“: je nach Batteriezustand sind 12,8–15 V im Leerlauf normal.
    nonisolated static func gradeCharging(_ v: Double) -> Grade {
        (12.8...15.0).contains(v) ? .good : (12.5..<12.8).contains(v) ? .weak : .bad
    }

    // MARK: - Beispiel

    private func startDemo() {
        isDemo = true
        supported = Set(Self.signals.map(\.pid)).subtracting([0xA6])
        state = .live
        task = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                guard let self else { return }
                let rpm = 820 + 40 * sin(t * 1.3)
                self.values = [
                    0x0C: rpm, 0x0D: 0, 0x04: 21 + 3 * sin(t), 0x11: 0, 0x0B: 1.02, 0x10: 7.8 + 0.4 * sin(t * 2),
                    0x23: 300 + 15 * sin(t), 0x5E: 0.9, 0x05: 88, 0x5C: 96, 0x0F: 24, 0x46: 9, 0x2F: 58,
                    0x33: 1012, 0x42: 14.1, 0x1F: 12, 0x31: 1840,
                    0x2C: 34 + 6 * sin(t * 0.7), 0x2D: -3 + 2 * sin(t * 1.1), 0x6B: 142 + 8 * sin(t * 0.4),
                ]
                self.voltage = 14.05 + 0.05 * sin(t * 0.8)
                self.readiness = Self.decodeReadiness([0x00, 0x0F, 0xEB, 0x40])
                try? await Task.sleep(nanoseconds: 400_000_000)
            }
        }
    }
}
