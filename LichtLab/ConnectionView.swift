import SwiftUI

struct ConnectionView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession

    var body: some View {
        NavigationStack {
            List {
                Section("Status") {
                    LabeledContent("Bluetooth", value: ble.status.text)
                    if let name = ble.connectedName {
                        LabeledContent("Adapter", value: name)
                    }
                    if let info = session.adapterInfo {
                        LabeledContent("Firmware", value: info)
                    }
                    if ble.status == .ready {
                        LabeledContent("Initialisiert", value: session.isInitialized ? "Ja" : "Nein")
                    }
                }

                if ble.status == .ready {
                    Section {
                        Button("Neu initialisieren") {
                            Task { await session.initialize() }
                        }
                        Button("Trennen", role: .destructive) {
                            Task {
                                await session.endAllSessions()
                                ble.disconnect()
                            }
                        }
                    }
                } else {
                    Section {
                        if ble.status == .scanning {
                            Button("Suche stoppen") { ble.stopScan() }
                        } else {
                            Button("Adapter suchen") { ble.startScan() }
                                .disabled(ble.status == .bluetoothOff || ble.status == .unauthorized || ble.status == .connecting)
                        }
                    } footer: {
                        Text("Zündung einschalten (Start/Stopp ohne Bremse drücken) und den vLinker in die OBD-Buchse stecken. Den Adapter hier verbinden, nicht in den iOS-Bluetooth-Einstellungen.")
                    }

                    if !ble.devices.isEmpty {
                        Section("Gefundene Geräte") {
                            ForEach(ble.devices) { device in
                                Button {
                                    ble.connect(device)
                                } label: {
                                    HStack {
                                        Image(systemName: device.looksLikeOBDAdapter ? "car.fill" : "dot.radiowaves.left.and.right")
                                        Text(device.name)
                                        Spacer()
                                        Text("\(device.rssi) dBm")
                                            .foregroundStyle(.secondary)
                                            .font(.caption)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("LichtLab")
        }
    }
}
