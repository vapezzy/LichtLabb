import SwiftUI

/// Eine selbst hinterlegte Service-Routine (Befehl aus einem echten Mitschnitt, z. B. ISTA/Tool32-Trace).
struct ServiceRoutine: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var ecu: UInt8
    /// Vorher in die erweiterte Diagnosesitzung (10 03) wechseln
    var extendedSession: Bool
    /// Optional: Lesebefehl (22 xx xx), dessen Antwort vorher als Sicherung gespeichert wird
    var backupHex: String
    var commandHex: String
    var lastBackup: String?
    var lastResult: String?
    var lastRun: Date?

    /// Erlaubte Dienste: lesen (22), schreiben per Kennung (2E), Routine (31). Kein Flashen, kein Reset, kein Sicherheitszugang.
    static let allowedServices: [UInt8: String] = [0x22: "Lesen", 0x2E: "Schreiben", 0x31: "Routine"]

    static func validate(_ hex: String) -> String? {
        guard let bytes = Hex.bytes(hex), !bytes.isEmpty else { return "Ungültige Hex-Eingabe" }
        guard let service = bytes.first, allowedServices[service] != nil else {
            return "Nur Lesen (22), Schreiben (2E) oder Routine (31) erlaubt"
        }
        if service == 0x31, bytes.count < 4 { return "Routine braucht mindestens 31 01 xx xx" }
        if service != 0x31, bytes.count < 3 { return "Kennung fehlt (2 Byte)" }
        return nil
    }
}

@MainActor
final class RoutineStore: ObservableObject {
    @Published var routines: [ServiceRoutine] = []
    private let key = "serviceRoutines"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([ServiceRoutine].self, from: data) {
            routines = decoded
        }
    }

    func save() {
        if let data = try? JSONEncoder().encode(routines) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    func upsert(_ routine: ServiceRoutine) {
        if let i = routines.firstIndex(where: { $0.id == routine.id }) { routines[i] = routine } else { routines.append(routine) }
        save()
    }

    func delete(_ routine: ServiceRoutine) {
        routines.removeAll { $0.id == routine.id }
        save()
    }
}

/// Routinen-Bereich im Service-Tab.
struct RoutineSection: View {
    @EnvironmentObject private var store: RoutineStore
    @EnvironmentObject private var session: ELMSession

    @State private var editing: ServiceRoutine?
    @State private var running: UUID?
    @State private var checks: [Check] = []
    @State private var confirm: ServiceRoutine?

    struct Check: Identifiable {
        let id = UUID()
        let title: String
        let ok: Bool
        let detail: String
    }

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 4) {
                Text("Routinen")
                    .font(Theme.display(26))
                    .foregroundStyle(Theme.titleGradient)
                Text("Eigene Service-Befehle aus einem echten Mitschnitt")
                    .font(Theme.rounded(12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.55))
            }

            InfoCard(icon: "exclamationmark.shield.fill", color: Theme.fault, title: "Auf eigene Verantwortung",
                     text: "Hier nur Befehle eintragen, die du aus einem Mitschnitt (ISTA, Tool32-Trace, Carly) für genau dein Steuergerät hast. Geratene Befehle können Lernwerte verstellen.")

            if !session.isInitialized {
                InfoCard(icon: "cable.connector.slash", color: Theme.violet, title: "Kein Stecker verbunden",
                         text: "Routinen lassen sich anlegen, ausgeführt werden sie nur mit verbundenem Adapter.")
            }

            if !checks.isEmpty { checksCard }

            ForEach(store.routines) { routine in
                routineCard(routine)
            }

            Button {
                Haptics.tap()
                editing = ServiceRoutine(name: "", ecu: 0x12, extendedSession: true, backupHex: "", commandHex: "")
            } label: {
                Label("Neue Routine", systemImage: "plus")
                    .font(Theme.rounded(15, weight: .bold))
                    .foregroundStyle(Theme.onButton)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Capsule().fill(Theme.buttonGradient))
            }
            .buttonStyle(PressableStyle())
        }
        .sheet(item: $editing) { routine in
            RoutineEditor(routine: routine) { store.upsert($0) }
        }
        .alert(item: $confirm) { routine in
            Alert(title: Text("„\(routine.name)“ ausführen?"),
                  message: Text("Steuergerät \(String(format: "0x%02X", routine.ecu))\nBefehl: \(routine.commandHex.uppercased())"),
                  primaryButton: .destructive(Text("Senden")) { Task { await execute(routine) } },
                  secondaryButton: .cancel(Text("Abbrechen")))
        }
    }

    private func routineCard(_ routine: ServiceRoutine) -> some View {
        let service = Hex.bytes(routine.commandHex)?.first.flatMap { ServiceRoutine.allowedServices[$0] } ?? "?"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(routine.name.isEmpty ? "Ohne Namen" : routine.name)
                        .font(Theme.rounded(16, weight: .bold))
                    Text("\(service) · Steuergerät \(String(format: "0x%02X", routine.ecu))\(routine.extendedSession ? " · Service-Sitzung" : "")")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Menu {
                    Button("Bearbeiten") { editing = routine }
                    Button("Löschen", role: .destructive) { store.delete(routine) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 20))
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            Text(routine.commandHex.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.accent)
            if let backup = routine.lastBackup {
                Text("Sicherung: \(backup)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
                    .textSelection(.enabled)
            }
            if let result = routine.lastResult, let date = routine.lastRun {
                Text("\(date.formatted(date: .abbreviated, time: .shortened)): \(result)")
                    .font(Theme.rounded(12, weight: .medium))
                    .foregroundStyle(result.hasPrefix("✅") ? Theme.ok : Theme.fault)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button {
                Haptics.tap()
                Task { await preflight(routine) }
            } label: {
                HStack {
                    if running == routine.id { ProgressView().tint(Theme.onButton) }
                    Text(running == routine.id ? "Läuft …" : "Prüfen & ausführen")
                }
                .font(Theme.rounded(14, weight: .bold))
                .foregroundStyle(Theme.onButton)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .background(Capsule().fill(Theme.buttonGradient))
            }
            .buttonStyle(PressableStyle())
            .disabled(!session.isInitialized || running != nil)
            .opacity(session.isInitialized ? 1 : 0.4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(tint: Theme.violet)
    }

    private var checksCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("VORPRÜFUNG")
                .font(.system(size: 12, weight: .heavy))
                .tracking(1.6)
                .foregroundStyle(.white.opacity(0.55))
            ForEach(checks) { check in
                HStack(alignment: .top) {
                    Image(systemName: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill")
                        .foregroundStyle(check.ok ? Theme.ok : Theme.severe)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(check.title).font(Theme.rounded(14, weight: .semibold))
                        Text(check.detail).font(Theme.rounded(12, weight: .medium)).foregroundStyle(.white.opacity(0.6))
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }

    // MARK: - Ablauf

    /// Prüft Spannung, Motor aus und Befehl – erst dann kommt die Rückfrage.
    private func preflight(_ routine: ServiceRoutine) async {
        var result: [Check] = []
        if let problem = ServiceRoutine.validate(routine.commandHex) {
            result.append(Check(title: "Befehl", ok: false, detail: problem))
        } else {
            result.append(Check(title: "Befehl", ok: true, detail: routine.commandHex.uppercased()))
        }
        let volts = try? await session.readVoltage()
        let voltsOK = (volts ?? 0) >= 12.5
        result.append(Check(title: "Batteriespannung", ok: voltsOK,
                            detail: volts.map { String(format: "%.2f V %@", $0, voltsOK ? "" : "– Ladegerät anschließen (mind. 12,5 V)") } ?? "nicht messbar"))
        if let data = try? await session.readPID(0x0C), data.count >= 2 {
            let rpm = Double(UInt16(data[0]) << 8 | UInt16(data[1])) / 4
            result.append(Check(title: "Motor aus, Zündung an", ok: rpm < 50,
                                detail: rpm < 50 ? "Drehzahl 0" : String(format: "Motor läuft (%.0f U/min) – bitte ausschalten", rpm)))
        } else {
            result.append(Check(title: "Zündung an", ok: true, detail: "Drehzahl nicht lesbar – Motor bitte aus"))
        }
        checks = result
        if result.allSatisfy(\.ok) {
            confirm = routine
        } else {
            Haptics.warning()
        }
    }

    private func execute(_ routine: ServiceRoutine) async {
        guard let command = Hex.bytes(routine.commandHex) else { return }
        running = routine.id
        var updated = routine
        defer {
            running = nil
            updated.lastRun = Date()
            store.upsert(updated)
        }
        do {
            if let read = Hex.bytes(routine.backupHex), !read.isEmpty, read.first == 0x22 {
                let backup = try await session.uds(read, ecu: routine.ecu, timeout: 4)
                updated.lastBackup = Hex.string(backup)
                session.info("Sicherung \(routine.name): \(Hex.string(backup))")
            }
            if routine.extendedSession {
                try await session.uds([0x10, 0x03], ecu: routine.ecu)
            }
            let response = try await session.uds(command, ecu: routine.ecu, timeout: 10)
            updated.lastResult = "✅ Steuergerät hat bestätigt: \(Hex.string(response))"
            Haptics.confirm()
        } catch {
            updated.lastResult = "Abgelehnt: \(error.localizedDescription)"
            Haptics.warning()
        }
        // zurück in die normale Sitzung
        if routine.extendedSession { _ = try? await session.uds([0x10, 0x01], ecu: routine.ecu) }
    }
}

/// Anlegen / Bearbeiten einer Routine.
struct RoutineEditor: View {
    @State var routine: ServiceRoutine
    var onSave: (ServiceRoutine) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ecuText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("z. B. AGR-Adaption zurücksetzen", text: $routine.name)
                }
                Section {
                    TextField("12", text: $ecuText)
                        .hexInput()
                    Toggle("Service-Sitzung (10 03) vorher", isOn: $routine.extendedSession)
                } header: {
                    Text("Steuergerät (Hex-Adresse)")
                } footer: {
                    Text("Motorsteuergerät DME/DDE = 12")
                }
                Section {
                    TextField("22 xx xx", text: $routine.backupHex)
                        .hexInput()
                } header: {
                    Text("Sicherung vorher lesen (optional)")
                } footer: {
                    Text("Lesebefehl für den Wert, der geändert wird – die Antwort wird vor dem Senden gespeichert.")
                }
                Section {
                    TextField("31 01 xx xx", text: $routine.commandHex)
                        .hexInput()
                    if let problem = ServiceRoutine.validate(routine.commandHex), !routine.commandHex.isEmpty {
                        Text(problem).foregroundStyle(Theme.fault)
                    }
                } header: {
                    Text("Befehl aus dem Mitschnitt")
                } footer: {
                    Text("Erlaubt: Routine (31), Schreiben (2E), Lesen (22). Flashen, Reset und Sicherheitszugang sind gesperrt.")
                }
            }
            .navigationTitle(routine.name.isEmpty ? "Neue Routine" : routine.name)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") {
                        if let ecu = Hex.bytes(ecuText), ecu.count == 1 { routine.ecu = ecu[0] }
                        onSave(routine)
                        dismiss()
                    }
                    .disabled(routine.name.trimmingCharacters(in: .whitespaces).isEmpty
                              || ServiceRoutine.validate(routine.commandHex) != nil)
                }
            }
            .onAppear { ecuText = String(format: "%02X", routine.ecu) }
        }
        .preferredColorScheme(.dark)
    }
}
