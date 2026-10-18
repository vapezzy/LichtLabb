import SwiftUI

struct RootView: View {
    enum Zone: String, CaseIterable, Identifiable {
        case all = "Alle", front = "Vorne", rear = "Hinten"
        var id: String { rawValue }
        var focus: CameraFocus {
            switch self {
            case .all: return .overview
            case .front: return .front
            case .rear: return .rear
            }
        }
    }

    enum Panel { case lights, shows }

    enum AppMode: String, CaseIterable, Identifiable {
        case lights = "Licht", music = "Musik", faults = "Fehler"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .lights: return "lightbulb.2"
            case .music: return "music.note"
            case .faults: return "stethoscope"
            }
        }
    }

    @EnvironmentObject private var ble: BLEManager
    @EnvironmentObject private var session: ELMSession
    @EnvironmentObject private var store: PresetStore
    @EnvironmentObject private var controller: LightController

    @StateObject private var car = CarScene()
    @AppStorage("rearLightStyle") private var rearStyleRaw = RearLightStyle.original.rawValue
    @AppStorage("paintColor") private var paintRaw = PaintColor.estorilBlau.rawValue

    @State private var zone: Zone = .all
    @State private var panel: Panel = .lights
    @State private var mode: AppMode = .lights
    @State private var introPhase = 0
    @State private var showConnection = false
    @State private var showSettings = false
    @Namespace private var namespace

    private var rearStyle: RearLightStyle { RearLightStyle(rawValue: rearStyleRaw) ?? .original }
    private var paint: PaintColor { PaintColor(rawValue: paintRaw) ?? .estorilBlau }

    var body: some View {
        ZStack {
            // Im Fehler-Modus ist das Auto verdeckt – dann nicht weiter rendern.
            CarSceneView(car: car, paused: mode == .faults) { spot in handleTap(spot) }
                .ignoresSafeArea()

            vignette

            // Im Fehler-Modus verschwimmt das Auto im Hintergrund.
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.35))
                .ignoresSafeArea()
                .opacity(mode == .faults ? 1 : 0)
                .allowsHitTesting(mode == .faults)

            VStack(spacing: 12) {
                topBar
                modeSwitcher
                if mode == .lights {
                    if let toast = controller.toast {
                        toastView(toast)
                            .id(toast.id)
                            .transition(.blurFade)
                    }
                    Spacer()
                    controlPanel
                        .transition(.blurFade.combined(with: .move(edge: .bottom)))
                } else if mode == .music {
                    Spacer()
                    MusicPanel(car: car)
                        .padding(16)
                        .frostedGlass(cornerRadius: 30)
                        .transition(.blurFade.combined(with: .move(edge: .bottom)))
                } else {
                    FaultsView(onConnect: { showConnection = true })
                        .transition(.blurFade)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            .opacity(introPhase == 2 ? 1 : 0)
            .blur(radius: introPhase == 2 ? 0 : 24)
            .offset(y: introPhase == 2 ? 0 : 30)

            if introPhase < 2 {
                introOverlay.transition(.blurFade)
            }
        }
        .preferredColorScheme(.dark)
        .animation(.easeInOut(duration: 0.35), value: controller.toast)
        .onAppear(perform: startIntro)
        .onReceive(controller.$litSpots) { car.setLit($0) }
        .onReceive(controller.$selectedSpots) { car.setSelected($0) }
        .onChange(of: rearStyleRaw) { _ in car.setRearStyle(rearStyle) }
        .onChange(of: paintRaw) { _ in car.setPaint(paint) }
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

    // MARK: - Intro

    private var introOverlay: some View {
        ZStack {
            Color.black.opacity(introPhase == 0 ? 1 : 0.35).ignoresSafeArea()
            VStack(spacing: 12) {
                Text("LICHTLAB")
                    .font(.system(size: 46, weight: .ultraLight))
                    .tracking(16)
                Text("BMW F36 · LICHTSTEUERUNG")
                    .font(.caption.weight(.medium))
                    .tracking(5)
                    .foregroundStyle(.secondary)
            }
            .foregroundStyle(.white)
            .blur(radius: introPhase == 0 ? 26 : 0)
            .opacity(introPhase == 0 ? 0 : 1)
            .scaleEffect(introPhase == 0 ? 1.15 : 1)
        }
        .allowsHitTesting(false)
    }

    private func startIntro() {
        guard introPhase == 0 else { return }
        car.setPaint(paint)
        car.setRearStyle(rearStyle)
        car.playIntro()
        withAnimation(.easeOut(duration: 1.6)) { introPhase = 1 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) {
            withAnimation(.easeInOut(duration: 1.3)) { introPhase = 2 }
        }
    }

    // MARK: - Oberfläche

    private var vignette: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 190)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                .frame(height: 340)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("LichtLab")
                    .font(.title2.weight(.semibold))
                Text("4er Gran Coupé · F36")
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

    private var modeSwitcher: some View {
        HStack(spacing: 2) {
            ForEach(AppMode.allCases) { item in
                Button {
                    guard mode != item else { return }
                    Haptics.tap()
                    withAnimation(.spring(response: 0.55, dampingFraction: 0.85)) { mode = item }
                    if item == .lights { car.focus(zone.focus) } else { car.focus(.overview) }
                } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .foregroundStyle(mode == item ? Color.black : Color.white.opacity(0.85))
                        .background {
                            if mode == item {
                                Capsule().fill(.white).matchedGeometryEffect(id: "appMode", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .glass(cornerRadius: 22)
    }

    private var statusText: String {
        if session.isInitialized { return "Live" }
        if ble.status == .ready { return "Verbinde …" }
        return "Vorschau"
    }

    private var statusColor: Color {
        if session.isInitialized { return .green }
        if ble.status == .ready || ble.status == .connecting { return .yellow }
        return .gray
    }

    private func toastView(_ toast: LightController.Toast) -> some View {
        HStack(spacing: 8) {
            Image(systemName: toast.isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(toast.isError ? .orange : .cyan)
            Text(toast.text)
                .font(.footnote)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .glass(cornerRadius: 18)
    }

    private var controlPanel: some View {
        VStack(spacing: 14) {
            HStack {
                zonePicker
                Spacer()
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.85)) {
                        panel = panel == .lights ? .shows : .lights
                    }
                } label: {
                    Label(panel == .lights ? "Szenen" : "Lichter",
                          systemImage: panel == .lights ? "sparkles.rectangle.stack" : "lightbulb.2")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
            }

            ZStack {
                if panel == .lights {
                    lightsContent.transition(.blurFade)
                } else {
                    showsContent.transition(.blurFade)
                }
            }
        }
        .padding(16)
        .frostedGlass(cornerRadius: 30)
    }

    private var zonePicker: some View {
        HStack(spacing: 2) {
            ForEach(Zone.allCases) { item in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { zone = item }
                    car.focus(item.focus)
                } label: {
                    Text(item.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .foregroundStyle(zone == item ? Color.black : Color.white.opacity(0.8))
                        .background {
                            if zone == item {
                                Capsule()
                                    .fill(.white)
                                    .matchedGeometryEffect(id: "zone", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    // MARK: - Lichter

    private var visiblePresets: [LightPreset] {
        switch zone {
        case .all: return store.presets
        case .front: return store.presets.filter(\.isFront)
        case .rear: return store.presets.filter { !$0.isFront }
        }
    }

    private var lightsContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(visiblePresets) { preset in
                        LightChip(preset: preset,
                                  isOn: controller.onPresets.contains(preset.id),
                                  isSelected: controller.selection.contains(preset.id))
                            .onTapGesture { select(preset) }
                            .transition(.blurFade)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 2)
                .animation(.spring(response: 0.45, dampingFraction: 0.85), value: zone)
            }

            HStack(spacing: 10) {
                PanelButton(title: "Einschalten", icon: "lightbulb.fill", prominent: true) {
                    Haptics.confirm()
                    Task { await controller.switchSelection(on: true) }
                }
                .disabled(controller.selection.isEmpty)

                PanelButton(title: "Aus", icon: "lightbulb.slash") {
                    Haptics.tap()
                    Task { await controller.switchSelection(on: false) }
                }
                .disabled(controller.selection.isEmpty)

                PanelButton(title: nil, icon: "power", tint: .red) {
                    Haptics.tap()
                    Task { await controller.allOff() }
                }
            }

            Text(controller.selection.isEmpty
                 ? "Tippe Leuchten am Auto oder hier an, um sie auszuwählen."
                 : "\(controller.selection.count) ausgewählt · nochmal tippen zum Abwählen")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .animation(nil, value: controller.selection)
        }
    }

    private func select(_ preset: LightPreset) {
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            controller.toggleSelection(preset.id)
        }
        if controller.selection.contains(preset.id), zone == .all {
            car.focus(preset.isFront ? .front : .rear)
        }
    }

    private func handleTap(_ spot: LightSpot?) {
        guard let spot else { return }
        Haptics.tap()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            _ = controller.toggleSelection(spot: spot)
        }
    }

    // MARK: - Szenen

    private var showsContent: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(LightShow.all(for: rearStyle)) { show in
                    ShowCard(show: show,
                             isPlaying: controller.playingShow == show.id,
                             progress: controller.playingShow == show.id ? controller.showProgress : 0)
                        .onTapGesture {
                            Haptics.confirm()
                            if controller.playingShow == show.id {
                                Task { await controller.stopShow() }
                            } else {
                                if zone != .all {
                                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { zone = .all }
                                    car.focus(.overview)
                                }
                                controller.play(show)
                            }
                        }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
    }
}

// MARK: - Bausteine

private struct LightChip: View {
    let preset: LightPreset
    let isOn: Bool
    let isSelected: Bool

    var body: some View {
        let tint = preset.tint.color
        HStack(spacing: 8) {
            Circle()
                .fill(isOn ? tint : tint.opacity(0.25))
                .frame(width: 10, height: 10)
                .shadow(color: isOn ? tint : .clear, radius: 6)
            Text(preset.name)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            if !preset.isConfigured {
                Image(systemName: "wrench")
                    .font(.caption2)
                    .foregroundStyle(isSelected ? Color.orange : Color.orange.opacity(0.8))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .foregroundStyle(isSelected ? Color.black : Color.white)
        .background(Capsule().fill(isSelected ? Color.white : Color.white.opacity(0.08)))
        .overlay(Capsule().strokeBorder(isOn ? tint.opacity(0.9) : Color.white.opacity(0.12), lineWidth: 1))
        .shadow(color: isOn ? tint.opacity(0.6) : .clear, radius: 12)
        .scaleEffect(isSelected ? 1.05 : 1)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: isSelected)
        .animation(.easeInOut(duration: 0.3), value: isOn)
    }
}

private struct PanelButton: View {
    let title: String?
    let icon: String
    var prominent = false
    var tint: Color = .white
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                if let title { Text(title) }
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: title == nil ? 52 : .infinity, minHeight: 46)
            .foregroundStyle(prominent ? Color.black : tint)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(prominent ? Color.white : tint.opacity(0.12))
            )
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(PressStyle())
    }
}

private struct PressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

private struct ShowCard: View {
    let show: LightShow
    let isPlaying: Bool
    let progress: Double

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: show.icon)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isPlaying ? Color.cyan : Color.white)
            Spacer(minLength: 0)
            Text(show.name)
                .font(.headline)
            Text(show.subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack {
                Text(String(format: "%.0f s", show.duration))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.caption)
            }
            ProgressView(value: progress)
                .tint(.cyan)
                .opacity(isPlaying ? 1 : 0)
        }
        .foregroundStyle(.white)
        .padding(14)
        .frame(width: 156, height: 170)
        .background(shape.fill(Color.white.opacity(isPlaying ? 0.14 : 0.06)))
        .overlay {
            if isPlaying {
                // Umlaufende Lichtkante, solange die Szene läuft
                TimelineView(.animation) { timeline in
                    let angle = timeline.date.timeIntervalSinceReferenceDate * 180
                    shape.strokeBorder(
                        AngularGradient(colors: [.cyan, .purple.opacity(0.2), .cyan], center: .center, angle: .degrees(angle)),
                        lineWidth: 1.5)
                }
            } else {
                shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
            }
        }
        .shadow(color: isPlaying ? .cyan.opacity(0.35) : .clear, radius: 16)
        .scaleEffect(isPlaying ? 1.03 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isPlaying)
    }
}
