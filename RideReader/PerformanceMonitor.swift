import Foundation

/// 0–100-Messung über das Tempo-Signal des Motorsteuergeräts (OBD PID 0D).
/// Tempo wird so schnell wie möglich abgefragt; die Zeitpunkte, an denen 50/60/80/100 km/h überschritten werden,
/// werden zwischen zwei Messpunkten linear interpoliert – das macht die Zeiten deutlich genauer als die Abfragerate.
@MainActor
final class PerformanceMonitor: ObservableObject {
    struct Run: Codable, Identifiable, Equatable {
        var id = UUID()
        let date: Date
        /// Zielgeschwindigkeit → Sekunden ab Start
        let splits: [Int: Double]
        let isDemo: Bool

        var total: Double? { splits[100] }
    }

    enum Phase: Equatable {
        case idle
        /// Auto rollt noch – erst anhalten
        case waitingForStop
        /// Steht, Messung scharf
        case ready
        case running(start: Date)
        case finished(Run)
        case failed(String)
    }

    static let targets = [50, 60, 80, 100]

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var speed: Double = 0
    @Published private(set) var splits: [Int: Double] = [:]
    @Published private(set) var runs: [Run] = []
    /// Messpunkte pro Sekunde (zur Info)
    @Published private(set) var sampleRate: Double = 0

    var best: Run? { runs.filter { !$0.isDemo && $0.total != nil }.min { ($0.total ?? 99) < ($1.total ?? 99) } }
    var isActive: Bool { task != nil }

    private let session: ELMSession
    private var task: Task<Void, Never>?
    private let storageKey = "performanceRuns"

    init(session: ELMSession) {
        self.session = session
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([Run].self, from: data) {
            runs = decoded
        }
    }

    // MARK: - Steuerung

    func arm() {
        task?.cancel()
        splits = [:]
        guard session.isInitialized else {
            task = Task { [weak self] in await self?.runDemo(); self?.task = nil }
            return
        }
        task = Task { [weak self] in await self?.measure(); self?.task = nil }
    }

    func cancel() {
        task?.cancel()
        task = nil
        phase = .idle
        speed = 0
    }

    // MARK: - Messung

    private func measure() async {
        phase = .waitingForStop
        var lastZero: Date?
        var prev: (t: Date, v: Double)?
        var sampleTimes: [Date] = []
        do {
            while !Task.isCancelled {
                guard let data = try await session.readPID(0x0D, fast: true), let a = data.first else { continue }
                let now = Date()
                let v = Double(a)
                speed = v
                sampleTimes.append(now)
                sampleTimes.removeAll { now.timeIntervalSince($0) > 1 }
                sampleRate = Double(sampleTimes.count)

                switch phase {
                case .waitingForStop, .ready:
                    if v == 0 {
                        lastZero = now
                        if phase != .ready { phase = .ready; Haptics.tap() }
                    } else if phase == .ready, let zero = lastZero {
                        // Losgefahren: Start zwischen letztem Stillstand und erstem Messpunkt in Bewegung
                        let begin = zero.addingTimeInterval(now.timeIntervalSince(zero) / 2)
                        phase = .running(start: begin)
                    } else {
                        phase = .waitingForStop
                    }
                case .running(let begin):
                    if let prev {
                        for target in Self.targets where splits[target] == nil {
                            if let crossing = Self.crossing(t0: prev.t.timeIntervalSince(begin), v0: prev.v,
                                                            t1: now.timeIntervalSince(begin), v1: v, target: Double(target)) {
                                splits[target] = crossing
                                Haptics.tap()
                            }
                        }
                    }
                    if splits[100] != nil {
                        finish(demo: false)
                        return
                    }
                    if v == 0 || now.timeIntervalSince(begin) > 40 {
                        phase = .failed(v == 0 ? "Abgebrochen – das Auto steht wieder." : "Zu lange – 100 km/h nicht erreicht.")
                        return
                    }
                default:
                    break
                }
                prev = (now, v)
            }
        } catch {
            if !Task.isCancelled { phase = .failed(error.localizedDescription) }
        }
    }

    /// Zeitpunkt, an dem `target` zwischen zwei Messpunkten überschritten wurde (linear interpoliert).
    nonisolated static func crossing(t0: Double, v0: Double, t1: Double, v1: Double, target: Double) -> Double? {
        guard v0 < target, v1 >= target, v1 > v0, t1 >= t0 else { return nil }
        return t0 + (target - v0) / (v1 - v0) * (t1 - t0)
    }

    private func finish(demo: Bool) {
        let run = Run(date: Date(), splits: splits, isDemo: demo)
        phase = .finished(run)
        Haptics.confirm()
        guard !demo else { return }
        runs.insert(run, at: 0)
        if runs.count > 30 { runs.removeLast(runs.count - 30) }
        if let data = try? JSONEncoder().encode(runs) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    // MARK: - Beispiel ohne Auto

    /// Simulierter Lauf (ca. 5,6 s), damit man die Anzeige ohne Auto sieht.
    private func runDemo() async {
        phase = .ready
        speed = 0
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let begin = Date()
        phase = .running(start: begin)
        var prev: (t: Double, v: Double) = (0, 0)
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 80_000_000)
            let t = Date().timeIntervalSince(begin)
            // Beschleunigung nimmt mit dem Tempo ab
            let v = 118 * (1 - exp(-t / 3.4))
            speed = v.rounded()
            for target in Self.targets where splits[target] == nil {
                if let c = Self.crossing(t0: prev.t, v0: prev.v, t1: t, v1: v, target: Double(target)) { splits[target] = c }
            }
            prev = (t, v)
            if splits[100] != nil {
                finish(demo: true)
                return
            }
        }
    }
}
