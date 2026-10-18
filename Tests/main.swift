import Foundation

// Ende-zu-Ende-Test der Diagnose gegen den ELM327/BMW-Simulator.
// Aufruf aus dem Projektordner:  sh tools/run_tests.sh

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ✅ \(message)" : "  ❌ \(message)")
    if !condition { failures += 1 }
}

let vin = Array("WBA4A31070GTEST123".utf8)

@MainActor
func makeCar() -> ELMSimulator {
    let sim = ELMSimulator()
    // DME mit zwei Fehlern und Fahrgestellnummer (mehrteilige Antworten)
    sim.ecus[0x12] = { request in
        switch request {
        case [0x19, 0x02, 0x0D]: return [0x59, 0x02, 0xFF, 0x12, 0x03, 0x08, 0x08, 0x1B, 0x2A, 0x00, 0x09]
        case [0x22, 0xF1, 0x90]: return [0x62, 0xF1, 0x90] + vin
        default: return [0x7F, request[0], 0x11]
        }
    }
    // DSC ohne Fehler
    sim.ecus[0x29] = { request in request.first == 0x19 ? [0x59, 0x02, 0xFF] : [0x7F, request[0], 0x11] }
    // FEM: ein Fehler, Licht-Steuerung per 2F
    sim.ecus[0x40] = { request in
        switch request.first {
        case 0x19: return [0x59, 0x02, 0xFF, 0x80, 0x1C, 0x20, 0x2F]
        case 0x10: return [0x50, request[1], 0x00, 0x32, 0x01, 0xF4]
        case 0x2F: return [0x6F] + request.dropFirst()
        case 0x3E: return nil
        default: return [0x7F, request[0], 0x11]
        }
    }
    sim.obdStored = [0x0300]
    return sim
}

@MainActor
func run() async {
    print("Fehlerspeicher-Scan (Schnell)")
    let sim = makeCar()
    let session = ELMSession(transport: sim)
    await session.initialize()
    check(session.isInitialized, "Adapter initialisiert")

    let scanner = FaultScanner(session: session)
    scanner.start()
    while scanner.phase != .finished(Date.distantPast), !isFinished(scanner) {
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    check(scanner.abortReason == nil, "Scan nicht abgebrochen \(scanner.abortReason ?? "")")
    let order = sim.received.filter { $0.hasPrefix("ATFCS") }.prefix(3)
    check(Array(order) == ["ATFCSH6F1", "ATFCSD12300000", "ATFCSM1"], "Flow-Control-Reihenfolge: \(Array(order))")
    check(scanner.results.map(\.address) == [0x12, 0x29, 0x40], "genau DME, DSC und FEM gefunden: \(scanner.results.map(\.hexAddress))")
    check(scanner.results.allSatisfy { $0.error == nil }, "keine Lesefehler")
    let dme = scanner.results.first { $0.address == 0x12 }
    check(dme?.faults.map(\.code) == ["120308", "1B2A00"], "DME-Fehler gelesen: \(dme?.faults.map(\.code) ?? [])")
    check(dme?.faults.last?.isActive == true, "Status „aktiv“ erkannt")
    check(scanner.results.first { $0.address == 0x29 }?.faults.isEmpty == true, "DSC ohne Einträge")
    check(scanner.results.first { $0.address == 0x40 }?.faults.map(\.code) == ["801C20"], "FEM-Fehler gelesen")
    check(scanner.vin == "WBA4A31070GTEST123", "Fahrgestellnummer: \(scanner.vin ?? "–")")
    check(scanner.obdCodes.map(\.code) == ["P0300"], "OBD-II: \(scanner.obdCodes.map(\.code))")

    print("Licht schalten nach dem Scan")
    var preset = LightPreset(name: "Test", spots: [.angelEyeLeft])
    preset.ecu = "40"; preset.did = "D1 23"; preset.controlData = "01"
    do {
        try await session.setLight(preset, on: true)
        try await session.setLight(preset, on: false)
        check(true, "2F an/aus am FEM positiv beantwortet")
    } catch {
        check(false, "Licht schalten: \(error.localizedDescription)")
    }
    await session.endAllSessions()

    print("Unbekanntes Steuergerät")
    do {
        _ = try await session.readDTCs(ecu: 0x55)
        check(false, "hätte „keine Antwort“ melden müssen")
    } catch ELMSession.SessionError.noResponse {
        check(true, "fehlendes Steuergerät → keine Antwort")
    } catch {
        check(false, "falscher Fehler: \(error.localizedDescription)")
    }

    print("Adapter lehnt BMW-Adressierung ab")
    let picky = makeCar()
    picky.rejectExtendedAddressing = true
    let pickySession = ELMSession(transport: picky)
    await pickySession.initialize()
    let pickyScanner = FaultScanner(session: pickySession)
    pickyScanner.mode = .full
    pickyScanner.start()
    while !isFinished(pickyScanner) { try? await Task.sleep(nanoseconds: 20_000_000) }
    check(pickyScanner.abortReason != nil, "Scan bricht mit Meldung ab: \(pickyScanner.abortReason ?? "–")")
    check(pickyScanner.results.isEmpty, "keine 127 Fehlerzeilen (\(pickyScanner.results.count))")
    let pickyRequests = picky.received.filter { $0.hasPrefix("ATCEA") && $0.count > 5 }.count
    check(pickyRequests <= 2, "bricht sofort ab (\(pickyRequests) Versuche)")

    print(failures == 0 ? "\nAlle Tests bestanden." : "\n\(failures) Test(s) fehlgeschlagen.")
    exit(failures == 0 ? 0 : 1)
}

@MainActor
func isFinished(_ scanner: FaultScanner) -> Bool {
    if case .finished = scanner.phase { return true }
    return false
}

Task { @MainActor in await run() }
RunLoop.main.run()
