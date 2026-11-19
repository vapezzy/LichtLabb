import Foundation

/// Live-Werte rund um den Dieselpartikelfilter (Rußfilter).
/// Liest ausschließlich genormte OBD-II-Messwerte (Modus 01, SAE J1979) vom Motorsteuergerät –
/// es wird nichts angesteuert, gestartet oder verändert.
@MainActor
final class DPFMonitor: ObservableObject {
    struct Reading: Equatable {
        /// Differenzdruck über dem Filter in mbar – steigt mit der Rußbeladung
        var deltaPressure: Double?
        /// Temperatur vor / nach dem Filter in °C
        var inletTemp: Double?
        var outletTemp: Double?
        /// Abgastemperatur (erster Sensor) in °C
        var exhaustTemp: Double?
        /// Regeneration läuft laut Steuergerät
        var regenActive: Bool?
        /// Beladung bis zur nächsten Regeneration in % (100 % = Regeneration fällig)
        var regenTrigger: Double?
        /// Durchschnittlicher Abstand zwischen Regenerationen (km) und Dauer (min), wenn geliefert
        var averageDistance: Double?
        var averageMinutes: Double?
        var coolant: Double?
        var oil: Double?
        var rpm: Double?
        var speed: Double?

        /// Regeneration läuft – entweder laut Steuergerät oder erkennbar an der Temperatur vor dem Filter
        var regenerating: Bool {
            if let regenActive { return regenActive }
            if let inletTemp { return inletTemp > 480 }
            return false
        }

        var hasDPFData: Bool {
            deltaPressure != nil || inletTemp != nil || regenTrigger != nil || regenActive != nil
        }
    }

    enum State: Equatable {
        case idle
        case discovering
        case live
        case failed(String)
    }

    @Published private(set) var reading = Reading()
    @Published private(set) var state: State = .idle
    @Published private(set) var supported: Set<UInt8> = []
    @Published private(set) var isDemo = false
    @Published private(set) var lastUpdate: Date?

    private let session: ELMSession
    private var task: Task<Void, Never>?

    /// Alle Werte, die gelesen werden, wenn das Steuergerät sie unterstützt.
    static let wanted: [UInt8] = [0x7A, 0x7C, 0x8B, 0x78, 0x05, 0x5C, 0x0C, 0x0D]

    init(session: ELMSession) {
        self.session = session
    }

    // MARK: - Steuerung

    func start() {
        task?.cancel()
        task = nil
        guard session.isInitialized else {
            startDemo()
            return
        }
        isDemo = false
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
        if case .failed = state { return }
        state = .idle
    }

    private func run() async {
        state = .discovering
        do {
            supported = try await discoverSupported()
            let pids = Self.wanted.filter { supported.contains($0) }
            if pids.isEmpty {
                state = .failed("Das Motorsteuergerät liefert keine Rußfilter-Werte über die Standard-Schnittstelle.")
                return
            }
            state = .live
            while !Task.isCancelled {
                var next = reading
                for pid in pids {
                    if Task.isCancelled { break }
                    if let data = try await session.readPID(pid) {
                        Self.apply(pid: pid, data: data, to: &next)
                    }
                }
                reading = next
                lastUpdate = Date()
                try? await Task.sleep(nanoseconds: 600_000_000)
            }
        } catch {
            if !Task.isCancelled {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func discoverSupported() async throws -> Set<UInt8> {
        try await session.supportedPIDs()
    }

    // MARK: - Dekodierung (SAE J1979)

    nonisolated static func decodeSupport(base: UInt8, data: [UInt8]) -> Set<UInt8> {
        ELMSession.decodeSupport(base: base, data: data)
    }

    nonisolated static func apply(pid: UInt8, data d: [UInt8], to r: inout Reading) {
        func u16(_ i: Int) -> Double? { d.count > i + 1 ? Double(UInt16(d[i]) << 8 | UInt16(d[i + 1])) : nil }
        func s16(_ i: Int) -> Double? { d.count > i + 1 ? Double(Int16(bitPattern: UInt16(d[i]) << 8 | UInt16(d[i + 1]))) : nil }
        func temp16(_ i: Int) -> Double? { u16(i).map { $0 / 10 - 40 } }
        func has(_ bit: UInt8) -> Bool { (d.first ?? 0) & bit != 0 }

        switch pid {
        case 0x7A:
            // A: unterstützt (Bit0 Differenzdruck), B-C: Differenzdruck in 0,01 kPa (vorzeichenbehaftet)
            if has(0x01), let raw = s16(1) { r.deltaPressure = raw * 0.01 * 10 }   // kPa → mbar
        case 0x7C:
            // A: unterstützt (Bit0 Bank 1 vor, Bit1 Bank 1 nach), B-C / D-E: Temperatur = Wert/10 − 40 °C
            if has(0x01) { r.inletTemp = temp16(1) }
            if has(0x02) { r.outletTemp = temp16(3) }
        case 0x78:
            // A: unterstützt (Bit0 Sensor 1), B-C: Temperatur = Wert/10 − 40 °C
            if has(0x01) { r.exhaustTemp = temp16(1) }
        case 0x8B:
            // A: unterstützt, B: Status (Bit0 Regeneration läuft), C: Beladung bis zum Auslösen (×100/255 %),
            // D-E: Ø Zeit zwischen Regenerationen (min), F-G: Ø Strecke zwischen Regenerationen (km)
            guard d.count >= 3 else { return }
            if has(0x01) { r.regenActive = d[1] & 0x01 != 0 }
            r.regenTrigger = Double(d[2]) * 100 / 255
            if let minutes = u16(3), minutes > 0 { r.averageMinutes = minutes }
            if let km = u16(5), km > 0 { r.averageDistance = km }
        case 0x05:
            if let a = d.first { r.coolant = Double(a) - 40 }
        case 0x5C:
            if let a = d.first { r.oil = Double(a) - 40 }
        case 0x0C:
            if let raw = u16(0) { r.rpm = raw / 4 }
        case 0x0D:
            if let a = d.first { r.speed = Double(a) }
        default:
            break
        }
    }

    // MARK: - Beispiel

    /// Beispielwerte ohne Auto: Filter halb voll, Motor warm, keine Regeneration.
    func startDemo() {
        task?.cancel()
        isDemo = true
        supported = Set(Self.wanted)
        state = .live
        task = Task { [weak self] in
            let start = Date()
            while !Task.isCancelled {
                let t = Date().timeIntervalSince(start)
                guard let self else { return }
                self.reading = Reading(
                    deltaPressure: 38 + 4 * sin(t * 0.9),
                    inletTemp: 268 + 12 * sin(t * 0.4),
                    outletTemp: 241 + 9 * sin(t * 0.35),
                    exhaustTemp: 312 + 15 * sin(t * 0.5),
                    regenActive: false,
                    regenTrigger: 63,
                    averageDistance: 412,
                    averageMinutes: 18,
                    coolant: 88,
                    oil: 94,
                    rpm: 820 + 30 * sin(t * 2),
                    speed: 0)
                self.lastUpdate = Date()
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
