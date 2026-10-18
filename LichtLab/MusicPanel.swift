import SwiftUI
import UniformTypeIdentifiers

/// Lichtgruppen, die mit der Musik pulsieren können. Abblend- und Fernlicht sind absichtlich nicht dabei.
enum MusicGroup: String, CaseIterable, Identifiable {
    case angelEyes = "Angel Eyes", tails = "Rücklichter", blinkers = "Blinker", fog = "Nebel", brake = "Bremslicht"

    var id: String { rawValue }

    var spots: Set<LightSpot> {
        switch self {
        case .angelEyes: return [.angelEyeLeft, .angelEyeRight]
        case .tails: return [.tailLeft, .tailRight]
        case .blinkers: return [.blinkerFrontLeft, .blinkerFrontRight, .blinkerRearLeft, .blinkerRearRight]
        case .fog: return [.fogLeft, .fogRight]
        case .brake: return [.brakeLeft, .brakeRight]
        }
    }

    var tint: Color { (spots.first?.tint ?? .coolWhite).color }
}

/// Musik-Modus: lokale Datei abspielen, Lichter auf Bass, Mitten oder Höhen reagieren lassen.
struct MusicPanel: View {
    @EnvironmentObject private var music: MusicEngine
    @EnvironmentObject private var controller: LightController
    @EnvironmentObject private var session: ELMSession
    let car: CarScene

    @State private var showImporter = false
    @State private var groups: Set<MusicGroup> = [.angelEyes, .tails]
    @State private var driveCar = true
    @State private var flash = 0.0
    @Namespace private var namespace

    private var activeSpots: Set<LightSpot> {
        groups.reduce(into: Set<LightSpot>()) { $0.formUnion($1.spots) }
    }

    var body: some View {
        VStack(spacing: 14) {
            header
            SpectrumView(bars: music.bars, band: music.band)
                .frame(height: 64)
            transport
            bandPicker
            sensitivity
            groupChips
            if session.isInitialized {
                Toggle(isOn: $driveCar) {
                    Label("Auch am Auto schalten", systemImage: "car.side")
                        .font(.footnote.weight(.medium))
                }
                .tint(.cyan)
            }
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.audio], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                music.load(url)
                music.play()
            }
        }
        .onAppear {
            music.onBeat = { [weak car, weak controller] in
                car?.pushMusicLevel(1)
                controller?.musicBeat()
            }
            music.onLevel = { [weak car] level in
                car?.pushMusicLevel(level * 0.45)
            }
            car.setMusicSpots(activeSpots)
        }
        .onDisappear {
            music.pause()
            music.onBeat = nil
            music.onLevel = nil
            car.setMusicSpots([])
            controller.stopMusicSync()
        }
        .onChange(of: groups) { _ in
            car.setMusicSpots(activeSpots)
            updateCarSync()
        }
        .onChange(of: music.isPlaying) { _ in updateCarSync() }
        .onChange(of: driveCar) { _ in updateCarSync() }
        .onChange(of: music.beatCount) { _ in
            flash = 1
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.35)) { flash = 0 }
            }
        }
    }

    private func updateCarSync() {
        if music.isPlaying && driveCar && session.isInitialized {
            controller.startMusicSync(spots: activeSpots)
        } else {
            controller.stopMusicSync()
        }
    }

    // MARK: - Teile

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.cyan.opacity(0.15 + flash * 0.5))
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.cyan)
            }
            .frame(width: 40, height: 40)
            .scaleEffect(1 + flash * 0.18)
            .shadow(color: .cyan.opacity(flash * 0.8), radius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(music.title ?? "Keine Musik gewählt")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(music.title == nil ? "MP3, M4A, WAV … aus der Dateien-App" : "\(timeString(music.currentTime)) / \(timeString(music.duration))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Haptics.tap()
                showImporter = true
            } label: {
                Label(music.title == nil ? "Auswählen" : "Wechseln", systemImage: "folder")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(music.title == nil ? Color.white : Color.white.opacity(0.12)))
                    .foregroundStyle(music.title == nil ? Color.black : Color.white)
            }
            .buttonStyle(.plain)
        }
        .overlay(alignment: .bottom) {
            if let error = music.errorMessage {
                Text(error).font(.caption2).foregroundStyle(.orange).offset(y: 18)
            }
        }
    }

    private var transport: some View {
        VStack(spacing: 8) {
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.1))
                    Capsule().fill(Color.cyan).frame(width: proxy.size.width * music.progress)
                }
            }
            .frame(height: 3)

            HStack(spacing: 28) {
                Button { Haptics.tap(); music.restart() } label: {
                    Image(systemName: "backward.end.fill").font(.system(size: 18))
                }
                Button { Haptics.confirm(); music.togglePlay() } label: {
                    Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(Color.white))
                        .foregroundStyle(.black)
                }
                .disabled(music.title == nil)
                .opacity(music.title == nil ? 0.4 : 1)
                Text("\(music.beatCount)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .frame(width: 34)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
        }
    }

    private var bandPicker: some View {
        HStack(spacing: 2) {
            ForEach(MusicBand.allCases) { band in
                Button {
                    Haptics.tap()
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { music.band = band }
                } label: {
                    Text(band.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .foregroundStyle(music.band == band ? Color.black : Color.white.opacity(0.8))
                        .background {
                            if music.band == band {
                                Capsule().fill(.white).matchedGeometryEffect(id: "band", in: namespace)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Capsule().fill(.white.opacity(0.08)))
    }

    private var sensitivity: some View {
        HStack(spacing: 10) {
            Image(systemName: "dial.low").foregroundStyle(.secondary)
            Slider(value: $music.sensitivity, in: 0...1)
                .tint(.cyan)
            Image(systemName: "dial.high").foregroundStyle(.secondary)
        }
        .font(.caption)
    }

    private var groupChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(MusicGroup.allCases) { group in
                    let isOn = groups.contains(group)
                    Button {
                        Haptics.tap()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
                            if isOn { groups.remove(group) } else { groups.insert(group) }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(group.tint).frame(width: 8, height: 8)
                            Text(group.rawValue).font(.caption.weight(.semibold))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .foregroundStyle(isOn ? Color.black : Color.white)
                        .background(Capsule().fill(isOn ? Color.white : Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
        }
    }

    private func timeString(_ seconds: Double) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Spektrum-Balken; die Balken im gewählten Band leuchten in Cyan.
private struct SpectrumView: View {
    let bars: [Float]
    let band: MusicBand

    var body: some View {
        Canvas { context, size in
            let count = bars.count
            guard count > 0 else { return }
            let gap: CGFloat = 3
            let width = (size.width - gap * CGFloat(count - 1)) / CGFloat(count)
            for (i, value) in bars.enumerated() {
                let frequency = 40 * pow(400, (Float(i) + 0.5) / Float(count))
                let highlighted = band.range.contains(frequency)
                let height = max(3, CGFloat(value) * size.height)
                let rect = CGRect(x: CGFloat(i) * (width + gap), y: size.height - height, width: width, height: height)
                context.fill(Path(roundedRect: rect, cornerRadius: width / 2),
                             with: .color(highlighted ? Color.cyan : Color.white.opacity(0.28)))
            }
        }
        .animation(.linear(duration: 0.05), value: bars)
    }
}
