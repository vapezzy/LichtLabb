import Foundation
import AVFoundation
import Accelerate

/// Frequenzband, auf das die Lichter reagieren.
enum MusicBand: String, CaseIterable, Identifiable {
    case bass = "Bass", mid = "Mitten", treble = "Höhen"

    var id: String { rawValue }

    var range: ClosedRange<Float> {
        switch self {
        case .bass: return 35...150
        case .mid: return 400...2000
        case .treble: return 4000...12000
        }
    }
}

/// Ergebnis der Analyse eines Audio-Abschnitts.
struct SpectrumFrame: Sendable {
    /// Pegel pro Band (Bass, Mitten, Höhen), linear
    var bands: [Float]
    /// Balken für die Anzeige, 0…1, logarithmisch verteilt
    var bars: [Float]
}

/// FFT-Analyse mit Accelerate. Läuft auf dem Audio-Thread, nicht auf dem Main-Thread.
final class SpectrumAnalyzer {
    static let size = 2048
    static let barCount = 28

    private let fft: vDSP.FFT<DSPSplitComplex>
    private let window: [Float]
    private var real = [Float](repeating: 0, count: size / 2)
    private var imag = [Float](repeating: 0, count: size / 2)
    private var magnitudes = [Float](repeating: 0, count: size / 2)

    init?() {
        guard let fft = vDSP.FFT(log2n: vDSP_Length(log2(Float(Self.size))), radix: .radix2, ofType: DSPSplitComplex.self) else {
            return nil
        }
        self.fft = fft
        window = vDSP.window(ofType: Float.self, usingSequence: .hanningDenormalized, count: Self.size, isHalfWindow: false)
    }

    func analyze(_ samples: UnsafePointer<Float>, count: Int, sampleRate: Float) -> SpectrumFrame {
        var input = [Float](repeating: 0, count: Self.size)
        let used = min(count, Self.size)
        for i in 0..<used { input[i] = samples[i] }
        vDSP.multiply(input, window, result: &input)

        let half = Self.size / 2
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                input.withUnsafeBytes { raw in
                    vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(half))
                }
                fft.forward(input: split, output: &split)
                magnitudes.withUnsafeMutableBufferPointer { magPtr in
                    vDSP_zvabs(&split, 1, magPtr.baseAddress!, 1, vDSP_Length(half))
                }
            }
        }

        let binWidth = sampleRate / Float(Self.size)
        func energy(_ low: Float, _ high: Float) -> Float {
            let from = max(1, Int(low / binWidth))
            let to = min(half - 1, max(from, Int(high / binWidth)))
            var sum: Float = 0
            for i in from...to { sum += magnitudes[i] }
            return sum / Float(to - from + 1)
        }

        let bands = MusicBand.allCases.map { energy($0.range.lowerBound, $0.range.upperBound) }

        // Balken von 40 Hz bis 16 kHz, logarithmisch, in dB auf 0…1 abgebildet
        let low: Float = 40, high: Float = 16000
        let bars = (0..<Self.barCount).map { i -> Float in
            let f0 = low * pow(high / low, Float(i) / Float(Self.barCount))
            let f1 = low * pow(high / low, Float(i + 1) / Float(Self.barCount))
            let db = 20 * log10(max(energy(f0, f1), 1e-6))
            return min(1, max(0, (db + 10) / 60))
        }
        return SpectrumFrame(bands: bands, bars: bars)
    }
}

/// Spielt eine lokale Audiodatei ab und erkennt Beats im gewählten Frequenzband.
@MainActor
final class MusicEngine: ObservableObject {
    @Published private(set) var title: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    @Published private(set) var bars = [Float](repeating: 0, count: SpectrumAnalyzer.barCount)
    /// Pegel des gewählten Bands, 0…1 (für die 3D-Leuchten)
    @Published private(set) var level: Double = 0
    @Published private(set) var beatCount = 0
    @Published var band: MusicBand = .bass
    /// 0 = nur kräftige Schläge, 1 = reagiert auf fast alles
    @Published var sensitivity: Double = 0.55
    @Published var errorMessage: String?

    /// Wird bei jedem erkannten Beat aufgerufen.
    var onBeat: (() -> Void)?
    /// Wird bei jedem analysierten Abschnitt mit dem aktuellen Pegel aufgerufen.
    var onLevel: ((Double) -> Void)?

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var file: AVAudioFile?
    private var startOffset: Double = 0
    private var averages = [Float](repeating: 0, count: MusicBand.allCases.count)
    private var peaks = [Float](repeating: 0.0001, count: MusicBand.allCases.count)
    private var lastBeat = Date.distantPast
    private var tapInstalled = false
    private var playbackToken = 0

    init() {
        engine.attach(player)
    }

    var progress: Double { duration > 0 ? min(1, currentTime / duration) : 0 }

    // MARK: - Datei

    func load(_ url: URL) {
        stop()
        errorMessage = nil
        do {
            let local = try Self.copyToTemporary(url)
            let file = try AVAudioFile(forReading: local)
            self.file = file
            title = url.deletingPathExtension().lastPathComponent
            duration = Double(file.length) / file.processingFormat.sampleRate
            currentTime = 0
            startOffset = 0
            engine.disconnectNodeOutput(player)
            engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
            installTapIfNeeded()
        } catch {
            file = nil
            title = nil
            errorMessage = "„\(url.lastPathComponent)“ lässt sich nicht abspielen. Unterstützt: MP3, M4A/AAC, WAV, AIFF, FLAC, CAF. Songs aus Apple Music (Kopierschutz) gehen nicht."
        }
    }

    /// Kopiert die gewählte Datei in den App-Ordner, damit der Zugriff nach dem Auswählen bestehen bleibt.
    private static func copyToTemporary(_ url: URL) throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("Musik", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.copyItem(at: url, to: target)
        return target
    }

    // MARK: - Wiedergabe

    func togglePlay() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard let file else { return }
        do {
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if !engine.isRunning { try engine.start() }
        } catch {
            errorMessage = "Audio konnte nicht gestartet werden: \(error.localizedDescription)"
            return
        }
        if !player.isPlaying {
            if currentTime >= duration - 0.05 { currentTime = 0 }
            schedule(file, from: currentTime)
            player.play()
        }
        isPlaying = true
    }

    func pause() {
        currentTime = playbackTime
        playbackToken += 1
        player.stop()
        isPlaying = false
        level = 0
    }

    func restart() {
        let wasPlaying = isPlaying
        pause()
        currentTime = 0
        if wasPlaying { play() }
    }

    func stop() {
        playbackToken += 1
        player.stop()
        isPlaying = false
        level = 0
        bars = bars.map { _ in 0 }
    }

    private func schedule(_ file: AVAudioFile, from time: Double) {
        let sampleRate = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(time * sampleRate)
        let remaining = AVAudioFrameCount(max(0, file.length - startFrame))
        guard remaining > 0 else { return }
        startOffset = time
        playbackToken += 1
        let token = playbackToken
        player.scheduleSegment(file, startingFrame: startFrame, frameCount: remaining, at: nil) { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.playbackToken == token else { return }
                self.isPlaying = false
                self.currentTime = self.duration
                self.level = 0
            }
        }
    }

    private var playbackTime: Double {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime) else { return currentTime }
        return startOffset + Double(playerTime.sampleTime) / playerTime.sampleRate
    }

    // MARK: - Analyse

    private func installTapIfNeeded() {
        guard !tapInstalled, let analyzer = SpectrumAnalyzer() else { return }
        tapInstalled = true
        let mixer = engine.mainMixerNode
        let format = mixer.outputFormat(forBus: 0)
        let target = WeakTarget(self)
        mixer.installTap(onBus: 0, bufferSize: 1024, format: format,
                         block: Self.makeTap(analyzer: analyzer, sink: { frames in
            DispatchQueue.main.async { target.engine?.consume(frames) }
        }))
    }

    /// Zerlegt jeden Audio-Puffer in Abschnitte à 1024 Samples (≈ 23 ms) und analysiert sie einzeln –
    /// so werden Beats auch dann genau erkannt, wenn iOS größere Puffer liefert.
    nonisolated private static func makeTap(analyzer: SpectrumAnalyzer,
                                            sink: @escaping @Sendable ([(SpectrumFrame, Double)]) -> Void) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channel = buffer.floatChannelData?[0] else { return }
            let count = Int(buffer.frameLength)
            let sampleRate = Float(buffer.format.sampleRate)
            let hop = 1024
            var frames: [(SpectrumFrame, Double)] = []
            var start = 0
            repeat {
                let length = min(SpectrumAnalyzer.size, count - start)
                guard length > 0 else { break }
                frames.append((analyzer.analyze(channel + start, count: length, sampleRate: sampleRate),
                               Double(start) / Double(sampleRate)))
                start += hop
            } while start + hop <= count
            sink(frames)
        }
    }

    private func consume(_ frames: [(SpectrumFrame, Double)]) {
        guard isPlaying else { return }
        for (frame, offset) in frames {
            if offset <= 0.001 {
                process(frame)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + offset) { [weak self] in
                    guard let self, self.isPlaying else { return }
                    self.process(frame)
                }
            }
        }
        currentTime = playbackTime
    }

    private func process(_ frame: SpectrumFrame) {
        bars = frame.bars
        let index = MusicBand.allCases.firstIndex(of: band) ?? 0
        let value = frame.bands[index]

        // Gleitender Durchschnitt (~1 s) und langsam abfallender Spitzenwert zum Normieren
        averages[index] = averages[index] * 0.96 + value * 0.04
        peaks[index] = max(value, peaks[index] * 0.995)
        level = Double(min(1, value / max(peaks[index], 0.0001)))
        onLevel?(level)

        // Beat: deutlich über dem Durchschnitt und nicht zu dicht hintereinander
        let threshold = Float(1.15 + (1 - sensitivity) * 1.1)
        let minimumGap = band == .bass ? 0.18 : 0.12
        if value > averages[index] * threshold, value > peaks[index] * 0.25,
           Date().timeIntervalSince(lastBeat) > minimumGap {
            lastBeat = Date()
            beatCount += 1
            onBeat?()
        }
    }
}

/// Schwache Referenz, die der Audio-Thread an den Main-Thread weiterreichen darf.
private final class WeakTarget: @unchecked Sendable {
    weak var engine: MusicEngine?
    init(_ engine: MusicEngine) { self.engine = engine }
}
