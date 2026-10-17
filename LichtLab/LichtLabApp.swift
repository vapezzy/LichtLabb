import SwiftUI

@main
@MainActor
struct LichtLabApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: ELMSession
    @StateObject private var store: PresetStore
    @StateObject private var controller: LightController
    @StateObject private var scanner: FaultScanner

    init() {
        let ble = BLEManager()
        let session = ELMSession(ble: ble)
        let store = PresetStore()
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: session)
        _store = StateObject(wrappedValue: store)
        _controller = StateObject(wrappedValue: LightController(session: session, store: store))
        _scanner = StateObject(wrappedValue: FaultScanner(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(controller)
                .environmentObject(scanner)
        }
    }
}

extension View {
    /// Eingabefeld für Hex-Werte: Großbuchstaben, keine Autokorrektur.
    func hexInput() -> some View {
        #if os(iOS)
        return self
            .textInputAutocapitalization(.characters)
            .autocorrectionDisabled()
            .font(.body.monospaced())
        #else
        return self.autocorrectionDisabled().font(.body.monospaced())
        #endif
    }
}
