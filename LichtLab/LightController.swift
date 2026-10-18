import Foundation

/// Verbindet Auswahl, Lichtzustand und Szenen mit der Diagnose-Sitzung.
/// Ohne Verbindung läuft alles als Vorschau nur im 3D-Modell.
@MainActor
final class LightController: ObservableObject {
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let isError: Bool
    }

    @Published private(set) var onPresets: Set<UUID> = [] { didSet { recompute() } }
    @Published private(set) var selection: Set<UUID> = [] { didSet { recompute() } }
    @Published private(set) var litSpots: Set<LightSpot> = []
    @Published private(set) var selectedSpots: Set<LightSpot> = []
    @Published private(set) var playingShow: String?
    @Published private(set) var showProgress: Double = 0
    @Published var toast: Toast?

    let session: ELMSession
    let store: PresetStore

    private var showSpots: Set<LightSpot>? { didSet { recompute() } }
    private var showTask: Task<Void, Never>?

    init(session: ELMSession, store: PresetStore) {
        self.session = session
        self.store = store
    }

    var isLive: Bool { session.isInitialized }

    // MARK: - Auswahl

    func toggleSelection(_ id: UUID) {
        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
    }

    func toggleSelection(spot: LightSpot) -> LightPreset? {
        guard let preset = store.presets.first(where: { $0.spots.contains(spot) }) else { return nil }
        toggleSelection(preset.id)
        return preset
    }

    func clearSelection() { selection = [] }

    // MARK: - Schalten

    func switchSelection(on: Bool) async {
        for preset in store.presets where selection.contains(preset.id) {
            await set(preset, on: on)
        }
    }

    func set(_ preset: LightPreset, on: Bool) async {
        if isLive {
            guard preset.isConfigured else {
                showToast("\(preset.name) ist noch nicht eingerichtet – nur Vorschau")
                apply(preset.id, on: on)
                return
            }
            do {
                try await session.setLight(preset, on: on)
            } catch {
                showToast("\(preset.name): \(error.localizedDescription)", isError: true)
                return
            }
        }
        apply(preset.id, on: on)
    }

    func allOff() async {
        await stopShow()
        if isLive {
            for preset in store.presets where onPresets.contains(preset.id) && preset.isConfigured {
                try? await session.setLight(preset, on: false)
            }
            await session.endAllSessions()
        }
        onPresets = []
    }

    private func apply(_ id: UUID, on: Bool) {
        if on { onPresets.insert(id) } else { onPresets.remove(id) }
    }

    // MARK: - Szenen

    /// Spielt eine Szene ab. `speed` 1 = Originaltempo, 2 = doppelt so schnell;
    /// `repeats` 0 = endlos, bis die Szene gestoppt wird.
    func play(_ show: LightShow, speed: Double = 1, repeats: Int = 1) {
        let previous = showTask
        previous?.cancel()
        showTask = Task { [weak self] in
            await previous?.value
            await self?.run(show, speed: max(0.25, speed), repeats: repeats)
        }
    }

    func stopShow() async {
        let task = showTask
        task?.cancel()
        await task?.value
        showTask = nil
    }

    private func run(_ show: LightShow, speed: Double, repeats: Int) async {
        await allOffQuietly()
        playingShow = show.id
        showProgress = 0
        var active: Set<UUID> = []
        let roundDuration = show.duration / speed
        let rounds = repeats <= 0 ? Int.max : repeats
        var round = 0

        while round < rounds, !Task.isCancelled {
            var elapsed = 0.0
            for original in show.steps {
                if Task.isCancelled { break }
                let step = LightShow.Step(spots: original.spots, duration: original.duration / speed)
                let started = Date()
                showSpots = step.spots
                let wanted = Set(store.presets.filter { !Set($0.spots).isDisjoint(with: step.spots) }.map(\.id))
                if isLive {
                    for preset in store.presets where preset.isConfigured && wanted.contains(preset.id) != active.contains(preset.id) {
                        try? await session.setLight(preset, on: wanted.contains(preset.id))
                    }
                }
                active = wanted
                // Die Zeit für die Befehle von der Schrittdauer abziehen, damit der Takt stimmt.
                let remaining = step.duration - Date().timeIntervalSince(started)
                if remaining > 0 { try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000)) }
                elapsed += step.duration
                // Endlos: Fortschritt pro Durchlauf; sonst über alle Wiederholungen
                showProgress = repeats <= 0
                    ? min(1, elapsed / roundDuration)
                    : min(1, (Double(round) * roundDuration + elapsed) / (roundDuration * Double(rounds)))
            }
            round += 1
        }

        if isLive {
            for preset in store.presets where preset.isConfigured && active.contains(preset.id) {
                try? await session.setLight(preset, on: false)
            }
        }
        showSpots = nil
        playingShow = nil
        showProgress = 0
    }

    private func allOffQuietly() async {
        if isLive {
            for preset in store.presets where onPresets.contains(preset.id) && preset.isConfigured {
                try? await session.setLight(preset, on: false)
            }
        }
        onPresets = []
    }

    // MARK: - Musik

    private var musicPresets: [LightPreset] = []
    private var musicDesired = false
    private var musicOn = false
    private var musicTask: Task<Void, Never>?
    private var musicOffTask: Task<Void, Never>?

    /// Schaltet die passenden Leuchten am Auto im Takt. Es wird immer nur der neueste Zustand gesendet,
    /// damit sich bei schnellen Beats keine Befehle stauen.
    func startMusicSync(spots: Set<LightSpot>) {
        stopMusicSync()
        musicPresets = store.presets.filter { $0.isConfigured && !Set($0.spots).isDisjoint(with: spots) }
        guard isLive, !musicPresets.isEmpty else { return }
        musicTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.musicDesired != self.musicOn {
                    let target = self.musicDesired
                    for preset in self.musicPresets {
                        try? await self.session.setLight(preset, on: target)
                    }
                    self.musicOn = target
                } else {
                    try? await Task.sleep(nanoseconds: 10_000_000)
                }
            }
        }
    }

    /// Ein Beat: Leuchten kurz an, nach `hold` Sekunden wieder aus.
    func musicBeat(hold: Double = 0.14) {
        guard musicTask != nil else { return }
        musicDesired = true
        musicOffTask?.cancel()
        musicOffTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(hold * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.musicDesired = false
        }
    }

    func stopMusicSync() {
        musicTask?.cancel()
        musicTask = nil
        musicOffTask?.cancel()
        musicDesired = false
        if musicOn {
            let presets = musicPresets
            musicOn = false
            Task { [weak self] in
                for preset in presets { try? await self?.session.setLight(preset, on: false) }
            }
        }
    }

    // MARK: - Hilfen

    func showToast(_ text: String, isError: Bool = false) {
        let toast = Toast(text: text, isError: isError)
        self.toast = toast
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            if self?.toast?.id == toast.id { self?.toast = nil }
        }
    }

    private func recompute() {
        let presets = store.presets
        litSpots = showSpots ?? Set(presets.filter { onPresets.contains($0.id) }.flatMap(\.spots))
        selectedSpots = Set(presets.filter { selection.contains($0.id) }.flatMap(\.spots))
    }
}
