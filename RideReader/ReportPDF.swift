import SwiftUI

/// Mehrseitiger PDF-Fehlerbericht (A4) – hell und druckbar, z. B. für die Werkstatt.
@MainActor
enum ReportPDF {
    static let pageSize = CGSize(width: 595, height: 842)   // A4 in Punkt
    static let margin: CGFloat = 40

    /// Eine Zeile im Bericht: Steuergeräte-Überschrift oder Fehler
    enum Item: Identifiable {
        case ecu(name: String, address: String, count: Int)
        case fault(code: String, info: FaultInfo, status: String, km: Int?)
        case healthy(names: [String])

        var id: String {
            switch self {
            case .ecu(let name, let address, _): return "e\(address)\(name)"
            case .fault(let code, let info, _, _): return "f\(code)\(info.area)\(info.title)"
            case .healthy: return "healthy"
            }
        }

        /// Geschätzte Höhe für den Seitenumbruch
        var height: CGFloat {
            switch self {
            case .ecu: return 34
            case .fault(_, let info, _, _):
                let lines = CGFloat((info.explanation.count + info.hint.count) / 88 + 2)
                return 52 + lines * 13
            case .healthy(let names): return 40 + CGFloat(names.count / 3 + 1) * 14
            }
        }
    }

    /// Erzeugt die PDF-Datei im temporären Ordner und gibt ihre Adresse zurück.
    static func make(scanner: FaultScanner, edition: String?) -> URL? {
        var items: [Item] = []
        for result in scanner.results where !result.faults.isEmpty {
            items.append(.ecu(name: result.name, address: result.hexAddress, count: result.faults.count))
            for fault in result.faults {
                items.append(.fault(code: fault.code, info: FaultCatalog.info(for: fault, ecu: result.address),
                                    status: fault.statusText, km: fault.mileage))
            }
        }
        if !scanner.obdCodes.isEmpty {
            items.append(.ecu(name: "OBD-II · Motor & Abgas", address: "genormt", count: scanner.obdCodes.count))
            for fault in scanner.obdCodes {
                items.append(.fault(code: fault.code, info: FaultCatalog.info(for: fault, ecu: nil), status: fault.statusText, km: nil))
            }
        }
        let healthy = scanner.results.filter { $0.faults.isEmpty && $0.error == nil }.map(\.name)
        if !healthy.isEmpty { items.append(.healthy(names: healthy)) }

        // Seiten füllen (erste Seite hat den großen Kopf)
        var pages: [[Item]] = [[]]
        var used: CGFloat = 0
        for item in items {
            let available = pageSize.height - margin * 2 - (pages.count == 1 ? 250 : 70) - 30
            if used + item.height > available, !(pages.last?.isEmpty ?? true) {
                pages.append([])
                used = 0
            }
            pages[pages.count - 1].append(item)
            used += item.height
        }

        let date = Date()
        let stamp = date.formatted(.iso8601.year().month().day())
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("RideReader-Fehlerbericht-\(stamp).pdf")
        var box = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &box, nil) else { return nil }

        let all = scanner.results.flatMap { r in r.faults.map { FaultCatalog.info(for: $0, ecu: r.address) } }
            + scanner.obdCodes.map { FaultCatalog.info(for: $0, ecu: nil) }
        let summary = Summary(total: all.count, severe: all.filter { $0.severity == .severe }.count,
                              ecus: scanner.results.count, vin: scanner.vin, km: scanner.highestStoredMileage,
                              isDemo: scanner.isDemo, edition: edition, date: date)

        for (index, page) in pages.enumerated() {
            let view = ReportPage(items: page, page: index + 1, pageCount: pages.count, summary: index == 0 ? summary : nil, date: date)
                .frame(width: pageSize.width, height: pageSize.height)
            let renderer = ImageRenderer(content: view)
            renderer.render { _, draw in
                context.beginPDFPage(nil)
                draw(context)
                context.endPDFPage()
            }
        }
        context.closePDF()
        return url
    }

    struct Summary {
        let total: Int
        let severe: Int
        let ecus: Int
        let vin: String?
        let km: Int?
        let isDemo: Bool
        let edition: String?
        let date: Date
    }
}

// MARK: - Seite

private struct ReportPage: View {
    let items: [ReportPDF.Item]
    let page: Int
    let pageCount: Int
    let summary: ReportPDF.Summary?
    let date: Date

    private let ink = Color(red: 0.08, green: 0.09, blue: 0.12)
    private let muted = Color(red: 0.42, green: 0.44, blue: 0.5)
    private let orange = Color(red: 0.93, green: 0.5, blue: 0.05)
    private let red = Color(red: 0.86, green: 0.12, blue: 0.18)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Farbband oben im Design der App
            LinearGradient(colors: Theme.brandColors, startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .padding(.horizontal, -ReportPDF.margin)
                .padding(.top, -ReportPDF.margin)
                .padding(.bottom, ReportPDF.margin - 6)

            if let summary { header(summary) } else { smallHeader }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(items) { item in row(item) }
            }

            Spacer(minLength: 0)

            HStack {
                Text("Erstellt mit RideReader · Löschen ersetzt keine Reparatur.")
                Spacer()
                Text("Seite \(page) von \(pageCount)")
            }
            .font(.system(size: 8.5, weight: .medium))
            .foregroundStyle(muted)
        }
        .padding(ReportPDF.margin)
        .frame(width: ReportPDF.pageSize.width, height: ReportPDF.pageSize.height, alignment: .topLeading)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private func header(_ s: ReportPDF.Summary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("RIDEREADER")
                        .font(.system(size: 22, weight: .black).width(.expanded))
                        .italic()
                        .foregroundStyle(LinearGradient(colors: [ink, Theme.accentDeep, Theme.violet], startPoint: .leading, endPoint: .trailing))
                    if let edition = s.edition {
                        Text(edition)
                            .font(.system(size: 9, weight: .light))
                            .tracking(1.6)
                            .foregroundStyle(muted)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Fehlerbericht").font(.system(size: 16, weight: .bold)).foregroundStyle(ink)
                    Text(s.date.formatted(date: .long, time: .shortened)).font(.system(size: 9.5)).foregroundStyle(muted)
                }
            }

            if s.isDemo {
                Text("BEISPIELDATEN – kein echtes Fahrzeug")
                    .font(.system(size: 9, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(orange)
            }

            HStack(spacing: 10) {
                stat("\(s.total)", "Fehler", s.total == 0 ? Color.green : (s.severe > 0 ? red : orange))
                stat("\(s.severe)", "schwerwiegend", s.severe > 0 ? red : muted)
                stat("\(s.ecus)", "Steuergeräte", ink)
                if let km = s.km {
                    stat(km.formatted(.number.locale(Locale(identifier: "de_DE"))), "km zuletzt gespeichert", ink)
                }
            }

            if let vin = s.vin {
                Text("FIN: \(vin)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(ink)
            }

            Rectangle().fill(muted.opacity(0.25)).frame(height: 1).padding(.bottom, 6)
        }
        .padding(.bottom, 8)
    }

    private var smallHeader: some View {
        HStack {
            Text("RIDEREADER").font(.system(size: 12, weight: .black).width(.expanded)).italic().foregroundStyle(ink)
            Spacer()
            Text("Fehlerbericht · \(date.formatted(date: .abbreviated, time: .shortened))")
                .font(.system(size: 9.5)).foregroundStyle(muted)
        }
        .padding(.bottom, 16)
    }

    private func stat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.system(size: 20, weight: .heavy)).foregroundStyle(color)
            Text(label).font(.system(size: 8.5, weight: .semibold)).foregroundStyle(muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.95, green: 0.96, blue: 0.98)))
    }

    @ViewBuilder
    private func row(_ item: ReportPDF.Item) -> some View {
        switch item {
        case .ecu(let name, let address, let count):
            HStack {
                Text(name).font(.system(size: 12.5, weight: .bold)).foregroundStyle(ink)
                Text("\(address) · \(count) \(count == 1 ? "Eintrag" : "Einträge")")
                    .font(.system(size: 9.5, weight: .medium)).foregroundStyle(muted)
                Spacer()
            }
            .padding(.top, 12)
            .padding(.bottom, 6)
        case .fault(let code, let info, let status, let km):
            let color = info.severity == .severe ? red : orange
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(code).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundStyle(color)
                        Text(info.severity.label.uppercased()).font(.system(size: 7.5, weight: .heavy)).tracking(0.8).foregroundStyle(color)
                        Text(status).font(.system(size: 8.5, weight: .medium)).foregroundStyle(muted)
                        if let km {
                            Text("bei \(km.formatted(.number.locale(Locale(identifier: "de_DE")))) km")
                                .font(.system(size: 8.5, weight: .semibold)).foregroundStyle(muted)
                        }
                    }
                    Text(info.headline).font(.system(size: 10.5, weight: .bold)).foregroundStyle(ink)
                    Text(info.explanation).font(.system(size: 9)).foregroundStyle(ink.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tipp: \(info.hint)").font(.system(size: 9, weight: .medium)).foregroundStyle(muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 6)
        case .healthy(let names):
            VStack(alignment: .leading, spacing: 4) {
                Text("Ohne Fehler (\(names.count))").font(.system(size: 11, weight: .bold)).foregroundStyle(Color.green)
                Text(names.joined(separator: " · ")).font(.system(size: 8.5)).foregroundStyle(muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 14)
        }
    }
}
