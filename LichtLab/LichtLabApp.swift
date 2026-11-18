import SwiftUI

@main
@MainActor
struct LichtLabApp: App {
    @StateObject private var ble: BLEManager
    @StateObject private var session: ELMSession
    @StateObject private var scanner: FaultScanner

    init() {
        let ble = BLEManager()
        let session = ELMSession(ble: ble)
        _ble = StateObject(wrappedValue: ble)
        _session = StateObject(wrappedValue: session)
        _scanner = StateObject(wrappedValue: FaultScanner(session: session))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(ble)
                .environmentObject(session)
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
