import SwiftUI

/// Unschärfe + Ausblenden + leichtes Skalieren – der Standard-Übergang der App.
private struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: active ? 18 : 0)
            .opacity(active ? 0 : 1)
            .scaleEffect(active ? 0.96 : 1)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFade(active: true), identity: BlurFade(active: false))
    }
}

extension View {
    /// Mattglas-Fläche mit feiner Lichtkante.
    func glass(cornerRadius: CGFloat = 24) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return self
            .background(.ultraThinMaterial, in: shape)
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
    }
}

extension LightTint {
    var color: Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}

extension PaintColor {
    var color: Color {
        Color(red: rgb.r, green: rgb.g, blue: rgb.b)
    }
}
