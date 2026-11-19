import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Farbsatz eines Designs. `accent → accentDeep → violet → magenta` bildet den Markenverlauf.
struct Palette: Equatable {
    var background: Color
    var accent: Color
    var accentDeep: Color
    var violet: Color
    var magenta: Color
    /// Mittelton im Überschriften-Verlauf
    var titleMid: Color
    /// Verlauf gefüllter Knöpfe (leer = Dunkel → Mitte → Akzent aus dem Markenverlauf)
    var buttonColors: [Color] = []
    /// Schrift auf gefüllten Knöpfen
    var onButton: Color = .white

    /// Aktuell gewähltes Design – wird von `Theme` gelesen.
    static var current: Palette = .original

    static let original = Palette(
        background: Color(red: 0.027, green: 0.031, blue: 0.045),
        accent: Color(red: 0.36, green: 0.92, blue: 1.0),
        accentDeep: Color(red: 0.27, green: 0.45, blue: 1.0),
        violet: Color(red: 0.6, green: 0.38, blue: 1.0),
        magenta: Color(red: 1.0, green: 0.34, blue: 0.74),
        titleMid: Color(red: 0.75, green: 0.93, blue: 1))

    /// Weiß, Hellblau, Dunkelblau, Rot – die drei Streifen
    static let mColours = Palette(
        background: Color(red: 0.02, green: 0.03, blue: 0.06),
        accent: Color(red: 0.13, green: 0.62, blue: 0.95),
        accentDeep: Color(red: 0.12, green: 0.24, blue: 0.62),
        violet: Color(red: 0.2, green: 0.38, blue: 0.86),
        magenta: Color(red: 0.92, green: 0.16, blue: 0.13),
        titleMid: Color(red: 0.72, green: 0.86, blue: 1))

    /// Schwarz und Weiß mit Silber
    static let amgColours = Palette(
        background: Color(red: 0.012, green: 0.012, blue: 0.014),
        accent: Color(red: 0.93, green: 0.94, blue: 0.96),
        accentDeep: Color(red: 0.42, green: 0.43, blue: 0.46),
        violet: Color(red: 0.7, green: 0.71, blue: 0.74),
        magenta: Color(red: 0.98, green: 0.98, blue: 1.0),
        titleMid: Color(red: 0.82, green: 0.83, blue: 0.86),
        buttonColors: [Color(red: 0.78, green: 0.79, blue: 0.82), Color(red: 0.98, green: 0.98, blue: 1.0)],
        onButton: .black)

    /// Rot und Weiß
    static let sLineColours = Palette(
        background: Color(red: 0.035, green: 0.02, blue: 0.025),
        accent: Color(red: 0.93, green: 0.12, blue: 0.18),
        accentDeep: Color(red: 0.55, green: 0.03, blue: 0.08),
        violet: Color(red: 0.98, green: 0.42, blue: 0.45),
        magenta: Color(red: 0.97, green: 0.96, blue: 0.97),
        titleMid: Color(red: 1, green: 0.8, blue: 0.82),
        buttonColors: [Color(red: 0.55, green: 0.03, blue: 0.08), Color(red: 0.93, green: 0.12, blue: 0.18)])

    /// Eigenes Design aus zwei Farben
    static func custom(primary: Color, secondary: Color) -> Palette {
        // Helle Farben (z. B. Gelb, Weiß) bekommen dunkle Schrift auf Knöpfen
        let mid = primary.mix(with: secondary, by: 0.5)
        let rgb = mid.rgba ?? [0, 0, 0, 1]
        let luminance = 0.2126 * rgb[0] + 0.7152 * rgb[1] + 0.0722 * rgb[2]
        return Palette(
            background: Color(red: 0.027, green: 0.031, blue: 0.045),
            accent: primary,
            accentDeep: primary.mix(with: .black, by: 0.4),
            violet: primary.mix(with: secondary, by: 0.5),
            magenta: secondary,
            titleMid: primary.mix(with: .white, by: 0.6),
            onButton: luminance > 0.6 ? .black : .white)
    }
}

/// Gewähltes Design, gespeichert auf dem Gerät.
@MainActor
final class ThemeStore: ObservableObject {
    enum Choice: String, CaseIterable, Identifiable {
        case original, m, amg, sLine, custom
        var id: String { rawValue }

        var title: String {
            switch self {
            case .original: return "RideReader"
            case .m: return "M Colours"
            case .amg: return "AMG Colours"
            case .sLine: return "S-Line Colours"
            case .custom: return "Eigene Farben"
            }
        }
    }

    @Published private(set) var choice: Choice
    @Published private(set) var primary: Color
    @Published private(set) var secondary: Color
    @Published private(set) var customName: String
    /// Ändert sich bei jedem Designwechsel – die Oberfläche wird damit neu aufgebaut
    @Published private(set) var revision = 0

    private var applyTask: Task<Void, Never>?

    init() {
        let defaults = UserDefaults.standard
        choice = Choice(rawValue: defaults.string(forKey: "theme") ?? "") ?? .original
        primary = Self.loadColor("themePrimary") ?? Color(red: 0.2, green: 0.85, blue: 0.6)
        secondary = Self.loadColor("themeSecondary") ?? Color(red: 1.0, green: 0.75, blue: 0.2)
        customName = defaults.string(forKey: "themeName") ?? ""
        Palette.current = palette(for: choice)
        WidgetBridge.themeChanged(edition: editionLabel)
    }

    /// Text unter dem Schriftzug auf „Zuhause“, z. B. „M Colours Edition“
    var editionLabel: String? {
        switch choice {
        case .original: return nil
        case .m: return "M Colours Edition"
        case .amg: return "AMG Colours Edition"
        case .sLine: return "S-Line Colours Edition"
        case .custom:
            let name = customName.trimmingCharacters(in: .whitespaces)
            return "\(name.isEmpty ? "Custom" : name) Colours Edition"
        }
    }

    func palette(for choice: Choice) -> Palette {
        switch choice {
        case .original: return .original
        case .m: return .mColours
        case .amg: return .amgColours
        case .sLine: return .sLineColours
        case .custom: return .custom(primary: primary, secondary: secondary)
        }
    }

    func select(_ newChoice: Choice) {
        guard newChoice != choice else { return }
        choice = newChoice
        UserDefaults.standard.set(newChoice.rawValue, forKey: "theme")
        apply()
    }

    func setPrimary(_ color: Color) {
        primary = color
        Self.saveColor(color, "themePrimary")
        applyDebounced()
    }

    func setSecondary(_ color: Color) {
        secondary = color
        Self.saveColor(color, "themeSecondary")
        applyDebounced()
    }

    func setCustomName(_ name: String) {
        customName = String(name.prefix(18))
        UserDefaults.standard.set(customName, forKey: "themeName")
    }

    private func apply() {
        Palette.current = palette(for: choice)
        WidgetBridge.themeChanged(edition: editionLabel)
        withAnimation(.easeInOut(duration: 0.4)) { revision += 1 }
    }

    /// Beim Ziehen im Farbwähler nicht bei jedem Zwischenschritt neu aufbauen
    private func applyDebounced() {
        guard choice == .custom else { return }
        applyTask?.cancel()
        applyTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            self?.apply()
        }
    }

    // MARK: - Farben speichern

    private static func saveColor(_ color: Color, _ key: String) {
        guard let rgba = color.rgba else { return }
        UserDefaults.standard.set(rgba, forKey: key)
    }

    private static func loadColor(_ key: String) -> Color? {
        guard let v = UserDefaults.standard.array(forKey: key) as? [Double], v.count == 4 else { return nil }
        return Color(.sRGB, red: v[0], green: v[1], blue: v[2], opacity: v[3])
    }
}

extension Color {
    /// sRGB-Komponenten 0…1
    var rgba: [Double]? {
        #if canImport(UIKit)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        return [Double(r), Double(g), Double(b), Double(a)]
        #elseif canImport(AppKit)
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return nil }
        return [Double(c.redComponent), Double(c.greenComponent), Double(c.blueComponent), Double(c.alphaComponent)]
        #else
        return nil
        #endif
    }

    /// Mischt zwei Farben (0 = self, 1 = other)
    func mix(with other: Color, by amount: Double) -> Color {
        guard let a = rgba, let b = other.rgba else { return self }
        let t = min(max(amount, 0), 1)
        return Color(.sRGB, red: a[0] + (b[0] - a[0]) * t, green: a[1] + (b[1] - a[1]) * t,
                     blue: a[2] + (b[2] - a[2]) * t, opacity: 1)
    }
}

/// Auswahl der Designs in den Einstellungen.
struct ThemePicker: View {
    @EnvironmentObject private var theme: ThemeStore

    var body: some View {
        VStack(spacing: 10) {
            ForEach(ThemeStore.Choice.allCases) { choice in
                Button {
                    Haptics.tap()
                    theme.select(choice)
                } label: {
                    HStack(spacing: 14) {
                        swatch(for: choice)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(choice.title)
                                .font(Theme.rounded(15, weight: .bold))
                            Text(subtitle(choice))
                                .font(Theme.rounded(12, weight: .medium))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: theme.choice == choice ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(theme.choice == choice ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(Color.white.opacity(0.25)))
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.white.opacity(theme.choice == choice ? 0.08 : 0.03))
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            }

            if theme.choice == .custom {
                VStack(spacing: 12) {
                    ColorPicker(selection: Binding(get: { theme.primary }, set: { theme.setPrimary($0) }), supportsOpacity: false) {
                        Label("Hauptfarbe", systemImage: "paintpalette.fill")
                            .font(Theme.rounded(14, weight: .semibold))
                    }
                    ColorPicker(selection: Binding(get: { theme.secondary }, set: { theme.setSecondary($0) }), supportsOpacity: false) {
                        Label("Zweitfarbe", systemImage: "paintbrush.fill")
                            .font(Theme.rounded(14, weight: .semibold))
                    }
                    HStack {
                        Label("Name", systemImage: "textformat")
                            .font(Theme.rounded(14, weight: .semibold))
                        TextField("Custom", text: Binding(get: { theme.customName }, set: { theme.setCustomName($0) }))
                            .multilineTextAlignment(.trailing)
                            .font(Theme.rounded(14, weight: .medium))
                    }
                    Text("Auf „Zuhause“ steht dann: \(theme.editionLabel ?? "")")
                        .font(Theme.rounded(12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(.white.opacity(0.05)))
                .transition(.blurFade)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: theme.choice)
    }

    private func subtitle(_ choice: ThemeStore.Choice) -> String {
        switch choice {
        case .original: return "Cyan, Violett, Magenta"
        case .m: return "Weiß, Blau und Rot"
        case .amg: return "Schwarz und Weiß"
        case .sLine: return "Rot und Weiß"
        case .custom: return "Mit dem Farbwähler selbst gemischt"
        }
    }

    /// Farbvorschau: Streifen des jeweiligen Designs
    private func swatch(for choice: ThemeStore.Choice) -> some View {
        let p = theme.palette(for: choice)
        let stripes: [Color] = {
            switch choice {
            case .m: return [p.accent, p.accentDeep, p.magenta]
            case .amg: return [p.magenta, p.accentDeep, Color(white: 0.08)]
            case .sLine: return [p.accent, p.magenta, p.accent]
            default: return [p.accent, p.violet, p.magenta]
            }
        }()
        return HStack(spacing: 3) {
            ForEach(stripes.indices, id: \.self) { i in
                Capsule()
                    .fill(stripes[i])
                    .frame(width: 7, height: 34)
                    .rotationEffect(.degrees(18))
            }
        }
        .frame(width: 44, height: 44)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(p.background))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white.opacity(0.15)))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
