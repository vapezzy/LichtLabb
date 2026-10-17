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

    func play(_ show: LightShow) {
        let previous = showTask
        previous?.cancel()
        showTask = Task { [weak self] in
            await previous?.value
            await self?.run(show)
        }
    }

    func stopShow() async {
        let task = showTask
        task?.cancel()
        await task?.value
        showTask = nil
    }

    private func run(_ show: LightShow) async {
        await allOffQuietly()
        playingShow = show.id
        showProgress = 0
        var active: Set<UUID> = []
        var elapsed = 0.0

        for step in show.steps {
            if Task.isCancelled { break }
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
            showProgress = min(1, elapsed / show.duration)
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
