import SwiftUI

/// Eine gespeicherte Kontrolle.
struct ScanRecord: Codable, Identifiable, Equatable {
    struct Entry: Codable, Hashable {
        let address: UInt8          // 0x00 = OBD-II
        let ecu: String
        let code: String
        let severe: Bool

        var key: String { "\(address):\(code)" }
    }

    var id = UUID()
    let date: Date
    let faults: [Entry]
    let highestKm: Int?

    var keys: Set<String> { Set(faults.map(\.key)) }
}

/// Verlauf aller Kontrollen (nur auf dem Gerät gespeichert). Vergleicht die aktuelle mit der vorherigen Kontrolle.
@MainActor
final class FaultHistory: ObservableObject {
    @Published private(set) var records: [ScanRecord] = []
    /// Die Kontrolle vor der aktuellen – Grundlage für „neu“ und „verschwunden“
    @Published private(set) var baseline: ScanRecord?

    private let storageKey = "faultHistory"
    private let maxRecords = 60

    init() {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([ScanRecord].self, from: data) {
            records = decoded
        }
    }

    /// Speichert eine abgeschlossene, echte Kontrolle.
    func record(_ scanner: FaultScanner) {
        guard !scanner.isDemo, scanner.abortReason == nil, !scanner.results.isEmpty else { return }
        var entries: [ScanRecord.Entry] = []
        for result in scanner.results {
            for fault in result.faults {
                let info = FaultCatalog.info(for: fault, ecu: result.address)
                entries.append(.init(address: result.address, ecu: result.name, code: fault.code, severe: info.severity == .severe))
            }
        }
        for fault in scanner.obdCodes {
            let info = FaultCatalog.info(for: fault, ecu: nil)
            entries.append(.init(address: FaultScanner.obdAddress, ecu: "OBD-II", code: fault.code, severe: info.severity == .severe))
        }
        baseline = records.first
        records.insert(ScanRecord(date: Date(), faults: entries, highestKm: scanner.highestStoredMileage), at: 0)
        if records.count > maxRecords { records.removeLast(records.count - maxRecords) }
        save()
    }

    func isNew(address: UInt8, code: String) -> Bool {
        guard let baseline else { return false }
        return !baseline.keys.contains("\(address):\(code)")
    }

    /// Vergleich der neuesten Kontrolle mit der davor: (neu, verschwunden)
    var comparison: (new: Int, gone: Int)? {
        guard let baseline, let current = records.first else { return nil }
        return (current.keys.subtracting(baseline.keys).count, baseline.keys.subtracting(current.keys).count)
    }

    func clear() {
        records = []
        baseline = nil
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(records) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}

/// Liste der bisherigen Kontrollen (Einstellungen → Werkzeuge → Fehler-Verlauf).
struct HistoryView: View {
    @EnvironmentObject private var history: FaultHistory
    @State private var expanded: UUID?
    @State private var confirmClear = false

    var body: some View {
        ZStack(alignment: .top) {
            AmbientBackground(tint: Theme.violet)
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 6) {
                        Text("Verlauf")
                            .font(Theme.display(34))
                            .foregroundStyle(Theme.titleGradient)
                        Text("Was kam dazu, was ist weg?")
                            .font(Theme.rounded(15, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.top, 12)

                    if history.records.isEmpty {
                        InfoCard(icon: "clock.arrow.circlepath", color: Theme.violet, title: "Noch keine Kontrolle gespeichert",
                                 text: "Jede Kontrolle mit verbundenem Stecker landet hier automatisch.")
                    }

                    ForEach(Array(history.records.enumerated()), id: \.element.id) { index, record in
                        let previous = index + 1 < history.records.count ? history.records[index + 1] : nil
                        recordCard(record, previous: previous)
                    }

                    if !history.records.isEmpty {
                        Button(role: .destructive) {
                            confirmClear = true
                        } label: {
                            Label("Verlauf löschen", systemImage: "trash")
                                .font(Theme.rounded(14, weight: .bold))
                                .foregroundStyle(Theme.severe)
                        }
                        .padding(.top, 6)
                    }
                }
                .pageWidth()
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
        }
        .foregroundStyle(.white)
        .confirmationDialog("Gesamten Verlauf löschen?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Verlauf löschen", role: .destructive) { history.clear() }
        } message: {
            Text("Das betrifft nur die gespeicherte Liste in der App, nicht das Auto.")
        }
    }

    private func recordCard(_ record: ScanRecord, previous: ScanRecord?) -> some View {
        let added = previous.map { record.keys.subtracting($0.keys) } ?? []
        let gone = previous.map { $0.keys.subtracting(record.keys) } ?? []
        let severe = record.faults.contains { $0.severe }
        let color: Color = record.faults.isEmpty ? Theme.ok : severe ? Theme.severe : Theme.fault
        let isOpen = expanded == record.id
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { expanded = isOpen ? nil : record.id }
            } label: {
                HStack(spacing: 12) {
                    Text("\(record.faults.count)")
                        .font(Theme.display(28))
                        .foregroundStyle(color)
                        .frame(minWidth: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.date.formatted(date: .abbreviated, time: .shortened))
                            .font(Theme.rounded(15, weight: .bold))
                        HStack(spacing: 6) {
                            if previous != nil {
                                if !added.isEmpty { chip("+\(added.count) neu", Theme.fault) }
                                if !gone.isEmpty { chip("−\(gone.count) weg", Theme.ok) }
                                if added.isEmpty && gone.isEmpty { chip("unverändert", .gray) }
                            }
                            if let km = record.highestKm {
                                chip("\(km.formatted(.number.locale(Locale(identifier: "de_DE")))) km", Theme.violet)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(isOpen ? 180 : 0))
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
            .buttonStyle(.plain)

            if isOpen {
                VStack(alignment: .leading, spacing: 6) {
                    if record.faults.isEmpty {
                        Text("Keine Fehler – alles sauber.")
                            .font(Theme.rounded(13, weight: .medium))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    ForEach(record.faults, id: \.self) { entry in
                        HStack {
                            Text(entry.code)
                                .font(.system(size: 13, weight: .heavy, design: .monospaced))
                                .foregroundStyle(entry.severe ? Theme.severe : Theme.fault)
                            Text(entry.ecu)
                                .font(Theme.rounded(13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.75))
                                .lineLimit(1)
                            Spacer(minLength: 0)
                            if added.contains(entry.key) { chip("NEU", Theme.magenta) }
                        }
                    }
                    if !gone.isEmpty, let previous {
                        Text("Verschwunden:")
                            .font(Theme.rounded(12, weight: .bold))
                            .foregroundStyle(Theme.ok)
                            .padding(.top, 4)
                        ForEach(previous.faults.filter { gone.contains($0.key) }, id: \.self) { entry in
                            Text("\(entry.code) · \(entry.ecu)")
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.5))
                                .strikethrough()
                        }
                    }
                }
                .transition(.blurFade)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: color)
    }

    private func chip(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(Theme.rounded(11, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.16)))
            .lineLimit(1)
            .fixedSize()
    }
}
