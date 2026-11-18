import SwiftUI

/// Hauptbildschirm: Verbindung oben, darunter Fehlerspeicher auslesen und löschen.
struct RootView: View {
    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession
    @EnvironmentObject private var scanner: FaultScanner

    @State private var showConnection = false
    @State private var showSettings = false
    @State private var appeared = false

    var body: some View {
        ZStack {
            background

            VStack(spacing: 12) {
                topBar
                FaultsView(onConnect: { showConnection = true })
            }
            .padding(.horizontal, 16)
            .opacity(appeared ? 1 : 0)
            .blur(radius: appeared ? 0 : 20)
            .offset(y: appeared ? 0 : 24)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) { appeared = true }
        }
        .sheet(isPresented: $showConnection) {
            ConnectionView()
                .presentationDetents([.medium, .large])
                .presentationBackground(.ultraThinMaterial)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .presentationBackground(.ultraThinMaterial)
        }
    }

    /// Dunkler Verlauf mit zwei weichen Farbflecken – statisch, kostet keine Leistung.
    private var background: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.03, green: 0.04, blue: 0.07), .black],
                           startPoint: .top, endPoint: .bottom)
            Circle()
                .fill(Color.cyan.opacity(0.18))
                .frame(width: 420, height: 420)
                .blur(radius: 120)
                .offset(x: -140, y: -320)
            Circle()
                .fill(Color.blue.opacity(0.16))
                .frame(width: 380, height: 380)
                .blur(radius: 120)
                .offset(x: 160, y: 260)
        }
        .ignoresSafeArea()
        .drawingGroup()
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LichtLab")
                    .font(.title2.weight(.semibold))
                Text("BMW-Diagnose · F-Serie")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { showConnection = true } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                        .shadow(color: statusColor, radius: 5)
                    Text(statusText)
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 13)
                .padding(.vertical, 9)
                .glass(cornerRadius: 20)
            }
            Button { showSettings = true } label: {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 38, height: 38)
                    .glass(cornerRadius: 19)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .padding(.top, 6)
    }

    private var statusText: String {
        if session.isInitialized { return "Verbunden" }
        if ble.status == .ready || ble.status == .connecting { return "Verbinde …" }
        return "Nicht verbunden"
    }

    private var statusColor: Color {
        if session.isInitialized { return .green }
        if ble.status == .ready || ble.status == .connecting { return .yellow }
        return .gray
    }
}
