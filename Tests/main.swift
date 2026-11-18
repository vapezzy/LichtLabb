import Foundation

// Ende-zu-Ende-Test der Diagnose gegen den ELM327/BMW-Simulator.
// Aufruf aus dem Projektordner:  sh tools/run_tests.sh

var failures = 0
func check(_ condition: Bool, _ message: String) {
    print(condition ? "  ✅ \(message)" : "  ❌ \(message)")
    if !condition { failures += 1 }
}

let vin = Array("WBA4A31070GTEST123".utf8)

/// Zustand eines simulierten Steuergeräts: Fehlerspeicher und aktive Sitzung.
final class ECUState {
    var dtcs: [[UInt8]]
    var session: UInt8 = 0x01
    /// Fehler kommt nach dem Löschen sofort wieder (Ursache besteht noch)
    var sticky = false
    /// Löschen nur in der erweiterten Sitzung erlaubt
    var needsExtendedSession = false

    init(dtcs: [[UInt8]]) { self.dtcs = dtcs }

    func respond(_ request: [UInt8], extra: (([UInt8]) -> [UInt8]?)? = nil) -> [UInt8]? {
        switch request.first {
        case 0x19:
            return [0x59, 0x02, 0xFF] + dtcs.flatMap { $0 }
        case 0x14:
            if needsExtendedSession && session != 0x03 { return [0x7F, 0x14, 0x7F] }
            if !sticky { dtcs = [] }
            return [0x54]
        case 0x10:
            session = request[1]
            return [0x50, request[1], 0x00, 0x32, 0x01, 0xF4]
        default:
            return extra?(request) ?? [0x7F, request[0], 0x11]
        }
    }
}

struct Car {
    let sim: ELMSimulator
    let dme: ECUState
    let dsc: ECUState
    let fem: ECUState
}

@MainActor
func makeCar() -> Car {
    let sim = ELMSimulator()
    // DME mit zwei Fehlern und Fahrgestellnummer (mehrteilige Antworten)
    let dme = ECUState(dtcs: [[0x12, 0x03, 0x08, 0x08], [0x1B, 0x2A, 0x00, 0x09]])
    sim.ecus[0x12] = { request in
        dme.respond(request) { $0 == [0x22, 0xF1, 0x90] ? [0x62, 0xF1, 0x90] + vin : nil }
    }
    // DSC ohne Fehler
    let dsc = ECUState(dtcs: [])
    sim.ecus[0x29] = { dsc.respond($0) }
    // FEM mit einem Fehler
    let fem = ECUState(dtcs: [[0x80, 0x1C, 0x20, 0x2F]])
    sim.ecus[0x40] = { fem.respond($0) }
    sim.obdStored = [0x0300]
    return Car(sim: sim, dme: dme, dsc: dsc, fem: fem)
}

@MainActor
func isFinished(_ scanner: FaultScanner) -> Bool {
    if case .finished = scanner.phase { return true }
    return false
}

@MainActor
func scanned(_ car: Car, mode: FaultScanner.Mode = .quick) async -> (ELMSession, FaultScanner) {
    let session = ELMSession(transport: car.sim)
    await session.initialize()
    let scanner = FaultScanner(session: session)
    scanner.mode = mode
    scanner.start()
    while !isFinished(scanner) { try? await Task.sleep(nanoseconds: 20_000_000) }
    return (session, scanner)
}

@MainActor
func run() async {
    print("Fehlerspeicher-Scan (Schnell)")
    let car = makeCar()
    let (session, scanner) = await scanned(car)
    check(session.isInitialized, "Adapter initialisiert")
    check(scanner.abortReason == nil, "Scan nicht abgebrochen \(scanner.abortReason ?? "")")
    let order = car.sim.received.filter { $0.hasPrefix("ATFCS") }.prefix(3)
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

    print("Ein Steuergerät löschen")
    await scanner.clear(0x12)
    check(car.sim.received.contains("14FFFFFF"), "Löschbefehl 14 FF FF FF gesendet")
    check(scanner.results.first { $0.address == 0x12 }?.faults.isEmpty == true, "DME nach dem Löschen leer (neu ausgelesen)")
    check(scanner.clearMessage?.contains("gelöscht") == true, "Meldung: \(scanner.clearMessage ?? "–")")
    check(scanner.results.first { $0.address == 0x40 }?.faults.count == 1, "FEM bleibt unberührt")

    print("Fehler kommt sofort wieder")
    car.fem.sticky = true
    await scanner.clear(0x40)
    check(scanner.results.first { $0.address == 0x40 }?.faults.count == 1, "FEM-Fehler wieder da")
    check(scanner.clearMessage?.contains("wiedergekommen") == true, "Meldung erklärt es: \(scanner.clearMessage ?? "–")")

    print("Löschen nur in der erweiterten Sitzung")
    let car2 = makeCar()
    car2.dme.needsExtendedSession = true
    let (_, scanner2) = await scanned(car2)
    await scanner2.clear(0x12)
    let afterClear = car2.sim.received.drop { $0 != "14FFFFFF" }
    check(Array(afterClear.prefix(3)) == ["14FFFFFF", "1003", "14FFFFFF"], "abgelehnt → 10 03 → erneut gelöscht")
    check(afterClear.contains("1001"), "danach zurück in die normale Sitzung")
    check(car2.dme.session == 0x01, "DME wieder in Sitzung 01")
    check(scanner2.results.first { $0.address == 0x12 }?.faults.isEmpty == true, "DME leer")

    print("Alle löschen")
    let car3 = makeCar()
    car3.fem.sticky = true
    let (_, scanner3) = await scanned(car3)
    await scanner3.clearAll()
    let clearCommands = car3.sim.received.filter { $0 == "14FFFFFF" }.count
    check(clearCommands == 2, "nur Steuergeräte mit Einträgen gelöscht (\(clearCommands)×)")
    check(scanner3.results.first { $0.address == 0x12 }?.faults.isEmpty == true, "DME leer")
    check(scanner3.clearMessage == "1 Steuergerät gelöscht, bei 1 sind Fehler sofort wiedergekommen (Ursache besteht noch).",
          "Zusammenfassung: \(scanner3.clearMessage ?? "–")")
    check(scanner3.obdCodes.count == 1, "OBD-II bleibt bei „Alle löschen“ unberührt")

    print("OBD-II löschen")
    await scanner3.clearOBD()
    check(car3.sim.received.contains("04"), "Modus 04 gesendet")
    check(scanner3.obdCodes.isEmpty, "OBD-II leer (neu ausgelesen)")
    check(scanner3.clearMessage == "OBD-II-Fehler gelöscht.", "Meldung: \(scanner3.clearMessage ?? "–")")
    check(scanner3.clearingAddress == nil && !scanner3.isBusy, "danach wieder bereit")

    print("Beispielmodus")
    let demo = FaultScanner(session: ELMSession(transport: ELMSimulator()))
    demo.loadDemo()
    await demo.clearAll()
    check(demo.results.allSatisfy { $0.faults.isEmpty }, "Beispiel-Fehler lassen sich ohne Auto „löschen“")

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
    picky.sim.rejectExtendedAddressing = true
    let (_, pickyScanner) = await scanned(picky, mode: .full)
    check(pickyScanner.abortReason != nil, "Scan bricht mit Meldung ab: \(pickyScanner.abortReason ?? "–")")
    check(pickyScanner.results.isEmpty, "keine 127 Fehlerzeilen (\(pickyScanner.results.count))")
    let pickyRequests = picky.sim.received.filter { $0.hasPrefix("ATCEA") && $0.count > 5 }.count
    check(pickyRequests <= 2, "bricht sofort ab (\(pickyRequests) Versuche)")

    print(failures == 0 ? "\nAlle Tests bestanden." : "\n\(failures) Test(s) fehlgeschlagen.")
    exit(failures == 0 ? 0 : 1)
}

Task { @MainActor in await run() }
RunLoop.main.run()
