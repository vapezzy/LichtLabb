import SceneKit
import ModelIO
import QuartzCore

enum CameraFocus {
    case overview, front, rear
}

/// Ein schaltbarer Lichtpunkt im 3D-Modell.
private final class SpotNode {
    let root = SCNNode()
    var materials: [SCNMaterial] = []
    /// Günstiger Lichtschein auf dem Boden (statt einer echten Lichtquelle pro Leuchte)
    var glow: SCNNode?
    var halo = SCNNode()
    var sequential = false
    var isOn = false
}

private struct Part {
    let geometry: SCNGeometry
    let position: SCNVector3
    var euler = SCNVector3Zero
}

/// Stilisiertes F36 Gran Coupé als SceneKit-Szene: Studio-Boden mit Spiegelung,
/// HDR-Bloom, Tiefenschärfe und Kamerafahrten. Achsen: +x = vorne, +y = oben, -z = links.
final class CarScene: ObservableObject {
    let scene = SCNScene()
    let cameraNode = SCNNode()

    private let camera = SCNCamera()
    private let rig = SCNNode()
    private let target = SCNNode()
    private let car = SCNNode()
    private var rearGroup = SCNNode()
    private let paint = SCNMaterial()
    private var spots: [LightSpot: SpotNode] = [:]
    private var lit: Set<LightSpot> = []
    private var override: Set<LightSpot>?
    private var selected: Set<LightSpot> = []
    private var rearStyle: RearLightStyle?
    private(set) var focus: CameraFocus = .overview

    private var current = CarScene.shot(for: .overview)
    private var goal = CarScene.shot(for: .overview)
    private var velocity = (yaw: 0.0, elevation: 0.0)
    private var rate = CarScene.glideRate
    private var dragging = false
    private var idle = 0.0
    private var introRunning = false
    private var frameDriver: FrameDriver?
    private var musicSpots: Set<LightSpot> = []
    private var musicLevel = 0.0
    private var musicTarget = 0.0

    private static let onIntensity: CGFloat = 2.4
    private static let glowOpacity: CGFloat = 0.4
    private static let glowTexture = CarScene.makeGlowTexture()
    private static let offIntensity: CGFloat = 0.03

    init() {
        buildStage()
        buildCamera()
        buildBody()
        buildFrontLights()
        setRearStyle(.original)
        applyCamera()
        frameDriver = FrameDriver { [weak self] dt in self?.tick(dt) }
    }

    // MARK: - Öffentliche Steuerung

    func setLit(_ spots: Set<LightSpot>) {
        lit = spots
        render()
    }

    func setSelected(_ spots: Set<LightSpot>) {
        selected = spots
        for (spot, node) in self.spots {
            node.halo.removeAction(forKey: "fade")
            node.halo.runAction(.fadeOpacity(to: spots.contains(spot) ? 1 : 0, duration: 0.3), forKey: "fade")
        }
    }

    func setPaint(_ color: PaintColor) {
        SCNTransaction.begin()
        SCNTransaction.animationDuration = 0.8
        paint.diffuse.contents = PlatformColor(rgb: color.rgb)
        SCNTransaction.commit()
    }

    func setRearStyle(_ style: RearLightStyle) {
        guard style != rearStyle else { return }
        rearStyle = style
        rearGroup.removeFromParentNode()
        for spot in LightSpot.allCases where !spot.isFront { spots[spot] = nil }
        rearGroup = SCNNode()
        car.addChildNode(rearGroup)
        for side in [-1.0, 1.0] { buildRear(style, side: side) }
        addSpot(.rearFog, parts: [Part(geometry: box(0.02, 0.03, 0.10, chamfer: 0.01), position: v3(-2.35, 0.30, -0.62))], parent: rearGroup)

        // Neu gebaute Leuchten in den aktuellen Zustand bringen, mit kurzem Aufblenden.
        rearGroup.opacity = 0
        rearGroup.runAction(.fadeIn(duration: 0.6))
        render()
        setSelected(selected)
    }

    func focus(_ focus: CameraFocus) {
        self.focus = focus
        var shot = Self.shot(for: focus)
        shot.yaw = Self.nearest(shot.yaw, to: current.yaw)
        goal = shot
        velocity = (0, 0)
        rate = Self.glideRate
        idle = 0
    }

    /// Kinoreife Einfahrt: Kamera fliegt aus der Unschärfe heran, die Lichter erwachen nacheinander.
    func playIntro() {
        introRunning = true
        current = Orbit(yaw: -1.35, elevation: 0.02, distance: 15, targetY: 0.45)
        goal = current
        rate = 0.2
        applyCamera()
        camera.fStop = 1.8
        camera.wantsDepthOfField = true
        override = []
        render()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.focus = .overview
            self.goal = Self.shot(for: .overview)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            SCNTransaction.begin()
            SCNTransaction.animationDuration = 1.2
            self.camera.fStop = 22
            SCNTransaction.commit()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.3) {
            // Tiefenschärfe nur für die Intro-Fahrt, danach scharf und ohne Rauschen.
            self.camera.wantsDepthOfField = false
            self.introRunning = false
            self.rate = Self.glideRate
        }

        let eyes: Set<LightSpot> = [.angelEyeLeft, .angelEyeRight]
        let tails: Set<LightSpot> = [.tailLeft, .tailRight]
        let blink: Set<LightSpot> = [.blinkerFrontLeft, .blinkerFrontRight, .blinkerRearLeft, .blinkerRearRight]
        let sweep: [(Double, Set<LightSpot>?)] = [
            (1.4, eyes),
            (2.1, eyes.union(tails)),
            (2.7, eyes.union(tails).union(blink)),
            (3.1, eyes.union(tails)),
            (3.5, eyes.union(tails).union(blink)),
            (3.9, eyes.union(tails)),
            (5.4, nil),
        ]
        for (time, spots) in sweep {
            DispatchQueue.main.asyncAfter(deadline: .now() + time) {
                self.override = spots
                self.render()
            }
        }
    }

    // MARK: - Musik

    /// Diese Leuchten pulsieren mit der Musik statt dem normalen An/Aus zu folgen.
    func setMusicSpots(_ spots: Set<LightSpot>) {
        let released = musicSpots.subtracting(spots)
        musicSpots = spots
        // Freigegebene Leuchten wieder in ihren normalen Zustand bringen
        for spot in released {
            guard let node = self.spots[spot] else { continue }
            node.isOn = !(override ?? lit).contains(spot)
        }
        render()
    }

    /// Pegel 0…1 vom Musik-Analysator; ein Beat schickt 1.
    func pushMusicLevel(_ level: Double) {
        musicTarget = max(musicTarget, min(1, max(0, level)))
    }

    /// Hält die 3D-Darstellung an, z. B. wenn sie verdeckt ist – spart Akku und Leistung.
    func setPaused(_ paused: Bool) {
        frameDriver?.isPaused = paused
    }

    // MARK: - Gesten

    func beginDrag() {
        dragging = true
        velocity = (0, 0)
        idle = 0
    }

    /// Finger-Bewegung in Punkten: waagrecht dreht ums Auto, senkrecht neigt die Kamera.
    func drag(dx: Double, dy: Double) {
        goal.yaw -= dx * Self.yawPerPoint
        goal.elevation = Self.clamp(goal.elevation + dy * Self.elevationPerPoint, Self.elevationRange)
        idle = 0
    }

    /// Loslassen mit Schwung: Geschwindigkeit in Punkten pro Sekunde.
    func endDrag(velocityX: Double, velocityY: Double) {
        dragging = false
        rate = Self.followRate
        velocity = (
            yaw: Self.clamp(-velocityX * Self.yawPerPoint, -5...5),
            elevation: Self.clamp(velocityY * Self.elevationPerPoint, -3...3)
        )
        idle = 0
    }

    func zoom(by factor: Double) {
        guard factor > 0 else { return }
        goal.distance = Self.clamp(goal.distance / factor, Self.distanceRange)
        rate = Self.followRate
        idle = 0
    }

    func spot(at point: CGPoint, in view: SCNView) -> LightSpot? {
        let hits = view.hitTest(point, options: [
            .searchMode: SCNHitTestSearchMode.all.rawValue,
            .ignoreHiddenNodes: true,
        ])
        // Nur der vorderste Treffer zählt – sonst könnte man Leuchten durch das Auto hindurch wählen.
        guard let first = hits.first else { return nil }
        var node: SCNNode? = first.node
        while let current = node {
            if let name = current.name, name.hasPrefix("spot:") {
                return LightSpot(rawValue: String(name.dropFirst(5)))
            }
            node = current.parent
        }
        return nil
    }

    // MARK: - Kamera

    /// Kameraposition auf einer Kugel um das Auto.
    private struct Orbit {
        var yaw: Double
        var elevation: Double
        var distance: Double
        var targetY: Double
    }

    private static let yawPerPoint = 0.0085
    private static let elevationPerPoint = 0.005
    private static let elevationRange = 0.03...1.15
    private static let distanceRange = 3.4...11.0
    /// Wie schnell die Kamera ihrem Ziel folgt (pro Sekunde): beim Ziehen, nach dem Loslassen, bei Fahrten.
    private static let dragRate = 30.0
    private static let followRate = 14.0
    private static let glideRate = 2.6
    private static let orbitSpeed = 0.07

    private static func shot(for focus: CameraFocus) -> Orbit {
        switch focus {
        case .overview: return Orbit(yaw: 0.72, elevation: 0.35, distance: 6.6, targetY: -0.25)
        case .front: return Orbit(yaw: 0.42, elevation: 0.22, distance: 5.5, targetY: 0.0)
        case .rear: return Orbit(yaw: .pi - 0.42, elevation: 0.22, distance: 5.5, targetY: 0.1)
        }
    }

    /// Kürzesten Weg um das Auto nehmen.
    private static func nearest(_ yaw: Double, to reference: Double) -> Double {
        var result = yaw
        while result - reference > .pi { result -= 2 * .pi }
        while result - reference < -.pi { result += 2 * .pi }
        return result
    }

    private static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    /// Wird pro Bildschirm-Frame aufgerufen (auf ProMotion-Displays 120-mal pro Sekunde).
    private func tick(_ rawDelta: Double) {
        let dt = min(max(rawDelta, 0), 1.0 / 30)

        if !dragging {
            goal.yaw += velocity.yaw * dt
            goal.elevation = Self.clamp(goal.elevation + velocity.elevation * dt, Self.elevationRange)
            let decay = exp(-5.0 * dt)
            velocity.yaw *= decay
            velocity.elevation *= decay
            idle += dt
            // Langsamer Orbit in der Übersicht, sanft anlaufend nach 3 s Ruhe.
            if focus == .overview && !introRunning && idle > 3 {
                goal.yaw += Self.orbitSpeed * min(1, (idle - 3) / 2) * dt
            }
        }
        if introRunning { rate = min(1.6, rate + dt * 0.7) }

        let k = 1 - exp(-(dragging ? Self.dragRate : rate) * dt)
        current.yaw += (goal.yaw - current.yaw) * k
        current.elevation += (goal.elevation - current.elevation) * k
        current.distance += (goal.distance - current.distance) * k
        current.targetY += (goal.targetY - current.targetY) * k
        applyCamera()

        if !musicSpots.isEmpty {
            musicLevel = max(musicTarget, musicLevel * exp(-9 * dt))
            musicTarget = 0
            let intensity = Self.offIntensity + CGFloat(musicLevel) * Self.onIntensity
            for spot in musicSpots {
                guard let node = spots[spot] else { continue }
                node.materials.forEach { $0.emission.intensity = intensity }
                node.glow?.opacity = CGFloat(musicLevel) * Self.glowOpacity
            }
        }
    }

    private func applyCamera() {
        rig.eulerAngles = v3(0, current.yaw, 0)
        cameraNode.position = v3(current.distance * cos(current.elevation),
                                 current.targetY + current.distance * sin(current.elevation), 0)
        target.position = v3(0, current.targetY, 0)
        camera.focusDistance = CGFloat(current.distance)
    }

    // MARK: - Licht schalten

    private func render() {
        let active = override ?? lit
        for (spot, node) in spots where !musicSpots.contains(spot) {
            let on = active.contains(spot)
            guard on != node.isOn else { continue }
            node.isOn = on

            if on && node.sequential {
                // Dynamischer Blinker: Segmente laufen von innen nach außen.
                for (index, material) in node.materials.enumerated() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.045) { [weak node] in
                        guard let node, node.isOn else { return }
                        SCNTransaction.begin()
                        SCNTransaction.animationDuration = 0.08
                        material.emission.intensity = Self.onIntensity
                        SCNTransaction.commit()
                    }
                }
            }

            SCNTransaction.begin()
            SCNTransaction.animationDuration = on ? 0.25 : 0.5
            if !(on && node.sequential) {
                node.materials.forEach { $0.emission.intensity = on ? Self.onIntensity : Self.offIntensity }
            }
            node.glow?.opacity = on ? Self.glowOpacity : 0
            SCNTransaction.commit()
        }
    }

    // MARK: - Bühne

    private func buildStage() {
        let background = PlatformColor(red: 0.010, green: 0.012, blue: 0.018, alpha: 1)
        scene.background.contents = background
        scene.fogColor = background
        scene.fogStartDistance = 8
        scene.fogEndDistance = 24

        scene.lightingEnvironment.contents = MDLSkyCubeTexture(
            name: nil, channelEncoding: .uInt8, textureDimensions: vector_int2(256, 256),
            turbidity: 0.2, sunElevation: 0.6, upperAtmosphereScattering: 0.25, groundAlbedo: 0.05)
        scene.lightingEnvironment.intensity = 0.3

        let floor = SCNFloor()
        floor.reflectivity = 0.22
        floor.reflectionFalloffEnd = 2.5
        floor.reflectionResolutionScaleFactor = 0.4
        floor.materials = [material(PlatformColor(white: 0.006, alpha: 1), metalness: 0, roughness: 0.7)]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        let key = SCNLight()
        key.type = .spot
        key.intensity = 450
        key.spotInnerAngle = 30
        key.spotOuterAngle = 75
        key.color = PlatformColor(red: 0.9, green: 0.94, blue: 1, alpha: 1)
        key.castsShadow = true
        key.shadowRadius = 10
        key.shadowSampleCount = 4
        key.shadowMapSize = CGSize(width: 1024, height: 1024)
        key.shadowColor = PlatformColor(white: 0, alpha: 0.7)
        let keyNode = SCNNode()
        keyNode.light = key
        keyNode.position = v3(0.5, 7, 1.5)
        keyNode.constraints = [SCNLookAtConstraint(target: car)]
        scene.rootNode.addChildNode(keyNode)

        // Kühle Kantenlichter von hinten links und rechts
        for yaw in [2.4, -2.4] {
            let rim = SCNLight()
            rim.type = .directional
            rim.intensity = 350
            rim.color = PlatformColor(red: 0.55, green: 0.7, blue: 1, alpha: 1)
            let node = SCNNode()
            node.light = rim
            node.eulerAngles = v3(-0.35, yaw, 0)
            scene.rootNode.addChildNode(node)
        }

        let ambient = SCNLight()
        ambient.type = .ambient
        ambient.intensity = 80
        ambient.color = PlatformColor(red: 0.6, green: 0.65, blue: 0.8, alpha: 1)
        let ambientNode = SCNNode()
        ambientNode.light = ambient
        scene.rootNode.addChildNode(ambientNode)

        scene.rootNode.addChildNode(car)
    }

    private func buildCamera() {
        camera.zNear = 0.05
        camera.zFar = 100
        // Horizontaler Bildwinkel, damit das Auto auch im Hochformat ganz ins Bild passt.
        camera.projectionDirection = .horizontal
        camera.fieldOfView = 52
        camera.wantsHDR = true
        camera.bloomIntensity = 1.1
        camera.bloomThreshold = 0.75
        camera.bloomBlurRadius = 14
        camera.wantsDepthOfField = false
        camera.focalBlurSampleCount = 8
        camera.motionBlurIntensity = 0
        camera.contrast = 0.12
        camera.saturation = 1.05
        cameraNode.camera = camera

        scene.rootNode.addChildNode(target)
        scene.rootNode.addChildNode(rig)
        rig.addChildNode(cameraNode)
        let look = SCNLookAtConstraint(target: target)
        look.isGimbalLockEnabled = true
        cameraNode.constraints = [look]
    }

    // MARK: - Karosserie

    private func buildBody() {
        paint.lightingModel = .physicallyBased
        paint.metalness.contents = 0.6
        paint.roughness.contents = 0.3
        paint.clearCoat.contents = 1.0
        paint.clearCoatRoughness.contents = 0.05
        paint.diffuse.contents = PlatformColor(rgb: PaintColor.estorilBlau.rgb)

        // Seitenprofil (x = Länge, y = Höhe), wird über die Breite extrudiert.
        let profile: [CGPoint] = [
            CGPoint(x: 2.20, y: 0.20), CGPoint(x: 2.34, y: 0.30), CGPoint(x: 2.36, y: 0.52), CGPoint(x: 2.30, y: 0.70),
            CGPoint(x: 1.80, y: 0.80), CGPoint(x: 1.05, y: 0.88), CGPoint(x: 0.65, y: 1.12), CGPoint(x: 0.15, y: 1.37),
            CGPoint(x: -0.55, y: 1.39), CGPoint(x: -1.30, y: 1.18), CGPoint(x: -1.90, y: 1.00), CGPoint(x: -2.22, y: 0.98),
            CGPoint(x: -2.34, y: 0.85), CGPoint(x: -2.36, y: 0.55), CGPoint(x: -2.30, y: 0.28), CGPoint(x: -2.15, y: 0.20),
            CGPoint(x: -1.00, y: 0.18), CGPoint(x: 1.00, y: 0.18),
        ]
        let body = SCNShape(path: PathBuilder.smoothClosed(profile), extrusionDepth: 1.70)
        body.chamferRadius = 0.13
        body.chamferMode = .both
        body.chamferProfile = Self.roundChamfer()
        body.materials = [paint]
        car.addChildNode(SCNNode(geometry: body))

        // Glashaus mit schwarzem Dach, leicht breiter als die Karosserie
        let glassProfile: [CGPoint] = [
            CGPoint(x: 1.00, y: 0.90), CGPoint(x: 0.64, y: 1.14), CGPoint(x: 0.15, y: 1.39), CGPoint(x: -0.55, y: 1.41),
            CGPoint(x: -1.30, y: 1.20), CGPoint(x: -1.72, y: 1.04), CGPoint(x: -1.45, y: 0.96), CGPoint(x: 0.0, y: 0.94),
        ]
        let glass = SCNShape(path: PathBuilder.smoothClosed(glassProfile), extrusionDepth: 1.74)
        glass.chamferRadius = 0.07
        glass.chamferMode = .both
        glass.chamferProfile = Self.roundChamfer()
        glass.materials = [material(PlatformColor(red: 0.015, green: 0.02, blue: 0.025, alpha: 1), metalness: 0.1, roughness: 0.04)]
        car.addChildNode(SCNNode(geometry: glass))

        let arch = material(PlatformColor(white: 0.005, alpha: 1), metalness: 0, roughness: 0.9)
        for x in [1.40, -1.40] {
            for side in [-1.0, 1.0] {
                let shadow = SCNNode(geometry: SCNCylinder(radius: 0.37, height: 0.02))
                shadow.geometry?.materials = [arch]
                shadow.position = v3(x, 0.37, side * 0.852)
                shadow.eulerAngles = v3(.pi / 2, 0, 0)
                car.addChildNode(shadow)

                let wheel = makeWheel(side: side)
                wheel.position = v3(x, 0.335, side * 0.80)
                car.addChildNode(wheel)
            }
        }

        // Niere
        let chrome = material(PlatformColor(white: 0.8, alpha: 1), metalness: 1, roughness: 0.12)
        let black = material(PlatformColor(white: 0.01, alpha: 1), metalness: 0.2, roughness: 0.3)
        for side in [-1.0, 1.0] {
            let frame = SCNNode(geometry: box(0.04, 0.13, 0.17, chamfer: 0.05, material: chrome))
            frame.position = v3(2.33, 0.55, side * 0.11)
            let inset = SCNNode(geometry: box(0.04, 0.11, 0.14, chamfer: 0.04, material: black))
            inset.position = v3(2.337, 0.55, side * 0.11)
            car.addChildNode(frame)
            car.addChildNode(inset)

            let mirror = SCNNode(geometry: box(0.14, 0.08, 0.16, chamfer: 0.035, material: paint))
            mirror.position = v3(0.72, 1.0, side * 0.93)
            car.addChildNode(mirror)
        }
    }

    private func makeWheel(side: Double) -> SCNNode {
        let wheel = SCNNode()
        let tire = SCNNode(geometry: SCNTorus(ringRadius: 0.24, pipeRadius: 0.095))
        tire.geometry?.materials = [material(PlatformColor(white: 0.03, alpha: 1), metalness: 0, roughness: 0.9)]
        tire.eulerAngles = v3(.pi / 2, 0, 0)
        wheel.addChildNode(tire)

        let rim = SCNNode(geometry: SCNCylinder(radius: 0.22, height: 0.14))
        rim.geometry?.materials = [material(PlatformColor(white: 0.55, alpha: 1), metalness: 1, roughness: 0.3)]
        rim.eulerAngles = v3(.pi / 2, 0, 0)
        wheel.addChildNode(rim)

        let spokeMaterial = material(PlatformColor(white: 0.12, alpha: 1), metalness: 0.9, roughness: 0.35)
        for i in 0..<5 {
            let spoke = SCNNode(geometry: box(0.045, 0.40, 0.02, chamfer: 0.008, material: spokeMaterial))
            spoke.position = v3(0, 0, side * 0.075)
            spoke.eulerAngles = v3(0, 0, Double(i) * 2 * .pi / 5)
            wheel.addChildNode(spoke)
        }
        return wheel
    }

    // MARK: - Leuchten

    private func buildFrontLights() {
        let darkGlass = material(PlatformColor(white: 0.02, alpha: 1), metalness: 0.3, roughness: 0.08)
        let lens = material(PlatformColor(white: 0.4, alpha: 1), metalness: 1, roughness: 0.1)
        for side in [-1.0, 1.0] {
            let left = side < 0
            let housing = SCNNode(geometry: box(0.08, 0.15, 0.44, chamfer: 0.05, material: darkGlass))
            housing.position = v3(2.27, 0.665, side * 0.60)
            car.addChildNode(housing)

            let projector = SCNNode(geometry: SCNSphere(radius: 0.035))
            projector.geometry?.materials = [lens]
            projector.position = v3(2.29, 0.665, side * 0.71)
            car.addChildNode(projector)

            let rings = [0.50, 0.71].map {
                Part(geometry: SCNTorus(ringRadius: 0.068, pipeRadius: 0.009), position: v3(2.315, 0.665, side * $0), euler: v3(0, 0, .pi / 2))
            }
            addSpot(left ? .angelEyeLeft : .angelEyeRight, parts: rings, parent: car)
            addSpot(left ? .highBeamLeft : .highBeamRight,
                    parts: [Part(geometry: SCNSphere(radius: 0.03), position: v3(2.30, 0.665, side * 0.50))], parent: car)
            addSpot(left ? .blinkerFrontLeft : .blinkerFrontRight,
                    parts: [Part(geometry: box(0.02, 0.022, 0.13, chamfer: 0.008), position: v3(2.31, 0.585, side * 0.615))], parent: car)
            addSpot(left ? .fogLeft : .fogRight,
                    parts: [Part(geometry: SCNCylinder(radius: 0.045, height: 0.03), position: v3(2.35, 0.33, side * 0.66), euler: v3(0, 0, .pi / 2))],
                    parent: car)
        }
    }

    private func buildRear(_ style: RearLightStyle, side: Double) {
        let left = side < 0
        let x = -2.315
        let housingColor = style == .oled
            ? PlatformColor(red: 0.03, green: 0.02, blue: 0.02, alpha: 1)
            : PlatformColor(red: 0.16, green: 0.01, blue: 0.015, alpha: 1)
        let housing = SCNNode(geometry: box(0.06, 0.15, 0.50, chamfer: 0.04, material: material(housingColor, metalness: 0.2, roughness: 0.08)))
        housing.position = v3(-2.285, 0.87, side * 0.58)
        rearGroup.addChildNode(housing)

        let tail: LightSpot = left ? .tailLeft : .tailRight
        let brake: LightSpot = left ? .brakeLeft : .brakeRight
        let blink: LightSpot = left ? .blinkerRearLeft : .blinkerRearRight
        let reverse: LightSpot = left ? .reverseLeft : .reverseRight

        switch style {
        case .original, .led:
            var tailParts = [
                Part(geometry: box(0.02, 0.022, 0.38, chamfer: 0.008), position: v3(x, 0.915, side * 0.56)),
                Part(geometry: box(0.02, 0.10, 0.024, chamfer: 0.008), position: v3(x, 0.87, side * 0.785)),
            ]
            if style == .led {
                tailParts.append(Part(geometry: box(0.016, 0.008, 0.40, chamfer: 0.003), position: v3(x, 0.938, side * 0.57)))
            }
            addSpot(tail, parts: tailParts, parent: rearGroup)
            addSpot(brake, parts: [Part(geometry: box(0.02, 0.03, 0.26, chamfer: 0.01), position: v3(x, 0.87, side * 0.52))], parent: rearGroup)
            if style == .led {
                addSpot(blink, parts: segments(count: 6, inner: 0.46, outer: 0.78, y: 0.83, x: x, side: side, height: 0.018),
                        parent: rearGroup, sequential: true)
            } else {
                addSpot(blink, parts: [Part(geometry: box(0.02, 0.02, 0.16, chamfer: 0.006), position: v3(x, 0.83, side * 0.64))], parent: rearGroup)
            }
            addSpot(reverse, parts: [Part(geometry: box(0.02, 0.02, 0.09, chamfer: 0.006), position: v3(x, 0.83, side * 0.39))], parent: rearGroup)

        case .oled:
            // Schmale, gestaffelte OLED-Streifen
            let tailParts = [0.928, 0.908, 0.888].enumerated().map { index, y -> Part in
                let length = 0.44 - Double(index) * 0.03
                return Part(geometry: box(0.012, 0.007, length, chamfer: 0.003), position: v3(x, y, side * (0.80 - length / 2)))
            }
            addSpot(tail, parts: tailParts, parent: rearGroup)
            addSpot(brake, parts: [0.866, 0.850].map {
                Part(geometry: box(0.012, 0.01, 0.36, chamfer: 0.003), position: v3(x, $0, side * 0.62))
            }, parent: rearGroup)
            addSpot(blink, parts: segments(count: 8, inner: 0.44, outer: 0.80, y: 0.826, x: x, side: side, height: 0.012),
                    parent: rearGroup, sequential: true)
            addSpot(reverse, parts: [Part(geometry: box(0.012, 0.012, 0.07, chamfer: 0.003), position: v3(x, 0.826, side * 0.385))], parent: rearGroup)
        }
    }

    private func segments(count: Int, inner: Double, outer: Double, y: Double, x: Double, side: Double, height: Double) -> [Part] {
        let pitch = (outer - inner) / Double(count)
        return (0..<count).map { i in
            Part(geometry: box(0.014, height, pitch * 0.82, chamfer: 0.003),
                 position: v3(x, y, side * (inner + pitch * (Double(i) + 0.5))))
        }
    }

    private func addSpot(_ spot: LightSpot, parts: [Part], parent: SCNNode, sequential: Bool = false) {
        let node = SpotNode()
        node.sequential = sequential
        node.root.name = "spot:" + spot.rawValue
        let color = PlatformColor(rgb: spot.tint.rgb)

        var cx = 0.0, cy = 0.0, cz = 0.0
        for part in parts {
            let lightMaterial = SCNMaterial()
            lightMaterial.lightingModel = .physicallyBased
            lightMaterial.diffuse.contents = PlatformColor(rgb: spot.tint.rgb, scale: 0.15)
            lightMaterial.roughness.contents = 0.15
            lightMaterial.metalness.contents = 0.0
            lightMaterial.emission.contents = color
            lightMaterial.emission.intensity = Self.offIntensity
            part.geometry.materials = [lightMaterial]

            let partNode = SCNNode(geometry: part.geometry)
            partNode.position = part.position
            partNode.eulerAngles = part.euler
            node.root.addChildNode(partNode)
            node.materials.append(lightMaterial)

            cx += Double(part.position.x)
            cy += Double(part.position.y)
            cz += Double(part.position.z)
        }
        let n = Double(parts.count)
        let center = v3(cx / n, cy / n, cz / n)
        let radius = max(0.09, parts.map { part -> Double in
            let dx = Double(part.position.x) - cx / n
            let dy = Double(part.position.y) - cy / n
            let dz = Double(part.position.z) - cz / n
            return (dx * dx + dy * dy + dz * dz).squareRoot()
        }.max()! + 0.07)

        // Lichtschein auf dem Boden: additiv gemischte Fläche mit weichem Verlauf
        let glowMaterial = SCNMaterial()
        glowMaterial.lightingModel = .constant
        glowMaterial.diffuse.contents = Self.glowTexture
        glowMaterial.multiply.contents = color
        glowMaterial.blendMode = .add
        glowMaterial.writesToDepthBuffer = false
        let glowSize = CGFloat(spot.isFront ? 1.3 : 1.0)
        let glow = SCNNode(geometry: SCNPlane(width: glowSize, height: glowSize))
        glow.geometry?.materials = [glowMaterial]
        glow.eulerAngles = v3(-.pi / 2, 0, 0)
        glow.position = v3(cx / n + (spot.isFront ? 0.55 : -0.45), 0.004, cz / n)
        glow.opacity = 0
        glow.castsShadow = false
        node.root.addChildNode(glow)
        node.glow = glow

        // Unsichtbare Trefferfläche zum Antippen
        let hitMaterial = SCNMaterial()
        hitMaterial.colorBufferWriteMask = []
        hitMaterial.writesToDepthBuffer = false
        let hit = SCNNode(geometry: SCNSphere(radius: CGFloat(radius)))
        hit.geometry?.materials = [hitMaterial]
        hit.position = center
        node.root.addChildNode(hit)

        // Pulsierender Auswahl-Ring, der immer zur Kamera zeigt
        let ringMaterial = SCNMaterial()
        ringMaterial.lightingModel = .constant
        ringMaterial.diffuse.contents = PlatformColor(red: 0.35, green: 0.85, blue: 1, alpha: 1)
        ringMaterial.emission.contents = PlatformColor(red: 0.35, green: 0.85, blue: 1, alpha: 1)
        ringMaterial.emission.intensity = 2
        ringMaterial.writesToDepthBuffer = false
        let ring = SCNNode(geometry: SCNTorus(ringRadius: CGFloat(radius), pipeRadius: 0.006))
        ring.geometry?.materials = [ringMaterial]
        ring.eulerAngles = v3(.pi / 2, 0, 0)
        let grow = SCNAction.scale(to: 1.12, duration: 0.7)
        grow.timingMode = .easeInEaseOut
        let shrink = SCNAction.scale(to: 1.0, duration: 0.7)
        shrink.timingMode = .easeInEaseOut
        ring.runAction(.repeatForever(.sequence([grow, shrink])))

        let halo = SCNNode()
        halo.position = center
        halo.constraints = [SCNBillboardConstraint()]
        halo.opacity = 0
        halo.addChildNode(ring)
        node.root.addChildNode(halo)
        node.halo = halo

        parent.addChildNode(node.root)
        spots[spot] = node
    }

    // MARK: - Hilfen

    private func box(_ width: Double, _ height: Double, _ length: Double, chamfer: Double, material: SCNMaterial? = nil) -> SCNBox {
        let box = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(length), chamferRadius: CGFloat(chamfer))
        if let material { box.materials = [material] }
        return box
    }

    private func material(_ color: PlatformColor, metalness: Double, roughness: Double) -> SCNMaterial {
        let material = SCNMaterial()
        material.lightingModel = .physicallyBased
        material.diffuse.contents = color
        material.metalness.contents = metalness
        material.roughness.contents = roughness
        return material
    }

    /// Weicher radialer Verlauf (weiß → transparent) für den Bodenschein.
    private static func makeGlowTexture() -> CGImage? {
        let size = 128
        guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [CGColor(red: 1, green: 1, blue: 1, alpha: 1),
                                                 CGColor(red: 1, green: 1, blue: 1, alpha: 0.25),
                                                 CGColor(red: 1, green: 1, blue: 1, alpha: 0)] as CFArray,
                                        locations: [0, 0.35, 1])
        else { return nil }
        let center = CGPoint(x: size / 2, y: size / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center,
                                   endRadius: CGFloat(size) / 2, options: [])
        return context.makeImage()
    }

    /// Runde statt gerader Fase an den Kanten der extrudierten Formen.
    private static func roundChamfer() -> PlatformBezierPath {
        var builder = PathBuilder()
        builder.move(CGPoint(x: 0, y: 1))
        builder.quad(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 1, y: 1))
        return builder.path
    }
}

/// Taktgeber pro Bildschirm-Frame – auf ProMotion-Geräten mit bis zu 120 Hz.
private final class FrameDriver: NSObject {
    private let onFrame: (Double) -> Void
    private var last: CFTimeInterval = 0

    var isPaused = false {
        didSet {
            last = 0
            #if os(iOS)
            link?.isPaused = isPaused
            #endif
        }
    }
    #if os(iOS)
    private var link: CADisplayLink?
    #else
    private var timer: Timer?
    #endif

    init(onFrame: @escaping (Double) -> Void) {
        self.onFrame = onFrame
        super.init()
        #if os(iOS)
        let link = CADisplayLink(target: self, selector: #selector(step(_:)))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 80, maximum: 120, preferred: 120)
        link.add(to: .main, forMode: .common)
        self.link = link
        #else
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 120, repeats: true) { [weak self] _ in
            self?.advance(to: CACurrentMediaTime())
        }
        #endif
    }

    #if os(iOS)
    @objc private func step(_ link: CADisplayLink) {
        advance(to: link.timestamp)
    }
    #endif

    private func advance(to now: CFTimeInterval) {
        guard !isPaused else { return }
        let delta = last == 0 ? 1.0 / 120 : now - last
        last = now
        onFrame(delta)
    }
}
