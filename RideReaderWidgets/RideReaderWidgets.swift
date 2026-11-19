#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

@main
struct RideReaderWidgetBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        RegenLiveActivity()
    }
}

// MARK: - Farben

private struct WidgetColors {
    let accent: Color
    let mid: Color
    let end: Color

    init(_ snapshot: WidgetShared.Snapshot) {
        func color(_ i: Int, _ fallback: Color) -> Color {
            guard let c = snapshot.colors, c.count > i, c[i].count >= 3 else { return fallback }
            return Color(.sRGB, red: c[i][0], green: c[i][1], blue: c[i][2], opacity: 1)
        }
        accent = color(0, Color(red: 0.36, green: 0.92, blue: 1.0))
        mid = color(1, Color(red: 0.6, green: 0.38, blue: 1.0))
        end = color(2, Color(red: 1.0, green: 0.34, blue: 0.74))
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [accent, mid, end], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

private let widgetBase = Color(red: 0.03, green: 0.035, blue: 0.05)
private let faultOrange = Color(red: 1.0, green: 0.6, blue: 0.14)
private let severeRed = Color(red: 1.0, green: 0.25, blue: 0.3)
private let okGreen = Color(red: 0.32, green: 0.95, blue: 0.62)

private extension View {
    /// iOS 17 verlangt einen Container-Hintergrund, iOS 16 kennt ihn noch nicht.
    @ViewBuilder
    func widgetBackground<B: View>(_ view: B) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            containerBackground(for: .widget) { view }
        } else {
            self.background(view)
        }
    }
}

private func volts(_ v: Double?) -> String {
    guard let v else { return "–" }
    return String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")
}

// MARK: - Status-Widget

struct StatusEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetShared.Snapshot
}

struct StatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: Date(), snapshot: .init(voltage: 12.6, voltageDate: Date(), faults: 2, severe: 0,
                                                  scanDate: Date(), dpfLoad: 63, regenerating: false, dpfDate: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : StatusEntry(date: Date(), snapshot: WidgetShared.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        let entry = StatusEntry(date: Date(), snapshot: WidgetShared.load())
        // Die App lädt die Widgets bei neuen Werten selbst neu; sonst alle 30 min
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(1800))))
    }
}

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetShared.kind, provider: StatusProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("RideReader")
        .description("Batterie, Fehler und Rußfilter auf einen Blick.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

struct StatusWidgetView: View {
    let entry: StatusEntry
    @Environment(\.widgetFamily) private var family

    private var s: WidgetShared.Snapshot { entry.snapshot }
    private var colors: WidgetColors { WidgetColors(s) }

    private var faultColor: Color {
        guard let faults = s.faults else { return .gray }
        if faults == 0 { return okGreen }
        return (s.severe ?? 0) > 0 ? severeRed : faultOrange
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Text("\(volts(s.voltage)) V · \(s.faults.map { "\($0) Fehler" } ?? "keine Kontrolle")\(s.regenerating ? " · DPF regeneriert" : "")")
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        case .systemMedium:
            medium
        default:
            small
        }
    }

    // Sperrbildschirm

    private var circular: some View {
        Gauge(value: min(max(s.voltage ?? 11.5, 11.5), 14.8), in: 11.5...14.8) {
            Image(systemName: "minus.plus.batteryblock.fill")
        } currentValueLabel: {
            Text(volts(s.voltage))
        }
        .gaugeStyle(.accessoryCircular)
        .widgetBackground(Color.clear)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("RIDEREADER").font(.system(size: 11, weight: .black)).italic()
            Text("\(volts(s.voltage)) V · \(s.faults.map { "\($0) Fehler" } ?? "–")")
                .font(.system(size: 15, weight: .bold))
            Text(s.regenerating ? "DPF regeneriert gerade" : s.dpfLoad.map { "DPF \(Int($0)) % beladen" } ?? "DPF –")
                .font(.system(size: 12, weight: .medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetBackground(Color.clear)
    }

    // Startbildschirm

    private var logo: some View {
        Text("RIDEREADER")
            .font(.system(size: 12, weight: .black).width(.expanded))
            .italic()
            .foregroundStyle(LinearGradient(colors: [.white, colors.accent, colors.end], startPoint: .leading, endPoint: .trailing))
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var batteryBlock: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(volts(s.voltage))
                    .font(.system(size: 34, weight: .heavy).width(.expanded))
                    .foregroundStyle(LinearGradient(colors: [.white, colors.accent], startPoint: .top, endPoint: .bottom))
                    .minimumScaleFactor(0.6)
                Text("V").font(.system(size: 15, weight: .bold)).foregroundStyle(.white.opacity(0.55))
            }
            if let date = s.voltageDate {
                Text(date, style: .relative)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
            } else {
                Text("Batterie").font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    private var faultChip: some View {
        HStack(spacing: 5) {
            Circle().fill(faultColor).frame(width: 7, height: 7)
            Text(s.faults.map { $0 == 0 ? "Keine Fehler" : "\($0) Fehler" } ?? "Keine Kontrolle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(faultColor)
                .lineLimit(1)
        }
    }

    private var dpfChip: some View {
        HStack(spacing: 5) {
            Image(systemName: s.regenerating ? "flame.fill" : "aqi.medium")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(s.regenerating ? faultOrange : colors.mid)
            Text(s.regenerating ? "Regeneriert" : s.dpfLoad.map { "DPF \(Int($0)) %" } ?? "DPF –")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.85))
                .lineLimit(1)
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            logo
            Spacer(minLength: 0)
            batteryBlock
            Spacer(minLength: 0)
            faultChip
            dpfChip
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .widgetBackground(widgetBackdrop)
    }

    private var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                logo
                if let edition = s.edition {
                    Text(edition).font(.system(size: 9, weight: .light)).tracking(1.2).foregroundStyle(.white.opacity(0.6))
                }
                Spacer(minLength: 0)
                batteryBlock
            }
            Spacer(minLength: 0)
            VStack(alignment: .leading, spacing: 10) {
                Spacer(minLength: 0)
                faultChip
                if let date = s.scanDate {
                    Text(date, style: .relative).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
                dpfChip
                Spacer(minLength: 0)
            }
            dpfRing
        }
        .foregroundStyle(.white)
        .widgetBackground(widgetBackdrop)
    }

    private var dpfRing: some View {
        let fraction = min(max((s.dpfLoad ?? 0) / 100, 0), 1)
        return ZStack {
            Circle().trim(from: 0, to: 0.75).stroke(.white.opacity(0.12), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle().trim(from: 0, to: 0.75 * fraction)
                .stroke(LinearGradient(colors: [okGreen, faultOrange, severeRed], startPoint: .leading, endPoint: .trailing),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(135))
            VStack(spacing: 0) {
                Text(s.dpfLoad.map { "\(Int($0))" } ?? "–").font(.system(size: 18, weight: .heavy))
                Text("DPF %").font(.system(size: 8, weight: .bold)).foregroundStyle(.white.opacity(0.5))
            }
        }
        .frame(width: 70, height: 70)
    }

    private var widgetBackdrop: some View {
        ZStack {
            widgetBase
            RadialGradient(colors: [colors.accent.opacity(0.35), .clear], center: .topLeading, startRadius: 0, endRadius: 160)
            RadialGradient(colors: [colors.end.opacity(0.25), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 160)
        }
    }
}

// MARK: - Live-Aktivität: Regeneration

struct RegenLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RegenActivityAttributes.self) { context in
            // Sperrbildschirm / Banner
            HStack(spacing: 14) {
                Image(systemName: context.state.finished ? "checkmark.seal.fill" : "flame.fill")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(context.state.finished ? okGreen : faultOrange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(context.state.finished ? "Regeneration fertig" : "Rußfilter regeneriert")
                        .font(.system(size: 16, weight: .bold))
                    Text(context.state.finished ? "Du kannst jetzt normal abstellen." : "Motor jetzt nicht abstellen.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.75))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 18, weight: .heavy).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                    if let temp = context.state.inletTemp {
                        Text("\(Int(temp)) °C").font(.system(size: 12, weight: .semibold)).foregroundStyle(faultOrange)
                    }
                }
            }
            .padding(16)
            .foregroundStyle(.white)
            .activityBackgroundTint(Color(red: 0.12, green: 0.05, blue: 0.04))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("DPF", systemImage: "flame.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(faultOrange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.attributes.startedAt, style: .timer)
                        .font(.system(size: 14, weight: .heavy).monospacedDigit())
                        .multilineTextAlignment(.trailing)
                        .frame(width: 60)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.finished ? "Fertig – du kannst abstellen." : "Regeneration läuft – nicht abstellen.")
                            .font(.system(size: 13, weight: .semibold))
                        Spacer()
                        if let temp = context.state.inletTemp {
                            Text("\(Int(temp)) °C").font(.system(size: 13, weight: .bold)).foregroundStyle(faultOrange)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill").foregroundStyle(faultOrange)
            } compactTrailing: {
                Text(context.attributes.startedAt, style: .timer)
                    .font(.system(size: 13, weight: .bold).monospacedDigit())
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "flame.fill").foregroundStyle(faultOrange)
            }
            .keylineTint(faultOrange)
        }
    }
}
#endif
