import SwiftUI
import SceneKit

#if os(iOS)
private typealias TapRecognizer = UITapGestureRecognizer
private typealias PanRecognizer = UIPanGestureRecognizer
private typealias PinchRecognizer = UIPinchGestureRecognizer
#else
private typealias TapRecognizer = NSClickGestureRecognizer
private typealias PanRecognizer = NSPanGestureRecognizer
private typealias PinchRecognizer = NSMagnificationGestureRecognizer
#endif

/// SCNView mit Antippen (Leuchte wählen), Ziehen (drehen und neigen, mit Schwung) und Zwei-Finger-Zoom.
struct CarSceneView {
    let car: CarScene
    var paused = false
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
            switch recognizer.state {
            case .began:
                car.beginDrag()
            case .changed:
                let translation = recognizer.translation(in: view)
                car.drag(dx: Double(translation.x), dy: Double(translation.y))
                recognizer.setTranslation(.zero, in: view)
            case .ended, .cancelled, .failed:
                let velocity = recognizer.velocity(in: view)
                car.endDrag(velocityX: Double(velocity.x), velocityY: Double(velocity.y))
            default:
                break
            }
        }

        @objc fileprivate func handlePinch(_ recognizer: PinchRecognizer) {
            #if os(iOS)
            car.zoom(by: Double(recognizer.scale))
            recognizer.scale = 1
            #else
            car.zoom(by: 1 + Double(recognizer.magnification))
            recognizer.magnification = 0
            #endif
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(car: car, onTapSpot: onTapSpot)
    }

    private func makeView(_ coordinator: Coordinator) -> SCNView {
        let view = SCNView(frame: .zero)
        view.scene = car.scene
        view.pointOfView = car.cameraNode
        // 2× statt 3× Auflösung und 2× Kantenglättung: rund dreimal weniger GPU-Arbeit pro Bild,
        // auf dem dunklen, weichgezeichneten Studio-Look kaum sichtbar.
        view.antialiasingMode = .multisampling2X
        #if os(iOS)
        view.contentScaleFactor = min(2, UIScreen.main.scale)
        #endif
        view.backgroundColor = .black
        // ProMotion: bis zu 120 Bilder pro Sekunde (braucht CADisableMinimumFrameDurationOnPhone in der Info.plist).
        view.preferredFramesPerSecond = 120
        view.isPlaying = true
        view.addGestureRecognizer(TapRecognizer(target: coordinator, action: #selector(Coordinator.handleTap(_:))))
        let pan = PanRecognizer(target: coordinator, action: #selector(Coordinator.handlePan(_:)))
        let pinch = PinchRecognizer(target: coordinator, action: #selector(Coordinator.handlePinch(_:)))
        #if os(iOS)
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        pinch.delegate = coordinator
        #endif
        view.addGestureRecognizer(pan)
        view.addGestureRecognizer(pinch)
        coordinator.view = view
        return view
    }

    private func update(_ view: SCNView, _ coordinator: Coordinator) {
        coordinator.onTapSpot = onTapSpot
        if view.isPlaying == paused {
            view.isPlaying = !paused
            car.setPaused(paused)
        }
    }
}

#if os(iOS)
extension CarSceneView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
}

extension CarSceneView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateUIView(_ view: SCNView, context: Context) { update(view, context.coordinator) }
}
#else
extension CarSceneView: NSViewRepresentable {
    func makeNSView(context: Context) -> SCNView { makeView(context.coordinator) }
    func updateNSView(_ view: SCNView, context: Context) { update(view, context.coordinator) }
}
#endif
