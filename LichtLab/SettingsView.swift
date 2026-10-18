import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("rearLightStyle") private var rearStyleRaw = RearLightStyle.original.rawValue
    @AppStorage("paintColor") private var paintRaw = PaintColor.estorilBlau.rawValue

    @State private var showImport = false

    private var rearStyle: RearLightStyle { RearLightStyle(rawValue: rearStyleRaw) ?? .original }

    var body: some View {
        NavigationStack {
            Form {
                Section("Lackierung") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 14) {
                            ForEach(PaintColor.allCases) { color in
                                VStack(spacing: 6) {
                                    Circle()
                                        .fill(color.color.gradient)
                                        .frame(width: 40, height: 40)
                                        .overlay(Circle().strokeBorder(.white, lineWidth: paintRaw == color.rawValue ? 2.5 : 0))
                                        .shadow(color: color.color.opacity(0.6), radius: paintRaw == color.rawValue ? 8 : 0)
                                    Text(color.title)
                                        .font(.caption2)
                                        .foregroundStyle(paintRaw == color.rawValue ? .primary : .secondary)
                                }
                                .onTapGesture {
                                    Haptics.tap()
                                    withAnimation(.spring(response: 0.3)) { paintRaw = color.rawValue }
                                }
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }

                Section {
                    Picker("Rückleuchten", selection: $rearStyleRaw) {
                        ForEach(RearLightStyle.allCases) { style in
                            Text(style.title).tag(style.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Rückleuchten")
                } footer: {
                    Text(rearStyle.footer)
                }

                Section {
                    ForEach($store.presets) { $preset in
                        NavigationLink {
                            PresetEditor(preset: $preset)
                        } label: {
                            HStack(spacing: 12) {
                                Circle()
                                    .fill(preset.tint.color)
                                    .frame(width: 10, height: 10)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(preset.name)
                                    Text(preset.isConfigured ? "SG \(preset.ecu) · DID \(preset.did)" : "Noch nicht eingerichtet")
                                        .font(.caption)
                                        .foregroundStyle(preset.isConfigured ? Color.secondary : Color.orange)
                                }
                            }
                        }
                    }
                    .onDelete { store.presets.remove(atOffsets: $0) }
                    .onMove { store.presets.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        store.presets.append(LightPreset(name: "Neue Leuchte", spots: []))
                    } label: {
                        Label("Leuchte hinzufügen", systemImage: "plus")
                    }
                    Button {
                        showImport = true
                    } label: {
                        Label("Profil importieren", systemImage: "square.and.arrow.down")
                    }
                    ShareLink(item: store.profileText) {
                        Label("Profil exportieren", systemImage: "square.and.arrow.up")
                    }
                } header: {
                    Text("Leuchten einrichten")
                } footer: {
                    Text("Mit „Profil importieren“ richtest du alle Leuchten auf einmal ein. Für nachgerüstete Leuchten kannst du eigene Einträge anlegen und ihnen eine Position am Auto geben.")
                }

                Section("Werkzeuge") {
                    NavigationLink {
                        ConsoleView()
                    } label: {
                        Label("Diagnose-Konsole", systemImage: "terminal")
                    }
                    Button("Leuchten auf Standard zurücksetzen", role: .destructive) {
                        store.presets = PresetStore.defaults
                    }
                }

                Section {
                    Label("Nur im Stand benutzen. Lichtsteuerung über Diagnose ist im Straßenverkehr nicht zulässig. Xenon-Abblendlicht nicht schnell schalten.",
                          systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
            .scrollContentBackground(.hidden)
            .sheet(isPresented: $showImport) { ProfileImportView() }
            .navigationTitle("Einstellungen")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
    }
}

struct PresetEditor: View {
    @EnvironmentObject private var session: ELMSession
    @Binding var preset: LightPreset
    @State private var result: String?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Name", text: $preset.name)
            }
            Section {
                TextField("Steuergerät (z. B. 72)", text: $preset.ecu).hexInput()
                TextField("DID, 2 Byte (z. B. D1 23)", text: $preset.did).hexInput()
                TextField("Steuerdaten (optional)", text: $preset.controlData).hexInput()
            } header: {
                Text("Adresse")
            } footer: {
                Text("FRM (Außenlicht) beim F36: 72. Die DID für jede Leuchte musst du in der Konsole herausfinden.")
            }
            Section("Befehle") {
                LabeledContent("An", value: preset.onCommand ?? "–")
                LabeledContent("Aus", value: preset.offCommand ?? "–")
            }
            .font(.callout.monospaced())

            Section {
                HStack {
                    Button("Test: An") { test(on: true) }
                    Spacer()
                    Button("Test: Aus") { test(on: false) }
                }
                .buttonStyle(.bordered)
                .disabled(!preset.isConfigured || !session.isInitialized)
                if let result {
                    Text(result).font(.footnote)
                }
            }

            Section {
                ForEach(LightSpot.allCases) { spot in
                    Button {
                        if let index = preset.spots.firstIndex(of: spot) {
                            preset.spots.remove(at: index)
                        } else {
                            preset.spots.append(spot)
                        }
                    } label: {
                        HStack {
                            Circle().fill(spot.tint.color).frame(width: 8, height: 8)
                            Text(spot.title).foregroundStyle(.primary)
                            Spacer()
                            if preset.spots.contains(spot) {
                                Image(systemName: "checkmark").foregroundStyle(.tint)
                            }
                        }
                    }
                }
            } header: {
                Text("Position am 3D-Auto")
            } footer: {
                Text("Bestimmt, welche Stelle im 3D-Modell aufleuchtet und wo du die Leuchte antippen kannst.")
            }
        }
        .scrollContentBackground(.hidden)
        .navigationTitle(preset.name)
    }

    private func test(on: Bool) {
        Task {
            do {
                try await session.setLight(preset, on: on)
                result = on ? "✅ Positiv – Leuchte sollte an sein" : "✅ Kontrolle zurück ans Steuergerät"
            } catch {
                result = "❌ \(error.localizedDescription)"
            }
        }
    }
}

/// Licht-Profil als Text einfügen – richtet alle Leuchten in einem Schritt ein.
struct ProfileImportView: View {
    @EnvironmentObject private var store: PresetStore
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var result: String?

    private var preview: (entries: [PresetStore.ProfileEntry], invalidLines: [Int]) {
        PresetStore.parseProfile(text)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 180)
                        .autocorrectionDisabled()
                    #if os(iOS)
                    Button {
                        if let pasted = UIPasteboard.general.string { text = pasted }
                    } label: {
                        Label("Aus Zwischenablage einfügen", systemImage: "doc.on.clipboard")
                    }
                    #endif
                } header: {
                    Text("Profil")
                } footer: {
                    Text("Eine Leuchte pro Zeile: Name; Steuergerät; DID; Steuerdaten; Positionen (optional). Beispiel:\nAngel Eyes links; 40; D1 23; 01; Angel Eye links\nLeuchten mit gleichem Namen werden aktualisiert, neue angelegt.")
                }

                if !text.isEmpty {
                    Section("Vorschau") {
                        ForEach(Array(preview.entries.enumerated()), id: \.offset) { _, entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name)
                                Text("SG \(entry.ecu) · DID \(entry.did)\(entry.controlData.isEmpty ? "" : " · \(entry.controlData)")")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if !preview.invalidLines.isEmpty {
                            Label("Ungültige Zeilen: \(preview.invalidLines.map(String.init).joined(separator: ", "))",
                                  systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let result {
                    Section { Text(result).font(.footnote) }
                }
            }
            .scrollContentBackground(.hidden)
            .navigationTitle("Profil importieren")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Übernehmen") {
                        let outcome = store.importProfile(text)
                        Haptics.confirm()
                        result = "\(outcome.updated) aktualisiert, \(outcome.added) neu angelegt."
                        if outcome.invalidLines.isEmpty {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismiss() }
                        }
                    }
                    .disabled(preview.entries.isEmpty)
                }
            }
        }
        .presentationBackground(.ultraThinMaterial)
    }
}
