import SwiftUI

@main
@MainActor
struct LichtLabApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: ELMSession
    @StateObject private var store: PresetStore
    @StateObject private var controller: LightController

    init() {
        let ble = BLEManager()
        let session = ELMSession(ble: ble)
        let store = PresetStore()
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: session)
        _store = StateObject(wrappedValue: store)
        _controller = StateObject(wrappedValue: LightController(session: session, store: store))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(session)
                .environmentObject(store)
                .environmentObject(controller)
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
