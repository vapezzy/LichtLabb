import SwiftUI
import SceneKit

#if os(iOS)
private typealias TapRecognizer = UITapGestureRecognizer
private typealias PanRecognizer = UIPanGestureRecognizer
#else
private typealias TapRecognizer = NSClickGestureRecognizer
private typealias PanRecognizer = NSPanGestureRecognizer
#endif

/// SCNView mit Antippen (Leuchte wählen) und Wischen (um das Auto drehen).
struct CarSceneView {
    let car: CarScene
    var onTapSpot: (LightSpot?) -> Void

    final class Coordinator: NSObject {
        let car: CarScene
        var onTapSpot: (LightSpot?) -> Void
        weak var view: SCNView?

        init(car: CarScene, onTapSpot: @escaping (LightSpot?) -> Void) {
            self.car = car
            self.onTapSpot = onTapSpot
        }

        @objc fileprivate func handleTap(_ recognizer: TapRecognizer) {
            guard let view else { return }
            onTapSpot(car.spot(at: recognizer.location(in: view), in: view))
        }

        @objc fileprivate func handlePan(_ recognizer: PanRecognizer) {
            guard let view else { return }
            car.pan(by: Double(recognizer.translation(in: view).x))
            recognizer.setTranslation(.zero, in: view)
            if recognizer.state == .ended || recognizer.state == .cancelled {
                car.endPan()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(car: car, onTapSpot: onTapSpot)
    }

    private func makeView(_ coordinator: Coordinator) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = car.scene
        view.pointOfView = car.cameraNode
        view.antialiasingMode = .multisampling4X
        view.backgroundColor = .black
        view.preferredFramesPerSecond = 60
        view.isPlaying = true
        view.addGestureRecognizer(TapRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:))))
        view.addGestureRecognizer(PanRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:))))
        coordinator.view = view
        return view
    }
}

#if os(iOS)
extension CarSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateUIView(_ view: SCNView, context: Context) { context.coordinator.onTapSpot = onTapSpot }
}
#else
extension CarSceneView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateNSView(_ view: SCNView, context: Context) { context.coordinator.onTapSpot = onTapSpot }
}
#endif
