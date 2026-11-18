import Foundation

/// Wie ernst ein Fehler ist – bestimmt die Akzentfarbe (Orange / Rot).
enum Severity: Int, Comparable {
    /// Fehler – sollte man sich anschauen (Orange)
    case fault = 1
    /// Schwerwiegend – Sicherheit oder Motorschaden möglich (Rot)
    case severe = 2

    static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }

    var label: String { self == .severe ? "Schwerwiegend" : "Fehler" }
}

/// Alles, was die App zu einem Fehlercode erklären kann.
struct FaultInfo {
    let code: String
    /// Kurzer Titel, z. B. „Katalysator-Wirkungsgrad zu niedrig (Bank 1)“
    let title: String
    /// Bereich, z. B. „Abgas“ oder „Airbag“
    let area: String
    let explanation: String
    /// Was man jetzt tun sollte
    let hint: String
    let severity: Severity
    /// Websuche zum Code (ohne Fahrgestellnummer)
    let searchURL: URL
    /// true, wenn der Text aus der Tabelle stammt; false bei BMW-Herstellercodes (nur Bereich bekannt)
    let isExact: Bool
    /// Betrifft den Dieselpartikelfilter (Rußfilter) – dann zeigt die App den DPF-Knopf statt der Websuche
    var isDPF: Bool = false

    /// Überschrift wie „P0401 – Abgasrückführung – Durchfluss zu gering“
    var headline: String {
        title.hasPrefix(area) ? "\(code) – \(title)" : "\(code) – \(area) – \(title)"
    }
}

/// Erklärungen für Fehlercodes.
///
/// - OBD-II-Codes (P0300 …) sind genormt: häufige Codes stehen hier mit Klartext, der Rest wird über den
///   Nummernbereich eingeordnet.
/// - BMW-Herstellercodes (z. B. 801C20) sind nicht öffentlich dokumentiert. Die App erklärt deshalb, aus
///   welchem Steuergerät der Code stammt und was das bedeutet; den genauen Wortlaut liefert die Websuche.
enum FaultCatalog {

    static func info(for fault: FaultCode, ecu: UInt8?) -> FaultInfo {
        fault.isOBD ? obdInfo(fault) : bmwInfo(fault, ecu: ecu ?? 0)
    }

    /// Schwerster Fehler einer Liste (nil = keine Fehler).
    static func worst(_ faults: [FaultCode], ecu: UInt8?) -> Severity? {
        faults.map { info(for: $0, ecu: ecu).severity }.max()
    }

    // MARK: - OBD-II

    private enum Area {
        case air, fuelTrim, oxygen, injection, ignition, misfire, knock, cam, cooling, turbo
        case egr, secondaryAir, catalyst, evap, idle, voltage, ecu, transmission, other
        case dpf, exhaustTemp

        var name: String {
            switch self {
            case .air: return "Luftmessung"
            case .fuelTrim: return "Gemisch"
            case .oxygen: return "Lambdasonde"
            case .injection: return "Einspritzung"
            case .ignition: return "Zündung"
            case .misfire: return "Zündaussetzer"
            case .knock: return "Klopfregelung"
            case .cam: return "Nockenwelle"
            case .cooling: return "Kühlung"
            case .turbo: return "Turbo"
            case .egr: return "Abgasrückführung"
            case .secondaryAir: return "Sekundärluft"
            case .catalyst: return "Katalysator"
            case .evap: return "Tankentlüftung"
            case .idle: return "Leerlauf"
            case .voltage: return "Bordnetz"
            case .ecu: return "Motorsteuergerät"
            case .transmission: return "Getriebe"
            case .other: return "Motor & Abgas"
            case .dpf: return "Rußfilter"
            case .exhaustTemp: return "Abgastemperatur"
            }
        }

        var explanation: String {
            switch self {
            case .air: return "Die Motorsteuerung misst, wie viel Luft der Motor ansaugt. Stimmt der Messwert nicht, passt das Gemisch nicht mehr – oft durch verschmutzte Sensoren oder Falschluft (undichte Schläuche)."
            case .fuelTrim: return "Das Verhältnis von Luft zu Kraftstoff ist dauerhaft daneben. Typisch sind Falschluft, ein schwacher Kraftstoffdruck, verschmutzte Injektoren oder ein Messfehler."
            case .oxygen: return "Die Lambdasonde misst den Sauerstoff im Abgas, damit das Gemisch stimmt und der Kat richtig arbeitet. Gemeldet wird ein unplausibles Signal oder eine defekte Heizung."
            case .injection: return "Ein Einspritzventil oder seine Leitung wird elektrisch nicht richtig angesteuert."
            case .ignition: return "Eine Zündspule oder ihr Stromkreis meldet einen Fehler. Häufig ist die Spule selbst defekt."
            case .misfire: return "In mindestens einem Zylinder verbrennt das Gemisch nicht richtig. Das spürt man als Ruckeln; unverbrannter Kraftstoff kann den Katalysator überhitzen."
            case .knock: return "Der Klopfsensor überwacht unkontrollierte Verbrennung. Ist sein Signal gestört, nimmt der Motor zur Sicherheit Leistung zurück."
            case .cam: return "Die Lage oder Verstellung der Nockenwelle passt nicht zur Kurbelwelle. Ursachen reichen vom Sensor über Ölmangel bis zur gelängten Steuerkette."
            case .cooling: return "Die Kühlmitteltemperatur stimmt nicht oder wird falsch gemessen – z. B. durch Thermostat, Sensor oder zu wenig Kühlmittel."
            case .turbo: return "Der Ladedruck weicht vom Sollwert ab. Häufig: undichte Ladeluftschläuche, Wastegate oder Sensor."
            case .egr: return "Die Abgasrückführung (AGR) leitet einen Teil des Abgases zurück in den Motor. Der gemessene Durchfluss passt nicht – oft durch Verkokung."
            case .secondaryAir: return "Die Sekundärluftpumpe bläst beim Kaltstart Luft ins Abgas, damit der Kat schneller warm wird. Der Durchfluss stimmt nicht."
            case .catalyst: return "Der Katalysator reinigt das Abgas nicht mehr gut genug. Ursache kann der Kat selbst sein, aber auch eine Lambdasonde oder frühere Zündaussetzer."
            case .evap: return "Die Tankentlüftung fängt Benzindämpfe auf. Erkannt wurde ein Leck oder ein Ventilfehler – manchmal nur ein lockerer Tankdeckel."
            case .idle: return "Die Leerlaufdrehzahl oder die Geschwindigkeitsmessung ist unplausibel."
            case .voltage: return "Die Bordspannung war außerhalb des normalen Bereichs – typisch bei schwacher Batterie oder Problemen beim Laden."
            case .ecu: return "Das Motorsteuergerät meldet einen internen Fehler oder ein Kommunikationsproblem."
            case .transmission: return "Die Getriebesteuerung hat einen Fehler gemeldet, etwa bei Drehzahlsensoren oder der Wandlerkupplung."
            case .other: return "Genormter Fehler aus der Motor- oder Abgassteuerung."
            case .dpf: return "Der Dieselpartikelfilter (DPF) sammelt Ruß und brennt ihn regelmäßig ab (Regeneration). Gemeldet wird eine zu hohe Beladung, ein unplausibler Differenzdruck oder eine Regeneration, die nicht durchläuft – oft nach vielen Kurzstrecken."
            case .exhaustTemp: return "Die Abgastemperatursensoren überwachen den Partikelfilter und den Kat. Ohne gültigen Messwert kann der Motor keine Regeneration starten."
            }
        }

        var isDPF: Bool { self == .dpf || self == .exhaustTemp }

        var hint: String {
            switch self {
            case .misfire: return "Nicht mit Vollgas fahren. Zündspulen und Kerzen prüfen lassen – blinkt die Motorleuchte, möglichst gar nicht weiterfahren."
            case .cooling: return "Temperaturanzeige im Blick behalten und Kühlmittelstand bei kaltem Motor prüfen."
            case .catalyst: return "Erst Zündaussetzer und Lambdasonden ausschließen, bevor ein teurer Kat getauscht wird."
            case .evap: return "Tankdeckel prüfen und richtig schließen; kommt der Fehler wieder, Tankentlüftung prüfen lassen."
            case .voltage: return "Batterie und Ladespannung prüfen lassen."
            case .dpf: return "Eine längere Fahrt (20–30 min Landstraße/Autobahn, über ca. 2.000 U/min) hilft dem Filter oft beim Freibrennen. Im DPF-Tab siehst du live, ob eine Regeneration läuft."
            case .exhaustTemp: return "Sensor und Stecker prüfen lassen – solange er fehlt, wird der Rußfilter nicht regeneriert."
            default: return "Prüfen lassen. Kommt der Fehler nach dem Löschen sofort wieder, besteht die Ursache noch."
            }
        }
    }

    /// Häufige genormte OBD-II-Codes: Titel, Bereich, schwerwiegend?
    private static let obdTable: [String: (title: String, area: Area, severe: Bool)] = {
        var t: [String: (String, Area, Bool)] = [
            "P0010": ("Nockenwellenverstellung Einlass – Stromkreis (Bank 1)", .cam, false),
            "P0011": ("Nockenwelle Einlass – Steuerzeit zu früh (Bank 1)", .cam, false),
            "P0012": ("Nockenwelle Einlass – Steuerzeit zu spät (Bank 1)", .cam, false),
            "P0014": ("Nockenwelle Auslass – Steuerzeit zu früh (Bank 1)", .cam, false),
            "P0015": ("Nockenwelle Auslass – Steuerzeit zu spät (Bank 1)", .cam, false),
            "P0016": ("Kurbelwelle und Nockenwelle passen nicht zusammen (Bank 1)", .cam, true),
            "P0017": ("Kurbelwelle und Auslassnockenwelle passen nicht zusammen (Bank 1)", .cam, true),
            "P0030": ("Lambdasonden-Heizung Stromkreis (Bank 1, vor Kat)", .oxygen, false),
            "P0036": ("Lambdasonden-Heizung Stromkreis (Bank 1, nach Kat)", .oxygen, false),
            "P0087": ("Kraftstoffdruck zu niedrig", .injection, true),
            "P0088": ("Kraftstoffdruck zu hoch", .injection, true),
            "P0089": ("Kraftstoffdruckregler – Funktion", .injection, false),
            "P0100": ("Luftmassenmesser – Stromkreis", .air, false),
            "P0101": ("Luftmassenmesser – Messwert unplausibel", .air, false),
            "P0102": ("Luftmassenmesser – Signal zu niedrig", .air, false),
            "P0103": ("Luftmassenmesser – Signal zu hoch", .air, false),
            "P0106": ("Saugrohrdrucksensor – Messwert unplausibel", .air, false),
            "P0110": ("Ansauglufttemperatur-Sensor – Stromkreis", .air, false),
            "P0115": ("Kühlmitteltemperatur-Sensor – Stromkreis", .cooling, false),
            "P0116": ("Kühlmitteltemperatur – Messwert unplausibel", .cooling, false),
            "P0117": ("Kühlmitteltemperatur-Sensor – Signal zu niedrig", .cooling, false),
            "P0118": ("Kühlmitteltemperatur-Sensor – Signal zu hoch", .cooling, false),
            "P0120": ("Drosselklappensensor – Stromkreis", .air, false),
            "P0121": ("Drosselklappensensor – Messwert unplausibel", .air, false),
            "P0128": ("Kühlmittel erreicht Betriebstemperatur nicht (Thermostat)", .cooling, false),
            "P0130": ("Lambdasonde (Bank 1, vor Kat) – Stromkreis", .oxygen, false),
            "P0131": ("Lambdasonde (Bank 1, vor Kat) – Spannung zu niedrig", .oxygen, false),
            "P0132": ("Lambdasonde (Bank 1, vor Kat) – Spannung zu hoch", .oxygen, false),
            "P0133": ("Lambdasonde (Bank 1, vor Kat) – reagiert zu langsam", .oxygen, false),
            "P0134": ("Lambdasonde (Bank 1, vor Kat) – keine Aktivität", .oxygen, false),
            "P0135": ("Lambdasonden-Heizung (Bank 1, vor Kat)", .oxygen, false),
            "P0136": ("Lambdasonde (Bank 1, nach Kat) – Stromkreis", .oxygen, false),
            "P0137": ("Lambdasonde (Bank 1, nach Kat) – Spannung zu niedrig", .oxygen, false),
            "P0138": ("Lambdasonde (Bank 1, nach Kat) – Spannung zu hoch", .oxygen, false),
            "P0139": ("Lambdasonde (Bank 1, nach Kat) – reagiert zu langsam", .oxygen, false),
            "P0141": ("Lambdasonden-Heizung (Bank 1, nach Kat)", .oxygen, false),
            "P0171": ("Gemisch zu mager (Bank 1)", .fuelTrim, false),
            "P0172": ("Gemisch zu fett (Bank 1)", .fuelTrim, false),
            "P0174": ("Gemisch zu mager (Bank 2)", .fuelTrim, false),
            "P0175": ("Gemisch zu fett (Bank 2)", .fuelTrim, false),
            "P0191": ("Kraftstoffdrucksensor – Messwert unplausibel", .injection, false),
            "P0217": ("Motor überhitzt", .cooling, true),
            "P0219": ("Motor hat überdreht", .other, true),
            "P0234": ("Ladedruck zu hoch (Overboost)", .turbo, true),
            "P0236": ("Ladedrucksensor – Messwert unplausibel", .turbo, false),
            "P0299": ("Ladedruck zu niedrig", .turbo, false),
            "P0300": ("Zündaussetzer – mehrere/wechselnde Zylinder", .misfire, true),
            "P0325": ("Klopfsensor 1 – Stromkreis (Bank 1)", .knock, false),
            "P0327": ("Klopfsensor 1 – Signal zu niedrig (Bank 1)", .knock, false),
            "P0335": ("Kurbelwellensensor – Stromkreis", .cam, true),
            "P0340": ("Nockenwellensensor – Stromkreis (Bank 1)", .cam, false),
            "P0400": ("Abgasrückführung – Durchfluss", .egr, false),
            "P0401": ("Abgasrückführung – Durchfluss zu gering", .egr, false),
            "P0402": ("Abgasrückführung – Durchfluss zu hoch", .egr, false),
            "P0403": ("Abgasrückführung – Stromkreis", .egr, false),
            "P0410": ("Sekundärluftsystem", .secondaryAir, false),
            "P0411": ("Sekundärluft – Durchfluss falsch", .secondaryAir, false),
            "P0491": ("Sekundärluft – zu wenig Durchfluss (Bank 1)", .secondaryAir, false),
            "P0420": ("Katalysator – Wirkungsgrad zu niedrig (Bank 1)", .catalyst, false),
            "P0430": ("Katalysator – Wirkungsgrad zu niedrig (Bank 2)", .catalyst, false),
            "P0440": ("Tankentlüftung – Fehlfunktion", .evap, false),
            "P0441": ("Tankentlüftung – Spülstrom falsch", .evap, false),
            "P0442": ("Tankentlüftung – kleines Leck", .evap, false),
            "P0455": ("Tankentlüftung – großes Leck", .evap, false),
            "P0456": ("Tankentlüftung – sehr kleines Leck", .evap, false),
            "P0480": ("Kühlerlüfter 1 – Steuerkreis", .cooling, false),
            "P0500": ("Geschwindigkeitssensor", .idle, false),
            "P0505": ("Leerlaufregelung", .idle, false),
            "P0506": ("Leerlaufdrehzahl zu niedrig", .idle, false),
            "P0507": ("Leerlaufdrehzahl zu hoch", .idle, false),
            "P0520": ("Öldrucksensor/-schalter – Stromkreis", .other, true),
            "P0524": ("Öldruck zu niedrig", .other, true),
            "P0562": ("Bordspannung zu niedrig", .voltage, false),
            "P0563": ("Bordspannung zu hoch", .voltage, false),
            "P0597": ("Thermostat-Heizung – Stromkreis offen", .cooling, false),
            "P0600": ("Kommunikation des Motorsteuergeräts gestört", .ecu, false),
            "P0601": ("Motorsteuergerät – Speicherfehler (Prüfsumme)", .ecu, true),
            "P0603": ("Motorsteuergerät – Dauerspeicher-Fehler", .ecu, false),
            "P0605": ("Motorsteuergerät – Programmspeicher-Fehler", .ecu, true),
            "P0700": ("Getriebesteuerung meldet einen Fehler", .transmission, false),
            "P0715": ("Turbinendrehzahl-Sensor (Getriebe)", .transmission, false),
            "P0720": ("Abtriebsdrehzahl-Sensor (Getriebe)", .transmission, false),
            "P0741": ("Wandlerkupplung – Funktion", .transmission, false),
            "P2002": ("Partikelfilter – Wirkungsgrad unter Schwellwert (Bank 1)", .dpf, false),
            "P2003": ("Partikelfilter – Wirkungsgrad unter Schwellwert (Bank 2)", .dpf, false),
            "P242F": ("Partikelfilter – zu viel Asche (Bank 1)", .dpf, false),
            "P244A": ("Partikelfilter – Differenzdruck zu niedrig (Bank 1)", .dpf, false),
            "P244B": ("Partikelfilter – Differenzdruck zu hoch (Bank 1)", .dpf, false),
            "P2452": ("Differenzdrucksensor Partikelfilter – Stromkreis", .dpf, false),
            "P2453": ("Differenzdrucksensor Partikelfilter – Messbereich/Funktion", .dpf, false),
            "P2454": ("Differenzdrucksensor Partikelfilter – Signal zu niedrig", .dpf, false),
            "P2455": ("Differenzdrucksensor Partikelfilter – Signal zu hoch", .dpf, false),
            "P2458": ("Partikelfilter – Regeneration dauert zu lange", .dpf, false),
            "P2459": ("Partikelfilter – Regeneration zu häufig", .dpf, false),
            "P2463": ("Partikelfilter – zu viel Ruß (Bank 1)", .dpf, false),
            "P0544": ("Abgastemperatursensor 1 – Stromkreis (Bank 1)", .exhaustTemp, false),
            "P0545": ("Abgastemperatursensor 1 – Signal zu niedrig (Bank 1)", .exhaustTemp, false),
            "P0546": ("Abgastemperatursensor 1 – Signal zu hoch (Bank 1)", .exhaustTemp, false),
            "P2031": ("Abgastemperatursensor 2 – Stromkreis (Bank 1)", .exhaustTemp, false),
            "P2032": ("Abgastemperatursensor 2 – Signal zu niedrig (Bank 1)", .exhaustTemp, false),
            "P2033": ("Abgastemperatursensor 2 – Signal zu hoch (Bank 1)", .exhaustTemp, false),
            "P2187": ("Gemisch im Leerlauf zu mager (Bank 1)", .fuelTrim, false),
            "P2188": ("Gemisch im Leerlauf zu fett (Bank 1)", .fuelTrim, false),
            "P2195": ("Lambdasonde (Bank 1) – Signal hängt auf „mager“", .oxygen, false),
            "P2196": ("Lambdasonde (Bank 1) – Signal hängt auf „fett“", .oxygen, false),
            "P2270": ("Lambdasonde nach Kat – Signal hängt auf „mager“", .oxygen, false),
            "P2271": ("Lambdasonde nach Kat – Signal hängt auf „fett“", .oxygen, false),
        ]
        for cylinder in 1...12 {
            let n = String(format: "%02d", cylinder)
            t["P03\(n)"] = ("Zündaussetzer Zylinder \(cylinder)", .misfire, true)
            t["P02\(n)"] = ("Einspritzventil Zylinder \(cylinder) – Stromkreis", .injection, false)
        }
        for coil in 1...8 {
            t["P035\(coil)"] = ("Zündspule \(coil) – Stromkreis", .ignition, false)
        }
        return t
    }()

    private static func obdInfo(_ fault: FaultCode) -> FaultInfo {
        let code = fault.code.uppercased()
        let url = search("OBD2 Fehlercode \(code) Bedeutung")
        if let entry = obdTable[code] {
            return FaultInfo(code: code, title: entry.title, area: entry.area.name,
                             explanation: entry.area.explanation, hint: entry.area.hint,
                             severity: entry.severe ? .severe : .fault, searchURL: url, isExact: true,
                             isDPF: entry.area.isDPF)
        }
        let area = obdRange(code)
        let generic = code.count == 5 && code.dropFirst().first == "0"
        let title = generic ? "genormter Fehler" : "herstellerspezifischer Fehler"
        return FaultInfo(code: code, title: title, area: area.name,
                         explanation: area.explanation + (area.isDPF ? "" : " Der genaue Wortlaut zu \(code) steht nicht in der App – der Web-Knopf sucht danach."),
                         hint: area.hint, severity: area == .misfire ? .severe : .fault, searchURL: url, isExact: false,
                         isDPF: area.isDPF)
    }

    /// Ordnet unbekannte Codes über den genormten Nummernbereich ein.
    private static func obdRange(_ code: String) -> Area {
        guard code.count == 5, let letter = code.first else { return .other }
        if letter != "P" { return .other }
        let digits = code.dropFirst(2)
        guard let group = digits.first else { return .other }
        // P2440–P246F: Partikelfilter, Differenzdruck, Ruß/Asche (genormt)
        if code.hasPrefix("P244") || code.hasPrefix("P245") || code.hasPrefix("P246") { return .dpf }
        switch group {
        case "0": return .fuelTrim
        case "1": return .air
        case "2": return .injection
        case "3": return code.hasPrefix("P030") ? .misfire : .ignition
        case "4": return .egr
        case "5": return .idle
        case "6": return .ecu
        case "7", "8", "9": return .transmission
        default: return .other
        }
    }

    // MARK: - BMW-Herstellercodes

    private struct ECUArea {
        let name: String
        let explanation: String
        let hint: String
        let safetyCritical: Bool
    }

    private static let ecuAreas: [UInt8: ECUArea] = [
        0x01: ECUArea(name: "Airbag",
                      explanation: "Fehler im Rückhaltesystem (Airbags, Gurtstraffer, Sitzbelegung). Im Ernstfall lösen betroffene Teile womöglich nicht aus.",
                      hint: "Nicht einfach löschen – in der Werkstatt prüfen lassen. Nicht selbst an Airbag-Steckern arbeiten.",
                      safetyCritical: true),
        0x10: ECUArea(name: "Gateway",
                      explanation: "Das Gateway verbindet die Datenbusse im Auto. Einträge hier sind oft Folgefehler, z. B. nach einer leeren Batterie.",
                      hint: "Oft harmlos. Erst Batterie prüfen, dann löschen und schauen, ob er wiederkommt.",
                      safetyCritical: false),
        0x12: ECUArea(name: "Motor",
                      explanation: "Die Motorsteuerung (DME/DDE) hat etwas bemerkt – von Sensoren über Zündung bis Abgasreinigung.",
                      hint: "Leuchtet die Motorkontrollleuchte, bald prüfen lassen.",
                      safetyCritical: false),
        0x18: ECUArea(name: "Getriebe",
                      explanation: "Die Getriebesteuerung (EGS) meldet einen Fehler, z. B. bei Sensoren, Ölstand oder Schaltvorgängen.",
                      hint: "Bei Ruckeln oder Notlauf vorsichtig fahren und prüfen lassen.",
                      safetyCritical: false),
        0x1C: ECUArea(name: "Fahrdynamik",
                      explanation: "Das Fahrdynamik-Modul (ICM) liefert Daten für Stabilitäts- und Assistenzsysteme.",
                      hint: "Assistenzsysteme können eingeschränkt sein – prüfen lassen.",
                      safetyCritical: true),
        0x29: ECUArea(name: "Bremsen",
                      explanation: "Fehler in der Bremsregelung (DSC/ABS) – z. B. Raddrehzahlsensor oder Bremsbelagverschleiß. ABS oder DSC können ausfallen.",
                      hint: "Nicht einfach löschen – Bremsen prüfen lassen.",
                      safetyCritical: true),
        0x30: ECUArea(name: "Lenkung",
                      explanation: "Fehler in der elektrischen Servolenkung (EPS). Die Lenkunterstützung kann eingeschränkt sein.",
                      hint: "Nicht einfach löschen – Lenkung prüfen lassen.",
                      safetyCritical: true),
        0x40: ECUArea(name: "Karosserie",
                      explanation: "Das Karosseriesteuergerät (FEM/BDC) regelt Zentralverriegelung, Fenster, Wischer, Innenlicht und mehr.",
                      hint: "Meist Komfortfunktionen. Löschen und beobachten, ob er wiederkommt.",
                      safetyCritical: false),
        0x56: ECUArea(name: "Dach",
                      explanation: "Steuergerät für Dachfunktionen wie Schiebedach und Innenleuchten.",
                      hint: "Meist Komfortfunktionen.", safetyCritical: false),
        0x5D: ECUArea(name: "Kamera",
                      explanation: "Kamera-Assistenz (KAFAS): Spurhalte- oder Verkehrszeichenerkennung.",
                      hint: "Assistenten können eingeschränkt sein. Frontscheibe vor der Kamera sauber halten.",
                      safetyCritical: false),
        0x60: ECUArea(name: "Instrumente",
                      explanation: "Das Kombiinstrument meldet einen Fehler oder hat Meldungen anderer Steuergeräte gespeichert.",
                      hint: "Oft Folgefehler. Löschen und beobachten.", safetyCritical: false),
        0x63: ECUArea(name: "Headunit",
                      explanation: "Navigation, Radio, Bluetooth oder Bildschirm haben einen Eintrag gespeichert.",
                      hint: "Meist harmlos.", safetyCritical: false),
        0x64: ECUArea(name: "Parkhilfe",
                      explanation: "Die Parkhilfe (PDC) meldet z. B. einen verschmutzten oder defekten Sensor.",
                      hint: "Sensoren reinigen; kommt er wieder, Sensor prüfen.", safetyCritical: false),
        0x67: ECUArea(name: "Controller",
                      explanation: "Der iDrive-Controller hat einen Eintrag gespeichert.",
                      hint: "Meist harmlos.", safetyCritical: false),
        0x6D: ECUArea(name: "Sitze",
                      explanation: "Sitzsteuergerät: Verstellung, Memory oder Heizung.",
                      hint: "Komfortfunktion.", safetyCritical: false),
        0x72: ECUArea(name: "Licht",
                      explanation: "Das Lichtmodul (FRM/REM) überwacht Scheinwerfer, Blinker und Rückleuchten – z. B. eine defekte Lampe oder Nachrüst-Leuchten ohne passende Codierung.",
                      hint: "Lampen prüfen. Bei Nachrüst-Leuchten kann der Eintrag dauerhaft bleiben.",
                      safetyCritical: false),
        0x78: ECUArea(name: "Klima",
                      explanation: "Die Klimaautomatik (IHKA) meldet z. B. einen Sensor- oder Stellmotorfehler.",
                      hint: "Komfortfunktion.", safetyCritical: false),
    ]

    private static func bmwInfo(_ fault: FaultCode, ecu: UInt8) -> FaultInfo {
        let ecuName = FaultScanner.name(for: ecu)
        let short = ecuName.components(separatedBy: " · ").first ?? ecuName
        let area = ecuAreas[ecu] ?? ECUArea(
            name: short,
            explanation: "Ein Steuergerät hat einen Eintrag gespeichert.",
            hint: "Prüfen lassen, falls im Auto etwas auffällt.",
            safetyCritical: false)
        let severe = area.safetyCritical || (fault.isActive && fault.warningLamp)
        return FaultInfo(
            code: fault.code,
            title: "BMW-Fehler aus \(short)",
            area: area.name,
            explanation: area.explanation + " Den genauen Wortlaut zu diesem BMW-Code kennt nur die BMW-Datenbank – der Web-Knopf sucht danach.",
            hint: area.hint,
            severity: severe ? .severe : .fault,
            searchURL: search("BMW Fehlercode \(fault.code) \(short)"),
            isExact: false)
    }

    private static func search(_ query: String) -> URL {
        var components = URLComponents(string: "https://www.google.com/search")!
        components.queryItems = [URLQueryItem(name: "q", value: query)]
        return components.url!
    }
}
