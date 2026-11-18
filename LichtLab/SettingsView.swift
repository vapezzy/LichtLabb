import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var session: ELMSession
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Adapter") {
                    LabeledContent("Status", value: session.isInitialized ? "Verbunden" : "Nicht verbunden")
                    if let info = session.adapterInfo {
                        LabeledContent("Firmware", value: info)
                    }
                }

                Section {
                    NavigationLink {
                        ConsoleView()
                    } label: {
                        Label("Diagnose-Konsole", systemImage: "terminal")
                    }
                } header: {
                    Text("Werkzeuge")
                } footer: {
                    Text("Zeigt jeden Befehl und jede Antwort des Adapters. Das Protokoll lässt sich teilen, wenn etwas nicht klappt.")
                }

                Section("Vor dem Löschen") {
                    Label("Zündung an, Motor aus, Auto steht.", systemImage: "key")
                    Label("Fehler erst auslesen und notieren – der Bericht lässt sich teilen.", systemImage: "square.and.arrow.up")
                    Label("Löschen behebt keine Ursache. Kommt ein Fehler sofort wieder, besteht das Problem noch.", systemImage: "arrow.counterclockwise")
                    Label("Airbag- oder Bremsfehler nicht einfach löschen, sondern prüfen lassen.", systemImage: "exclamationmark.triangle")
                    Label("OBD-II-Löschen setzt die Bereitschaftstests zurück – vor der AU/HU erst wieder ein Stück fahren.", systemImage: "engine.combustion")
                }
                .font(.footnote)
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}
