import SwiftUI

/// Gezeichnete DPF-Kontrollleuchte (Filterkasten mit Rußpunkten, Rohr links und rechts).
/// Übernimmt die Vordergrundfarbe bzw. den Verlauf aus `.foregroundStyle`.
struct DPFLampIcon: View {
    var size: CGFloat = 20

    var body: some View {
        Canvas { ctx, s in
            let w = s.width, h = s.height
            let line = StrokeStyle(lineWidth: max(1.4, w * 0.085), lineCap: .round, lineJoin: .round)
            let box = CGRect(x: w * 0.2, y: h * 0.2, width: w * 0.6, height: h * 0.6)
            var outline = Path(roundedRect: box, cornerRadius: w * 0.12, style: .continuous)
            // Rohre ein/aus
            outline.move(to: CGPoint(x: w * 0.03, y: h * 0.5))
            outline.addLine(to: CGPoint(x: box.minX, y: h * 0.5))
            outline.move(to: CGPoint(x: box.maxX, y: h * 0.5))
            outline.addLine(to: CGPoint(x: w * 0.97, y: h * 0.5))
            ctx.stroke(outline, with: .foreground, style: line)
            // Rußpunkte 3 × 2
            let r = w * 0.05
            for row in 0..<2 {
                for col in 0..<3 {
                    let c = CGPoint(x: box.minX + box.width * (0.25 + 0.25 * CGFloat(col)),
                                    y: box.minY + box.height * (0.33 + 0.34 * CGFloat(row)))
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: .foreground)
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Sprechblase und kleiner Mechaniker (Kenji schaut nach rechts, zum DPF-Knopf daneben).
/// Die Figur wird einmal gezeichnet (kein Bild-für-Bild-Neuzeichnen) und wippt per Core-Animation.
struct CrewHint: View {
    var text: String

    @State private var bob = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            Text(text)
                .font(Theme.rounded(12, weight: .bold))
                .foregroundStyle(.black)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    SideBubbleShape()
                        .fill(LinearGradient(colors: [.white, Color(red: 0.9, green: 0.94, blue: 1)],
                                             startPoint: .top, endPoint: .bottom))
                )
                .padding(.bottom, 20)

            Canvas { ctx, size in
                MechanicsLoader().drawPortrait(ctx, size: size)
            }
            .frame(width: 40, height: 52)
            .offset(y: bob ? -2 : 1)
            .rotationEffect(.degrees(bob ? 3 : -2), anchor: .bottom)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { bob = true }
        }
    }
}

/// Sprechblase mit Spitze nach rechts unten (zur Figur).
private struct SideBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(roundedRect: rect, cornerRadius: 12, style: .continuous)
        p.move(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 14))
        p.addLine(to: CGPoint(x: rect.maxX + 7, y: rect.maxY - 2))
        p.addLine(to: CGPoint(x: rect.maxX - 12, y: rect.maxY - 3))
        p.closeSubpath()
        return p
    }
}
