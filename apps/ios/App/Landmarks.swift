import SwiftUI
import SceneKit
import MuralCore

/// The floating figure on the Talk screen: the language's landmark when the app knows it, the
/// orb otherwise. A module names its landmark with `LanguageModule.landmarkID`, so a new language
/// gets the orb until someone builds its scene.
struct LanguageFigure: View {
    let language: LanguageModule
    var energy: Double = 0
    var listening = false
    var active = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Follows the scene's sunrise, so the sky behind the island warms as its sun climbs.
    @State private var risen = false
    var body: some View {
        if let id = language.landmarkID, let build = Landmarks.all[id] {
            ZStack {
                // The morning sky behind the island: cheap in SwiftUI, and it lifts the scene off the
                // black page. Gold low down where the sun is rising, rose and violet above.
                // It is drawn larger than the slot, like the scene, so the glow reaches past the island.
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height) * LandmarkView.overscan
                    let strength = (risen ? 1 : 0.45) * (1 + energy * 0.35)
                    // Fades out inside its frame, so no edge of the gradient is ever cut off.
                    RadialGradient(stops: Landmarks.sky.map { .init(color: $0.color.opacity($0.opacity * strength), location: $0.location) },
                                   center: UnitPoint(x: 0.5, y: 0.56), startRadius: 0, endRadius: side * 0.47)
                        .frame(width: geometry.size.width * LandmarkView.overscan, height: geometry.size.height * LandmarkView.overscan)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }
                .onAppear { withAnimation(reduceMotion ? nil : .easeOut(duration: Sunrise.duration)) { risen = true } }
                // The scene renders on a transparent canvas larger than its slot, with the camera widened
                // to match, so the island looks the same size but nothing it does, swaying, bobbing or
                // shedding petals, ever meets the edge of the view.
                GeometryReader { geometry in
                    LandmarkView(id: id, build: build, energy: energy, listening: listening, active: active)
                        .frame(width: geometry.size.width * LandmarkView.overscan, height: geometry.size.height * LandmarkView.overscan)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        .allowsHitTesting(false)
                }
            }
            .id(id)
            .accessibilityIdentifier("landmark-\(id)")
        } else {
            MuralOrb(energy: energy, listening: listening, active: active)
        }
    }
}

/// Every landmark the app can draw, by the ID a `LanguageModule` declares. Each builder returns a
/// small floating island with its scene on top, centred on the origin with the island's top at y = 0.
enum Landmarks {
    static let all: [String: () -> LandmarkScene] = [
        "pavilion": { LandmarkScene(root: Pavilion.island(), particles: Pavilion.petals() + [Geometry.fireflies(seed: 1)]) },
        "torii": { LandmarkScene(root: ToriiGate.island(), particles: ToriiGate.leaves() + [Geometry.fireflies(seed: 2)]) }
    ]
    /// The glow of a morning sky behind every landmark, so the scene stands in the same sunrise
    /// that lights it: gold at the heart, rose, then a trace of violet fading to the page.
    static let sky: [(color: Color, opacity: Double, location: CGFloat)] = [
        (Color(red: 1, green: 0.76, blue: 0.58), 0.46, 0),
        (Color(red: 1, green: 0.58, blue: 0.52), 0.28, 0.36),
        (Color(red: 0.72, green: 0.42, blue: 0.7), 0.12, 0.7),
        (Color(red: 0.4, green: 0.3, blue: 0.6), 0, 1)
    ]
}

struct LandmarkScene {
    var root: SCNNode
    var particles: [(SCNParticleSystem, SCNNode)]
}

/// Renders a landmark on a transparent SceneKit view.
///
/// Built for a screen that is on for a whole conversation: static parts are flattened into a few
/// draw calls, every tree's leaves and all the grass are one mesh each that sways on the GPU, there
/// are no shadows, the light is a handful of directional lights besides a lamp or two, it runs at
/// 30 frames a second, and nothing is drawn at all while the app is in the background, the
/// conversation is closing or Reduce Motion is on.
struct LandmarkView: UIViewRepresentable {
    let id: String
    let build: () -> LandmarkScene
    var energy: Double
    var listening: Bool
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    /// How much larger than its slot the canvas is.
    static let overscan: CGFloat = 1.7
    /// The slot's field of view, widened by `overscan` so the scene keeps its apparent size.
    static let fieldOfView: CGFloat = {
        let slot: CGFloat = 30 * .pi / 180
        return 2 * atan(tan(slot / 2) * overscan) * 180 / .pi
    }()

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
        // The canvas is larger than its slot, so draw it at 2x rather than the screen's 3x: about the
        // same number of pixels as the slot alone at full resolution.
        view.contentScaleFactor = 2
        view.isUserInteractionEnabled = false
        view.autoenablesDefaultLighting = false
        let scene = SCNScene()
        scene.background.contents = UIColor.clear
        let landmark = build()

        // Float: the whole island bobs and sways; `pulse` breathes with Mural's voice.
        let float = SCNNode(), pulse = SCNNode()
        pulse.addChildNode(landmark.root)
        float.addChildNode(pulse)
        float.eulerAngles.y = -0.35
        scene.rootNode.addChildNode(float)
        let bob = SCNAction.sequence([.moveBy(x: 0, y: 0.12, z: 0, duration: 2.6), .moveBy(x: 0, y: -0.12, z: 0, duration: 2.6)])
        bob.timingMode = .easeInEaseOut
        let sway = SCNAction.sequence([.rotateBy(x: 0, y: 0.55, z: 0, duration: 7), .rotateBy(x: 0, y: -0.55, z: 0, duration: 7)])
        sway.timingMode = .easeInEaseOut
        float.runAction(.repeatForever(bob)); float.runAction(.repeatForever(sway))
        for (system, emitter) in landmark.particles { emitter.addParticleSystem(system); landmark.root.addChildNode(emitter) }

        let camera = SCNCamera()
        camera.fieldOfView = Self.fieldOfView
        // HDR with bloom makes lanterns, windows and lacquer highlights glow. The view is small and
        // runs at 30 fps, so the post-process pass stays cheap.
        camera.wantsHDR = true
        camera.bloomIntensity = 1.3
        camera.bloomThreshold = 1.0
        camera.bloomBlurRadius = 8
        camera.wantsExposureAdaptation = false
        camera.exposureOffset = 0
        camera.contrast = 0.15
        camera.saturation = 1.1
        camera.vignettingIntensity = 0
        camera.zNear = 0.1; camera.zFar = 50
        let cameraNode = SCNNode(); cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 2.4, 7.6)
        cameraNode.look(at: SCNVector3(0, 0.75, 0))
        scene.rootNode.addChildNode(cameraNode)

        let sunrise = Sunrise(in: scene)
        if context.environment.accessibilityReduceMotion { sunrise.show(1) } else { sunrise.rise(on: scene.rootNode) }

        view.scene = scene
        view.pointOfView = cameraNode
        context.coordinator.sunrise = sunrise
        context.coordinator.pulse = pulse
        context.coordinator.particles = landmark.particles.map(\.0)
        context.coordinator.baseRates = landmark.particles.map { $0.0.birthRate }
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        let running = active && scenePhase == .active && !reduceMotion
        view.scene?.isPaused = !running
        view.isPlaying = running
        view.rendersContinuously = false
        let e = CGFloat(reduceMotion ? 0 : min(1, max(0, energy)))
        SCNTransaction.begin(); SCNTransaction.animationDuration = 0.18
        context.coordinator.pulse?.scale = SCNVector3(1 + e * 0.05, 1 + e * 0.05, 1 + e * 0.05)
        SCNTransaction.commit()
        // More petals or leaves drift while Mural speaks or the learner is listened to.
        let boost: CGFloat = 1 + e * 2 + (listening ? 0.5 : 0)
        for (system, base) in zip(context.coordinator.particles, context.coordinator.baseRates) { system.birthRate = base * boost }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        view.isPlaying = false
        view.scene = nil
    }

    final class Coordinator {
        var sunrise: Sunrise?
        var pulse: SCNNode?
        var particles: [SCNParticleSystem] = []
        var baseRates: [CGFloat] = []
    }
}

/// Morning light over a landmark: a low sun from the front left, a rose rim from the bright sky
/// behind that outlines roofs and crowns, cool skylight from above so the lawn and roofs are not
/// left to the sun alone, and a warm bounce from the grass up under the eaves.
///
/// When the scene appears the sun rises over a few seconds, from a red dawn on the horizon to a
/// golden morning, and then holds there for the rest of the conversation. Under Reduce Motion it
/// starts risen.
final class Sunrise {
    static let duration: TimeInterval = 6

    /// One moment of the light: the sun's height in radians, and each light's colour and strength.
    private struct Moment {
        var elevation: Float
        var sun: simd_float3, sunIntensity: Float
        var rim: simd_float3, rimIntensity: Float
        var sky: simd_float3, skyIntensity: Float
        var bounce: simd_float3, bounceIntensity: Float
        var ambient: simd_float3, ambientIntensity: Float
    }
    private static let dawn = Moment(elevation: 0.03,
                                     sun: simd_float3(1, 0.38, 0.2), sunIntensity: 450,
                                     rim: simd_float3(0.92, 0.36, 0.55), rimIntensity: 450,
                                     sky: simd_float3(0.32, 0.34, 0.68), skyIntensity: 200,
                                     bounce: simd_float3(0.8, 0.45, 0.35), bounceIntensity: 40,
                                     ambient: simd_float3(0.3, 0.28, 0.5), ambientIntensity: 170)
    private static let morning = Moment(elevation: 0.42,
                                        sun: simd_float3(1, 0.82, 0.62), sunIntensity: 1500,
                                        rim: simd_float3(1, 0.58, 0.55), rimIntensity: 750,
                                        sky: simd_float3(0.5, 0.62, 0.95), skyIntensity: 400,
                                        bounce: simd_float3(1, 0.78, 0.55), bounceIntensity: 170,
                                        ambient: simd_float3(0.52, 0.5, 0.64), ambientIntensity: 190)
    /// Where the sun stands, measured from straight ahead of the camera round to the left.
    private static let azimuth: Float = -0.85

    private let sun = SCNNode(), rim = SCNNode(), sky = SCNNode(), bounce = SCNNode(), ambient = SCNNode()

    init(in scene: SCNScene) {
        let lights: [(SCNNode, SCNLight.LightType)] = [(sun, .directional), (rim, .directional), (sky, .directional), (bounce, .directional), (ambient, .ambient)]
        for (node, type) in lights {
            let light = SCNLight(); light.type = type
            node.light = light
            scene.rootNode.addChildNode(node)
        }
        Self.aim(rim, from: Self.direction(azimuth: 2.5, elevation: 0.32))
        Self.aim(sky, from: simd_float3(0.1, 1, 0.3))
        Self.aim(bounce, from: simd_float3(-0.2, -1, 0.35))
    }

    /// Sets the light `progress` of the way from dawn to morning.
    func show(_ progress: Float) {
        let a = Self.dawn, b = Self.morning, t = simd_clamp(progress, 0, 1)
        func mix(_ x: Float, _ y: Float) -> Float { x + (y - x) * t }
        func mix(_ x: simd_float3, _ y: simd_float3) -> UIColor {
            let c = simd_mix(x, y, simd_float3(repeating: t))
            return UIColor(red: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
        }
        Self.aim(sun, from: Self.direction(azimuth: Self.azimuth, elevation: mix(a.elevation, b.elevation)))
        set(sun, mix(a.sun, b.sun), mix(a.sunIntensity, b.sunIntensity))
        set(rim, mix(a.rim, b.rim), mix(a.rimIntensity, b.rimIntensity))
        set(sky, mix(a.sky, b.sky), mix(a.skyIntensity, b.skyIntensity))
        set(bounce, mix(a.bounce, b.bounce), mix(a.bounceIntensity, b.bounceIntensity))
        set(ambient, mix(a.ambient, b.ambient), mix(a.ambientIntensity, b.ambientIntensity))
    }

    /// Starts at dawn and eases into morning, slowing as the sun climbs.
    func rise(on node: SCNNode) {
        show(0)
        let climb = SCNAction.customAction(duration: Self.duration) { [weak self] _, elapsed in
            let t = Float(elapsed) / Float(Self.duration)
            self?.show(1 - pow(1 - t, 2.2))
        }
        node.runAction(.sequence([climb, .run { [weak self] _ in self?.show(1) }]))
    }

    private func set(_ node: SCNNode, _ color: UIColor, _ intensity: Float) {
        node.light?.color = color
        node.light?.intensity = CGFloat(intensity)
    }
    private static func direction(azimuth: Float, elevation: Float) -> simd_float3 {
        simd_float3(cos(elevation) * sin(azimuth), sin(elevation), cos(elevation) * cos(azimuth))
    }
    /// Points a directional light so it shines from `direction` towards the island.
    private static func aim(_ node: SCNNode, from direction: simd_float3) {
        node.simdPosition = simd_normalize(direction) * 10
        node.simdLook(at: .zero)
    }
}

// MARK: Building blocks

/// A small deterministic generator, so a landmark looks the same every time it is drawn.
private struct Seeded: RandomNumberGenerator {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
    mutating func unit() -> Float { Float.random(in: 0...1, using: &self) }
    mutating func range(_ r: ClosedRange<Float>) -> Float { Float.random(in: r, using: &self) }
    /// A random direction on the unit sphere.
    mutating func direction() -> simd_float3 {
        let z = range(-1...1), a = range(0...(2 * .pi)), r = sqrt(max(0, 1 - z * z))
        return simd_float3(r * cos(a), z, r * sin(a))
    }
}

/// One leaf, petal, flower or blade card in a merged mesh.
private struct Card {
    var center: simd_float3
    var u: simd_float3
    var v: simd_float3
    var normal: simd_float3
    var color: simd_float4
}

private enum Geometry {
    static func material(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        material.isDoubleSided = doubleSided
        return material
    }
    /// Lacquered wood, painted metal or gilding: a highlight that moves as the island sways.
    static func lacquer(_ color: UIColor, shine: CGFloat = 0.6) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .blinn
        material.specular.contents = UIColor(white: shine, alpha: 1)
        material.shininess = 0.35
        return material
    }

    /// A surface that gives off light, bright enough to bloom.
    static func glow(_ color: UIColor, strength: CGFloat = 2.6) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.emission.contents = color
        material.emission.intensity = strength
        material.lightingModel = .constant
        return material
    }

    /// A warm point light that pools on the ground around a lantern and fades within `range`.
    static func lamp(at position: SCNVector3, color: UIColor = UIColor(red: 1, green: 0.72, blue: 0.4, alpha: 1),
                     intensity: CGFloat = 700, range: CGFloat = 1.1) -> SCNNode {
        let light = SCNLight(); light.type = .omni
        light.color = color; light.intensity = intensity
        light.attenuationStartDistance = 0; light.attenuationEndDistance = range; light.attenuationFalloffExponent = 2
        let node = SCNNode(); node.light = light; node.position = position
        return node
    }

    /// Slow, glowing motes drifting up over the island.
    static func fireflies(seed: UInt64) -> (SCNParticleSystem, SCNNode) {
        let system = SCNParticleSystem()
        system.particleImage = Textures.mote
        system.birthRate = 2.2
        system.particleLifeSpan = 5
        system.particleLifeSpanVariation = 2
        system.particleSize = 0.05
        system.particleSizeVariation = 0.025
        system.particleColor = UIColor(red: 1, green: 0.86, blue: 0.5, alpha: 1)
        system.particleColorVariation = SCNVector4(0.05, 0.1, 0.2, 0)
        system.emitterShape = SCNBox(width: 3, height: 1.2, length: 2.4, chamferRadius: 0)
        system.birthLocation = .volume
        system.particleVelocity = 0.06
        system.particleVelocityVariation = 0.05
        system.acceleration = SCNVector3(0, 0.025, 0)
        system.blendMode = .additive
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.loops = true
        // Fade in and out over each mote's life rather than popping.
        let fade = CAKeyframeAnimation(); fade.values = [0, 1, 1, 0]; fade.keyTimes = [0, 0.2, 0.7, 1]
        system.propertyControllers = [.opacity: SCNParticlePropertyController(animation: fade)]
        let emitter = SCNNode(); emitter.position = SCNVector3(0, 0.75, 0.1)
        _ = seed
        return (system, emitter)
    }

    static func textured(_ image: UIImage, repeat scale: CGSize = CGSize(width: 1, height: 1)) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.diffuse.wrapS = .repeat; material.diffuse.wrapT = .repeat
        material.diffuse.contentsTransform = SCNMatrix4MakeScale(Float(scale.width), Float(scale.height), 1)
        material.lightingModel = .lambert
        return material
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }
    static func vector(_ color: UIColor, jitter: Float = 0, using random: inout Seeded) -> simd_float4 {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let k = 1 + random.range(-jitter...jitter)
        return simd_float4(min(1, Float(r) * k), min(1, Float(g) * k), min(1, Float(b) * k), 1)
    }

    static func node(_ geometry: SCNGeometry, _ color: UIColor, at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = position
        return node
    }
    static func node(_ geometry: SCNGeometry, _ material: SCNMaterial, at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry); node.position = position
        return node
    }

    /// A cylinder from `a` to `b`, for trunks, branches, ridges and rails.
    static func limb(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor, taper: CGFloat = 0.7) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let cylinder = SCNCone(topRadius: radius * taper, bottomRadius: radius, height: CGFloat(length))
        cylinder.radialSegmentCount = 12
        let node = node(cylinder, color, at: SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2))
        // A cylinder stands on y; point that axis along the limb.
        let axis = simd_normalize(simd_float3(Float(dx), Float(dy), Float(dz)))
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: axis)
        return node
    }

    /// Merges a subtree that never moves into as few draw calls as its materials allow.
    static func flattened(_ node: SCNNode) -> SCNNode {
        let flat = node.flattenedClone()
        flat.position = node.position; flat.scale = node.scale; flat.eulerAngles = node.eulerAngles
        return flat
    }

    // MARK: Island and grass

    /// The island's outline at `angle`: a circle with a gently uneven edge, so the turf reads as
    /// grown rather than cut. Grass is placed inside the same outline, so no blade stands on air.
    static func rim(_ radius: Float, _ angle: Float, phase: Float) -> Float {
        radius * (1 + 0.022 * sin(3 * angle + phase) + 0.014 * sin(7 * angle + phase * 2.3) + 0.008 * sin(13 * angle + phase * 0.7))
    }

    /// The radius of the rounded edge where the top of the turf turns down into its side.
    static let turfEdge: Float = 0.07

    /// Slow variation across the lawn, from -1 to 1, so grass grows in patches of lighter and
    /// darker, taller and shorter, rather than as an even carpet.
    static func patch(_ spot: simd_float2, phase: Float) -> Float {
        0.6 * sin(spot.x * 2.1 + phase) * sin(spot.y * 1.7 - phase * 0.5) + 0.4 * sin((spot.x + spot.y) * 3.3 + phase * 1.3)
    }

    /// A floating island of turf and nothing under it: a slab of grass with a rounded, uneven edge,
    /// carpeted with swaying blades and a scattering of flowers. `clear` keeps grass off paths and
    /// buildings.
    static func island(radius: Float, top: UIColor, seed: UInt64, clear: (simd_float2) -> Bool) -> SCNNode {
        var random = Seeded(seed)
        let phase = random.range(0...(2 * .pi))
        let island = SCNNode()
        island.addChildNode(turf(radius: radius, color: top, phase: phase))
        island.addChildNode(grass(radius: radius, phase: phase, using: &random, clear: clear))
        return island
    }

    /// The slab under the grass, turned on a lathe: flat on top, rounding over the edge, and
    /// darkening down its side as turf does out of the sun. Its top sits at y = 0.
    static func turf(radius: Float, color: UIColor, phase: Float) -> SCNNode {
        let edge = turfEdge, depth: Float = 0.13, segments = 120
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        color.getRed(&r, green: &g, blue: &b, alpha: &a)
        let green = simd_float3(Float(r), Float(g), Float(b))
        // The profile from the centre outwards and down. Each ring reaches `scale` of the way to the
        // outline less `inset`, at height `y`, facing (outward, up), and `shade` into the side.
        var profile: [(scale: Float, inset: Float, y: Float, facing: simd_float2, shade: Float)] = []
        for f: Float in [0, 0.03, 0.08, 0.16, 0.26, 0.38, 0.5, 0.62, 0.75, 0.88, 1] { profile.append((f, edge * f, 0, simd_float2(0, 1), 0)) }
        for k in 1...6 {
            let turn = Float(k) / 6 * .pi / 2
            profile.append((1, edge * (1 - sin(turn)), -edge * (1 - cos(turn)), simd_float2(sin(turn), cos(turn)), Float(k) / 6 * 0.35))
        }
        profile.append((1, 0.004, -0.095, simd_float2(1, -0.1), 0.6))
        profile.append((1, 0.025, -depth, simd_float2(0.6, -0.8), 0.85))
        profile.append((0.85, 0, -depth - 0.01, simd_float2(0, -1), 0.9))
        profile.append((0, 0, -depth - 0.02, simd_float2(0, -1), 0.9))
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [simd_float4] = [], uvs: [CGPoint] = [], indices: [UInt32] = []
        let columns = segments + 1
        for ring in profile {
            for column in 0..<columns {
                let angle = Float(column) / Float(segments) * 2 * .pi
                let outward = simd_float2(cos(angle), sin(angle))
                let reach = max(0, rim(radius, angle, phase: phase) * ring.scale - ring.inset)
                let spot = outward * reach
                positions.append(SCNVector3(spot.x, ring.y, spot.y))
                normals.append(SCNVector3(simd_normalize(simd_float3(outward.x * ring.facing.x, ring.facing.y, outward.y * ring.facing.x))))
                // Down the side the green deepens, as turf does out of the sun, rather than turning to soil.
                let tone = simd_mix(green * (1 + 0.1 * patch(spot, phase: phase)), simd_float3(0.05, 0.13, 0.06), simd_float3(repeating: ring.shade))
                colors.append(simd_float4(tone, 1))
                uvs.append(.zero)
            }
        }
        for ring in 0..<(profile.count - 1) {
            for column in 0..<segments {
                let a = UInt32(ring * columns + column), b = a + 1, d = UInt32((ring + 1) * columns + column), c = d + 1
                indices += [a, b, c, a, c, d]
            }
        }
        let geometry = mesh(positions: positions, normals: normals, colors: colors, uvs: uvs, indices: indices)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .lambert
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    /// Grass blades and small flowers as one mesh, swaying from their tips. Blades grow in tufts,
    /// curve as they rise, darken towards the root and where buildings and trees crowd them, and
    /// spill over the rounded edge of the turf.
    static func grass(radius: Float, phase: Float, using random: inout Seeded, clear: (simd_float2) -> Bool) -> SCNNode {
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [simd_float4] = [], uvs: [CGPoint] = [], indices: [UInt32] = []
        positions.reserveCapacity(80_000); normals.reserveCapacity(80_000); colors.reserveCapacity(80_000); uvs.reserveCapacity(80_000)
        indices.reserveCapacity(140_000)
        // Greens from shade to sun, and now and then a dry blade, as in any real lawn.
        let greens = [simd_float3(0.24, 0.54, 0.16), simd_float3(0.3, 0.6, 0.19), simd_float3(0.2, 0.46, 0.14), simd_float3(0.35, 0.64, 0.2)]
        let dry = simd_float3(0.6, 0.6, 0.3)
        let up = simd_float3(0, 1, 0)
        // The top is flat until the rounded edge, so a root near the rim sits on the curve. `outline`
        // is the rim's radius in this direction, worked out once per tuft.
        func ground(_ spot: simd_float2, outline: Float) -> Float {
            let inset = outline - simd_length(spot)
            guard inset < turfEdge else { return 0 }
            let s = simd_clamp(1 - inset / turfEdge, 0, 1)
            return -turfEdge * (1 - sqrt(1 - s * s))
        }

        /// One blade: two quads tapering to a point, bent from `foot` towards `bend`.
        func blade(foot: simd_float3, rise: simd_float3, height: Float, width: Float, bend: simd_float3, base: simd_float3, shade: Float) {
            let facing = random.range(0...(2 * .pi))
            let side = simd_float3(cos(facing), 0, sin(facing)) * width
            let mid = foot + rise * height * 0.55 + bend * 0.3
            let tip = foot + rise * height + bend
            let start = UInt32(positions.count)
            // Lit as if facing up and a little towards its lean, so a lawn of blades turned every
            // way still reads as one lit surface, with blades that lean into the sun catching it.
            let lean = simd_length(simd_float3(bend.x, 0, bend.z)) > 0.0001 ? simd_normalize(simd_float3(bend.x, 0, bend.z)) : simd_float3(1, 0, 0)
            let normal = SCNVector3(simd_normalize(rise * 0.62 + lean * 0.38))
            let root = simd_float4(base * (0.32 - 0.14 * shade), 1), body = simd_float4(base * (0.78 - 0.18 * shade), 1)
            // Tips warm towards yellow, where the low sun catches them.
            let tipColor = simd_float4(simd_min(base * 1.2 + simd_float3(0.05, 0.05, 0), simd_float3(repeating: 1)), 1)
            // The wind reads v, so the tip travels furthest and the root stays put.
            func vertex(_ point: simd_float3, _ reach: CGFloat, _ color: simd_float4) {
                positions.append(SCNVector3(point)); normals.append(normal); uvs.append(CGPoint(x: 0.5, y: reach)); colors.append(color)
            }
            vertex(foot - side, 0, root); vertex(foot + side, 0, root)
            vertex(mid - side * 0.62, 0.3, body); vertex(mid + side * 0.62, 0.3, body)
            vertex(tip, 1, tipColor)
            for index in [start, start + 1, start + 3, start, start + 3, start + 2, start + 2, start + 3, start + 4] { indices.append(index) }
        }
        func tone(at spot: simd_float2) -> simd_float3 {
            if random.unit() < 0.04 { return dry * random.range(0.85...1.05) }
            let pick = greens[Int(random.unit() * Float(greens.count - 1) + 0.5)]
            let p = patch(spot, phase: phase)
            return pick * (1 + 0.14 * p) * random.range(0.88...1.08) + simd_float3(0.03, 0.02, 0) * max(0, p)
        }
        // How hemmed in a spot is, from 0 in open lawn to 1 beside a wall, so grass darkens where
        // a building or a trunk would shade it.
        let around = (0..<8).map { k -> simd_float2 in let a = Float(k) / 8 * 2 * .pi; return simd_float2(cos(a), sin(a)) * 0.16 }
        func crowding(_ spot: simd_float2) -> Float { Float(around.filter { clear(spot + $0) }.count) / 8 }

        var tufts = 0, attempts = 0
        while tufts < 2600 && attempts < 12_000 {
            attempts += 1
            let angle = random.range(0...(2 * .pi)), outline = rim(radius, angle, phase: phase), edge = outline - 0.03
            let centre = simd_float2(cos(angle), sin(angle)) * edge * sqrt(random.unit())
            guard !clear(centre) else { continue }
            tufts += 1
            let shade = crowding(centre)
            let p = patch(centre, phase: phase)
            let atEdge = simd_length(centre) / edge > 0.93
            let outward = simd_normalize(simd_float3(centre.x, 0, centre.y) + simd_float3(0.0001, 0, 0))
            for _ in 0..<Int(random.range(4...8.99)) {
                let spot = centre + simd_float2(random.range(-0.035...0.035), random.range(-0.035...0.035))
                guard !clear(spot), simd_length(spot) < outline - 0.01 else { continue }
                let height = random.range(0.065...0.14) * (1 + 0.28 * p) * (1 + 0.25 * shade)
                // Blades splay out from the middle of their tuft, and lean out over the edge.
                var splay = simd_float3(spot.x - centre.x, 0, spot.y - centre.y)
                splay = simd_length(splay) > 0.0001 ? simd_normalize(splay) : outward
                let direction = simd_normalize(splay + simd_float3(random.range(-0.5...0.5), 0, random.range(-0.5...0.5)) + (atEdge ? outward * 1.2 : .zero))
                let bend = direction * height * random.range(0.12...0.45)
                blade(foot: simd_float3(spot.x, ground(spot, outline: outline), spot.y), rise: up, height: height, width: random.range(0.009...0.016), bend: bend,
                      base: tone(at: spot), shade: shade)
            }
        }
        // A fringe over the rounded edge, growing outwards, so the slab's rim is grass too.
        for _ in 0..<1600 {
            let angle = random.range(0...(2 * .pi)), turn = random.range(0.2...1.4)
            let outward = simd_float3(cos(angle), 0, sin(angle))
            let reach = rim(radius, angle, phase: phase) - turfEdge * (1 - sin(turn))
            let spot = simd_float2(outward.x, outward.z) * (reach - 0.004)
            guard !clear(spot) else { continue }
            let foot = simd_float3(spot.x, -turfEdge * (1 - cos(turn)), spot.y)
            let rise = simd_normalize(up * 0.9 + outward * (0.25 + sin(turn) * 0.6))
            let height = random.range(0.06...0.13)
            blade(foot: foot, rise: rise, height: height, width: random.range(0.009...0.015),
                  bend: simd_normalize(outward + simd_float3(random.range(-0.4...0.4), 0, random.range(-0.4...0.4))) * height * 0.35,
                  base: tone(at: spot) * 0.9, shade: 0.2)
        }
        // And shorter blades growing out of the side itself, so it reads as turf all the way down.
        for _ in 0..<800 {
            let angle = random.range(0...(2 * .pi))
            let outward = simd_float3(cos(angle), 0, sin(angle))
            let spot = simd_float2(outward.x, outward.z) * (rim(radius, angle, phase: phase) - 0.002)
            guard !clear(spot) else { continue }
            let foot = simd_float3(spot.x, random.range(-0.105...(-0.07)), spot.y)
            let height = random.range(0.04...0.08)
            blade(foot: foot, rise: simd_normalize(outward * 0.75 + up * 0.65), height: height, width: random.range(0.008...0.013),
                  bend: simd_normalize(outward + simd_float3(random.range(-0.5...0.5), 0, random.range(-0.5...0.5))) * height * 0.3,
                  base: tone(at: spot) * 0.7, shade: 0.4)
        }
        // Flowers: small white, yellow and pink stars held just above the blades.
        let petals = [simd_float4(1, 0.97, 0.92, 1), simd_float4(1, 0.86, 0.4, 1), simd_float4(1, 0.72, 0.82, 1)]
        var flowers = 0; attempts = 0
        while flowers < 70 && attempts < 1200 {
            attempts += 1
            let angle = random.range(0...(2 * .pi))
            let spot = simd_float2(cos(angle), sin(angle)) * (rim(radius, angle, phase: phase) - 0.1) * sqrt(random.unit())
            guard !clear(spot) else { continue }
            flowers += 1
            let center = simd_float3(spot.x, random.range(0.07...0.12), spot.y), size = random.range(0.014...0.022)
            let color = petals[flowers % petals.count]
            for turn: Float in [0, .pi / 4] {
                let start = UInt32(positions.count)
                for k in 0..<4 {
                    let a = turn + Float(k) * .pi / 2
                    positions.append(SCNVector3(center + simd_float3(cos(a), 0, sin(a)) * size)); normals.append(SCNVector3(0, 1, 0))
                    uvs.append(CGPoint(x: 0.5, y: 0.6)); colors.append(color)
                }
                indices += [start, start + 1, start + 2, start, start + 2, start + 3]
            }
        }
        let geometry = mesh(positions: positions, normals: normals, colors: colors, uvs: uvs, indices: indices)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.shaderModifiers = [.geometry: wind]
        material.setValue(0.022, forKey: "windStrength")
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    static func mesh(positions: [SCNVector3], normals: [SCNVector3], colors: [simd_float4], uvs: [CGPoint], indices: [UInt32]) -> SCNGeometry {
        let colorData = colors.withUnsafeBufferPointer { Data(buffer: $0) }
        let colorSource = SCNGeometrySource(data: colorData, semantic: .color, vectorCount: colors.count, usesFloatComponents: true,
                                            componentsPerVector: 4, bytesPerComponent: MemoryLayout<Float>.size, dataOffset: 0,
                                            dataStride: MemoryLayout<simd_float4>.stride)
        let element = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        return SCNGeometry(sources: [SCNGeometrySource(vertices: positions), SCNGeometrySource(normals: normals), colorSource,
                                     SCNGeometrySource(textureCoordinates: uvs)], elements: [element])
    }

    /// Moves each vertex with the wind in proportion to its texture's v, so a blade sways from its
    /// tip and a leaf flutters about its stem. It runs on the GPU and costs nothing on the CPU.
    static let wind = """
    #pragma arguments
    float windStrength;
    #pragma body
    float reach = _geometry.texcoords[0].y;
    float t = scn_frame.time;
    float gust = sin(t * 1.4 + _geometry.position.x * 2.7 + _geometry.position.z * 1.9) + 0.4 * sin(t * 3.1 + _geometry.position.z * 4.0);
    _geometry.position.x += gust * windStrength * reach;
    _geometry.position.z += gust * windStrength * 0.5 * reach;
    """

    /// Leaf cards use a cut-out texture. Discarding the transparent part keeps depth correct without
    /// sorting hundreds of overlapping cards every frame.
    static let cutout = """
    #pragma body
    if (_output.color.a < 0.5) { discard_fragment(); }
    // The texture is premultiplied, so a card's soft edge would otherwise darken into a fringe.
    _output.color.rgb /= max(_output.color.a, 0.001);
    _output.color.a = 1.0;
    """

    /// Hundreds of leaf or blossom cards in one mesh around the given clusters, plus hanging
    /// strands for a weeping tree.
    /// `fill` is how deep into each cluster cards reach, so a crown can be dense right through
    /// rather than a shell; `shade`, when given, colours a card by where it sits.
    static func foliage(clusters: [(simd_float3, Float)], count: Int, size: ClosedRange<Float>, colors: [UIColor], image: UIImage,
                        strands: [(simd_float3, Float)] = [], seed: UInt64, wind strength: Float = 0.018,
                        fill: Float = 0.78, shade: ((simd_float3) -> UIColor)? = nil) -> SCNNode {
        var random = Seeded(seed)
        var cards: [Card] = []
        func card(at center: simd_float3, outward: simd_float3) {
            let s = random.range(size)
            var u = simd_normalize(simd_cross(random.direction(), outward))
            if !u.x.isFinite { u = simd_float3(1, 0, 0) }
            let v = simd_normalize(simd_cross(outward, u)) * 0.9 + simd_float3(0, -0.25, 0)
            let base = shade?(center) ?? colors[Int(random.unit() * Float(colors.count - 1) + 0.5)]
            let color = vector(base, jitter: 0.09, using: &random)
            // Lit as if facing mostly upwards, so cards turned away from the sun are not left black.
            let normal = simd_normalize(outward * 0.45 + simd_float3(0, 1, 0))
            cards.append(Card(center: center, u: u * s, v: simd_normalize(v) * s, normal: normal, color: color))
        }
        for _ in 0..<count {
            let (centre, radius) = clusters[Int(random.unit() * Float(clusters.count - 1) + 0.5)]
            let direction = random.direction()
            // Mostly on the outside of the cloud, where leaves catch the light, with some inside.
            let depth = fill + (1.06 - fill) * sqrt(random.unit())
            card(at: centre + direction * radius * depth, outward: direction)
        }
        for (top, length) in strands {
            var point = top
            let drift = simd_float3(random.range(-0.03...0.03), 0, random.range(-0.03...0.03))
            let steps = Int(length / 0.045)
            for _ in 0..<steps {
                point += simd_float3(0, -0.045, 0) + drift
                for _ in 0..<3 { card(at: point + random.direction() * 0.05, outward: simd_normalize(simd_float3(point.x - top.x, 0.2, point.z - top.z) + random.direction() * 0.6)) }
            }
        }
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], vertexColors: [simd_float4] = [], uvs: [CGPoint] = [], indices: [UInt32] = []
        positions.reserveCapacity(cards.count * 4); normals.reserveCapacity(cards.count * 4); vertexColors.reserveCapacity(cards.count * 4)
        uvs.reserveCapacity(cards.count * 4); indices.reserveCapacity(cards.count * 6)
        for card in cards {
            let start = UInt32(positions.count), normal = SCNVector3(card.normal)
            func corner(_ point: simd_float3, _ uv: CGPoint) {
                positions.append(SCNVector3(point)); normals.append(normal); vertexColors.append(card.color); uvs.append(uv)
            }
            corner(card.center - card.u - card.v, CGPoint(x: 0, y: 1)); corner(card.center + card.u - card.v, CGPoint(x: 1, y: 1))
            corner(card.center + card.u + card.v, CGPoint(x: 1, y: 0)); corner(card.center - card.u + card.v, CGPoint(x: 0, y: 0))
            indices.append(start); indices.append(start + 1); indices.append(start + 2)
            indices.append(start); indices.append(start + 2); indices.append(start + 3)
        }
        let geometry = mesh(positions: positions, normals: normals, colors: vertexColors, uvs: uvs, indices: indices)
        let material = SCNMaterial()
        material.diffuse.contents = image
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.shaderModifiers = [.geometry: wind, .fragment: cutout]
        material.setValue(strength, forKey: "windStrength")
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }

    // MARK: Roofs

    /// A many-sided roof whose surface sags towards the eaves and lifts at every corner, the curve
    /// both Korean and Japanese roofs share: tiled in rows on top, painted underneath, with hip
    /// ridges, upturned corner tips and round end tiles along the eaves. `rafters`, when given,
    /// adds a row of round rafters under the eaves with painted ends, as on a Korean pavilion.
    static func curvedRoof(sides: Int, eave: Float, apex: Float, height: Float, lift: Float,
                           tile: UIColor, under: UIColor, rows: Int, endTiles: Bool, rotation: Float = 0,
                           rafters: (wood: UIColor, ends: [UIColor])? = nil) -> SCNNode {
        let steps = 12
        var upper: [SCNVector3] = [], upperNormals: [SCNVector3] = [], upperUVs: [CGPoint] = []
        var lower: [SCNVector3] = [], lowerNormals: [SCNVector3] = []
        func corner(_ index: Int) -> simd_float2 {
            let angle = Float(index) * 2 * .pi / Float(sides) + rotation
            return simd_float2(cos(angle), sin(angle)) * eave
        }
        func point(_ sector: Int, _ u: Float, _ v: Float) -> simd_float3 {
            let edge = simd_mix(corner(sector), corner(sector + 1), simd_float2(repeating: u))
            let xz = edge * (apex / eave + (1 - apex / eave) * v)
            let cornerness = pow(abs(2 * u - 1), 3)
            let y = height * pow(1 - v, 1.6) + lift * pow(v, 3) * cornerness
            return simd_float3(xz.x, y, xz.y)
        }
        func add(_ a: (simd_float3, CGPoint), _ b: (simd_float3, CGPoint), _ c: (simd_float3, CGPoint)) {
            var n = simd_normalize(simd_cross(b.0 - a.0, c.0 - a.0))
            var (q, r) = (b, c)
            if n.y < 0 { n = -n; swap(&q, &r) }
            for vertex in [a, q, r] { upper.append(SCNVector3(vertex.0)); upperNormals.append(SCNVector3(n)); upperUVs.append(vertex.1) }
            let drop = simd_float3(0, -0.025, 0)
            for vertex in [a, r, q] { lower.append(SCNVector3(vertex.0 + drop)); lowerNormals.append(SCNVector3(-n)) }
        }
        for sector in 0..<sides {
            for i in 0..<steps { for j in 0..<steps {
                let u0 = Float(i) / Float(steps), u1 = Float(i + 1) / Float(steps)
                let v0 = Float(j) / Float(steps), v1 = Float(j + 1) / Float(steps)
                func p(_ u: Float, _ v: Float) -> (simd_float3, CGPoint) { (point(sector, u, v), CGPoint(x: CGFloat(u) * CGFloat(rows), y: CGFloat(v))) }
                add(p(u0, v0), p(u1, v0), p(u1, v1)); add(p(u0, v0), p(u1, v1), p(u0, v1))
            } }
        }
        func geometry(_ vertices: [SCNVector3], _ normals: [SCNVector3], _ uvs: [CGPoint]?, _ material: SCNMaterial) -> SCNGeometry {
            var sources = [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)]
            if let uvs { sources.append(SCNGeometrySource(textureCoordinates: uvs)) }
            let geometry = SCNGeometry(sources: sources, elements: [SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)])
            geometry.materials = [material]
            return geometry
        }
        let roof = SCNNode()
        roof.addChildNode(SCNNode(geometry: geometry(upper, upperNormals, upperUVs, textured(Textures.tiles(tile)))))
        roof.addChildNode(SCNNode(geometry: geometry(lower, lowerNormals, nil, material(under))))
        let scale = min(1, eave / 1.18)
        let ridge = CGFloat(0.026 * scale + 0.006)
        for sector in 0..<sides {
            var previous = point(sector, 0, 0) + simd_float3(0, 0.03, 0)
            for step in 1...8 {
                let next = point(sector, 0, Float(step) / 8) + simd_float3(0, 0.03, 0)
                roof.addChildNode(limb(from: SCNVector3(previous), to: SCNVector3(next), radius: ridge, color: tile.darker(0.2), taper: 1))
                previous = next
            }
            let tip = point(sector, 0, 1)
            roof.addChildNode(limb(from: SCNVector3(tip), to: SCNVector3(tip * simd_float3(1.06, 1, 1.06) + simd_float3(0, 0.1 * scale + 0.02, 0)),
                                   radius: ridge * 1.15, color: tile.darker(0.28)))
            if let rafters {
                // Clear of the corners, where the eave lifts away from the rafters.
                for k in 2..<13 {
                    let u = Float(k) / 14
                    let outer = point(sector, u, 0.985) + simd_float3(0, -0.042, 0), inner = point(sector, u, 0.7) + simd_float3(0, -0.042, 0)
                    roof.addChildNode(limb(from: SCNVector3(inner), to: SCNVector3(outer), radius: CGFloat(0.014 * scale), color: rafters.wood, taper: 1))
                    let along = simd_normalize(outer - inner)
                    let disc = SCNCylinder(radius: CGFloat(0.0145 * scale), height: 0.006); disc.radialSegmentCount = 10
                    let end = node(disc, rafters.ends[k % rafters.ends.count], at: SCNVector3(outer + along * 0.003))
                    end.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: along)
                    roof.addChildNode(end)
                }
            }
            guard endTiles else { continue }
            // Round end tiles along the eave, facing outwards.
            for k in 1..<12 {
                let u = Float(k) / 12, spot = point(sector, u, 1)
                let outward = simd_normalize(simd_float3(spot.x, 0, spot.z))
                let disc = SCNCylinder(radius: CGFloat(0.03 * scale), height: 0.02); disc.radialSegmentCount = 12
                let cap = node(disc, tile.lighter(0.15), at: SCNVector3(spot + outward * 0.012))
                cap.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: outward)
                roof.addChildNode(cap)
            }
        }
        return flattened(roof)
    }

    /// A falling-particle system: petals or leaves from a canopy.
    static func drift(color: UIColor, image: UIImage, rate: CGFloat, size: CGFloat, shape: SCNGeometry) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = image
        system.birthRate = rate
        system.particleLifeSpan = 5.5
        system.particleLifeSpanVariation = 1.5
        system.particleSize = size
        system.particleSizeVariation = size * 0.4
        system.particleColor = color
        system.particleColorVariation = SCNVector4(0.02, 0.1, 0.1, 0)
        system.emitterShape = shape
        system.birthLocation = .volume
        system.particleVelocity = 0.08
        system.particleVelocityVariation = 0.06
        system.acceleration = SCNVector3(0.05, -0.12, 0)
        system.particleAngularVelocity = 90
        system.particleAngularVelocityVariation = 120
        system.blendMode = .alpha
        system.isLightingEnabled = false
        system.isAffectedByGravity = false
        system.loops = true
        return system
    }
}

/// Small textures drawn once in code, so no image files ship with the landmarks.
private enum Textures {
    /// A five-petalled cherry blossom with a pale heart; vertex colour tints it.
    static let blossom: UIImage = draw(64) { size in
        let c = CGPoint(x: size / 2, y: size / 2)
        for k in 0..<5 {
            let angle = CGFloat(k) / 5 * 2 * .pi - .pi / 2
            let petal = UIBezierPath(ovalIn: CGRect(x: -size * 0.13, y: -size * 0.3, width: size * 0.26, height: size * 0.32))
            petal.apply(CGAffineTransform(rotationAngle: angle + .pi / 2).concatenating(CGAffineTransform(translationX: c.x + cos(angle) * size * 0.17, y: c.y + sin(angle) * size * 0.17)))
            UIColor.white.setFill(); petal.fill()
        }
        UIColor(white: 0.82, alpha: 1).setFill()
        UIBezierPath(ovalIn: CGRect(x: c.x - size * 0.07, y: c.y - size * 0.07, width: size * 0.14, height: size * 0.14)).fill()
    }

    /// A five-lobed maple leaf with a stem.
    static let maple: UIImage = draw(64) { size in
        let c = CGPoint(x: size / 2, y: size * 0.55)
        let path = UIBezierPath()
        let points = 10
        for k in 0...points {
            let angle = CGFloat(k) / CGFloat(points) * 2 * .pi - .pi / 2
            let lobe = k % 2 == 0
            let radius = lobe ? size * (k == 0 ? 0.44 : 0.38) : size * 0.16
            let p = CGPoint(x: c.x + cos(angle) * radius, y: c.y + sin(angle) * radius)
            if k == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        path.close()
        UIColor.white.setFill(); path.fill()
        let stem = UIBezierPath(); stem.move(to: c); stem.addLine(to: CGPoint(x: c.x, y: size * 0.98))
        stem.lineWidth = size * 0.05; UIColor.white.setStroke(); stem.stroke()
    }

    /// A soft round glow for fireflies.
    static let mote: UIImage = draw(32) { size in
        let colors = [UIColor.white.cgColor, UIColor(white: 1, alpha: 0).cgColor] as CFArray
        let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
        UIGraphicsGetCurrentContext()?.drawRadialGradient(gradient, startCenter: CGPoint(x: size / 2, y: size / 2), startRadius: 0,
                                                          endCenter: CGPoint(x: size / 2, y: size / 2), endRadius: size / 2, options: [])
    }

    /// A pointed leaf for evergreens and shrubs.
    static let leaf: UIImage = draw(32) { size in
        let path = UIBezierPath()
        path.move(to: CGPoint(x: size / 2, y: 1))
        path.addQuadCurve(to: CGPoint(x: size / 2, y: size - 1), controlPoint: CGPoint(x: size, y: size / 2))
        path.addQuadCurve(to: CGPoint(x: size / 2, y: 1), controlPoint: CGPoint(x: 0, y: size / 2))
        UIColor.white.setFill(); path.fill()
    }

    /// Rows of roof tiles: light ridges with darker channels between them.
    static func tiles(_ color: UIColor) -> UIImage {
        draw(32) { size in
            color.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: size, height: size))
            color.lighter(0.18).setFill(); UIRectFill(CGRect(x: size * 0.15, y: 0, width: size * 0.35, height: size))
            color.darker(0.3).setFill(); UIRectFill(CGRect(x: size * 0.82, y: 0, width: size * 0.18, height: size))
        }
    }

    /// Dressed stone blocks in staggered courses.
    static func stone(_ color: UIColor) -> UIImage {
        draw(64) { size in
            color.setFill(); UIRectFill(CGRect(x: 0, y: 0, width: size, height: size))
            color.darker(0.22).setFill()
            let course = size / 4
            for row in 0..<4 {
                UIRectFill(CGRect(x: 0, y: CGFloat(row) * course, width: size, height: 1.5))
                let offset = row % 2 == 0 ? 0 : size / 4
                for column in 0..<2 { UIRectFill(CGRect(x: offset + CGFloat(column) * size / 2, y: CGFloat(row) * course, width: 1.5, height: course)) }
            }
        }
    }

    static func draw(_ side: CGFloat, _ body: (CGFloat) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: side, height: side), format: format).image { _ in body(side) }
    }
}

private extension UIColor {
    func darker(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: min(1, r * (1 - amount)), green: min(1, g * (1 - amount)), blue: min(1, b * (1 - amount)), alpha: a)
    }
    func lighter(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r + (1 - r) * amount, green: g + (1 - g) * amount, blue: b + (1 - b) * amount, alpha: a)
    }
}

// MARK: Hexagonal pavilion beside a weeping cherry

/// A six-sided pavilion of the kind found in Korean palace gardens: a stepped stone base and
/// stairs, red pillars with a low railing, painted brackets and a green band under curved tiled
/// eaves, and a stacked finial, beside a weeping cherry in blossom and a small pine.
private enum Pavilion {
    static let stone = Geometry.rgb(0.83, 0.77, 0.66)
    static let wood = Geometry.rgb(0.55, 0.18, 0.13)
    static let green = Geometry.rgb(0.16, 0.56, 0.47)
    static let tile = Geometry.rgb(0.4, 0.41, 0.44)
    static let blossom = [Geometry.rgb(1, 0.8, 0.88), Geometry.rgb(0.98, 0.68, 0.8), Geometry.rgb(1, 0.9, 0.94), Geometry.rgb(0.95, 0.62, 0.76)]
    static let site = simd_float2(-0.35, 0.15)
    static let canopyCentre = SCNVector3(1.2, 1.85, -0.35)

    static func island() -> SCNNode {
        let root = Geometry.island(radius: 1.8, top: Geometry.rgb(0.2, 0.4, 0.15), seed: 11) { spot in
            // Keep grass off the stone base, the stairs and the foot of the tree.
            simd_distance(spot, site) < 1.0 || (abs(spot.x - site.x) < 0.3 && spot.y > site.y && spot.y < site.y + 1.25)
                || simd_distance(spot, simd_float2(1.2, -0.35)) < 0.12
        }
        let pavilion = building()
        pavilion.position = SCNVector3(site.x, 0, site.y)
        root.addChildNode(pavilion)
        root.addChildNode(cherry())
        root.addChildNode(pine(at: simd_float3(-1.35, 0, -0.65)))
        // A stone lantern by the stairs, and warm light under the eaves from the hanging lanterns.
        let stoneLantern = ToriiGate.lantern(); stoneLantern.position = SCNVector3(site.x + 0.78, 0, site.y + 0.9)
        root.addChildNode(stoneLantern)
        root.addChildNode(Geometry.lamp(at: SCNVector3(site.x + 0.78, 0.5, site.y + 0.9), intensity: 650, range: 0.9))
        root.addChildNode(Geometry.lamp(at: SCNVector3(site.x, 1.05, site.y + 0.35), color: UIColor(red: 1, green: 0.55, blue: 0.45, alpha: 1),
                                        intensity: 800, range: 1.3))
        return root
    }

    static func building() -> SCNNode {
        let building = SCNNode()
        // A hexagon's flat side faces the front, where the stairs meet it.
        let offset = Float.pi / 6
        let blocks = Geometry.textured(Textures.stone(stone), repeat: CGSize(width: 6, height: 1))
        let base = SCNCylinder(radius: 0.95, height: 0.26); base.radialSegmentCount = 6
        let baseNode = Geometry.node(base, blocks, at: SCNVector3(0, 0.13, 0)); baseNode.eulerAngles.y = offset
        building.addChildNode(baseNode)
        let step = SCNCylinder(radius: 0.82, height: 0.12); step.radialSegmentCount = 6
        let stepNode = Geometry.node(step, Geometry.textured(Textures.stone(stone.darker(0.05)), repeat: CGSize(width: 6, height: 1)), at: SCNVector3(0, 0.32, 0))
        stepNode.eulerAngles.y = offset
        building.addChildNode(stepNode)
        for i in 0..<4 {
            let stair = SCNBox(width: 0.5, height: 0.08, length: 0.14, chamferRadius: 0.005)
            building.addChildNode(Geometry.node(stair, stone.darker(0.03 * CGFloat(i)), at: SCNVector3(0, 0.04 + 0.08 * Float(i), 1.02 - 0.12 * Float(i))))
        }
        for x: Float in [-0.29, 0.29] {
            let cheek = SCNBox(width: 0.07, height: 0.3, length: 0.5, chamferRadius: 0.005)
            let side = Geometry.node(cheek, stone.darker(0.1), at: SCNVector3(x, 0.15, 0.85)); side.eulerAngles.x = 0.32
            building.addChildNode(side)
        }
        let floor = SCNCylinder(radius: 0.74, height: 0.05); floor.radialSegmentCount = 6
        let floorNode = Geometry.node(floor, wood.darker(0.25), at: SCNVector3(0, 0.4, 0)); floorNode.eulerAngles.y = offset
        building.addChildNode(floorNode)
        var corners: [simd_float3] = []
        for i in 0..<6 {
            let angle = Float(i) * .pi / 3
            corners.append(simd_float3(0.66 * cos(angle), 0, 0.66 * sin(angle)))
        }
        for corner in corners {
            let pillar = SCNCylinder(radius: 0.045, height: 0.88); pillar.radialSegmentCount = 18
            building.addChildNode(Geometry.node(pillar, Geometry.lacquer(wood), at: SCNVector3(corner.x, 0.86, corner.z)))
            let footing = SCNCylinder(radius: 0.065, height: 0.05); footing.radialSegmentCount = 18
            building.addChildNode(Geometry.node(footing, stone.darker(0.12), at: SCNVector3(corner.x, 0.445, corner.z)))
            // A painted bracket where each pillar meets the eaves.
            let bracket = SCNBox(width: 0.13, height: 0.07, length: 0.13, chamferRadius: 0.01)
            let top = Geometry.node(bracket, green.darker(0.15), at: SCNVector3(corner.x, 1.33, corner.z))
            top.eulerAngles.y = -atan2(corner.z, corner.x)
            building.addChildNode(top)
        }
        // A low railing on every side but the front, where the stairs arrive.
        for i in 0..<6 {
            let a = corners[i], b = corners[(i + 1) % 6]
            let mid = (a + b) / 2
            if mid.z > 0.4 { continue }
            for height: Float in [0.56, 0.68] {
                building.addChildNode(Geometry.limb(from: SCNVector3(a.x, height, a.z), to: SCNVector3(b.x, height, b.z), radius: 0.012, color: wood.darker(0.1), taper: 1))
            }
            for k in 1..<8 {
                let p = simd_mix(a, b, simd_float3(repeating: Float(k) / 8))
                let baluster = SCNCylinder(radius: 0.008, height: 0.24); baluster.radialSegmentCount = 8
                building.addChildNode(Geometry.node(baluster, wood.darker(0.1), at: SCNVector3(p.x, 0.55, p.z)))
            }
        }
        let band = SCNTube(innerRadius: 0.6, outerRadius: 0.72, height: 0.16); band.radialSegmentCount = 6
        building.addChildNode(Geometry.node(band, Geometry.material(green, doubleSided: true), at: SCNVector3(0, 1.22, 0)))
        let trim = SCNTube(innerRadius: 0.62, outerRadius: 0.73, height: 0.03); trim.radialSegmentCount = 6
        building.addChildNode(Geometry.node(trim, Geometry.rgb(0.86, 0.33, 0.2), at: SCNVector3(0, 1.13, 0)))
        // Dancheong: small painted motifs along the band, orange, white and blue.
        let paints = [Geometry.rgb(0.95, 0.5, 0.2), Geometry.rgb(0.95, 0.92, 0.85), Geometry.rgb(0.25, 0.4, 0.75)]
        for i in 0..<6 {
            let a = corners[i], b = corners[(i + 1) % 6]
            let outward = simd_normalize((a + b) / 2)
            for k in 1..<10 {
                let p = simd_mix(a, b, simd_float3(repeating: Float(k) / 10)) * 1.06 + outward * 0.02
                let dot = SCNCylinder(radius: 0.017, height: 0.01); dot.radialSegmentCount = 10
                let motif = Geometry.node(dot, paints[(i + k) % paints.count], at: SCNVector3(p.x, 1.22, p.z))
                motif.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: outward)
                building.addChildNode(motif)
            }
        }
        // Silk lanterns hanging under the front eaves: red, capped in blue, lit from within.
        for corner in corners where corner.z > -0.1 {
            let spot = corner * 1.14
            building.addChildNode(Geometry.limb(from: SCNVector3(spot.x, 1.3, spot.z), to: SCNVector3(spot.x, 1.13, spot.z), radius: 0.004, color: wood, taper: 1))
            let body = SCNCylinder(radius: 0.045, height: 0.11); body.radialSegmentCount = 18
            building.addChildNode(Geometry.node(body, Geometry.glow(Geometry.rgb(1, 0.3, 0.22), strength: 3.4), at: SCNVector3(spot.x, 1.07, spot.z)))
            for y: Float in [1.13, 1.01] {
                let cap = SCNCylinder(radius: 0.05, height: 0.02); cap.radialSegmentCount = 18
                building.addChildNode(Geometry.node(cap, Geometry.lacquer(Geometry.rgb(0.15, 0.3, 0.7)), at: SCNVector3(spot.x, y, spot.z)))
            }
            let tassel = SCNCone(topRadius: 0.012, bottomRadius: 0.004, height: 0.06); tassel.radialSegmentCount = 6
            building.addChildNode(Geometry.node(tassel, Geometry.rgb(0.95, 0.3, 0.25), at: SCNVector3(spot.x, 0.97, spot.z)))
        }
        let roof = Geometry.curvedRoof(sides: 6, eave: 1.2, apex: 0.08, height: 0.58, lift: 0.22, tile: tile, under: green, rows: 14, endTiles: true,
                                       rafters: (wood: green.darker(0.2), ends: [Geometry.rgb(0.95, 0.92, 0.85), Geometry.rgb(0.25, 0.4, 0.75), Geometry.rgb(0.95, 0.5, 0.2)]))
        roof.position = SCNVector3(0, 1.32, 0)
        building.addChildNode(roof)
        // The finial: stacked knobs at the crown, as in the photograph.
        for (index, radius) in [0.1, 0.078, 0.06, 0.035].enumerated() {
            let knob = SCNSphere(radius: radius); knob.segmentCount = 18
            building.addChildNode(Geometry.node(knob, tile.darker(0.2), at: SCNVector3(0, 1.94 + Float(index) * 0.11, 0)))
        }
        return Geometry.flattened(building)
    }

    static func cherry() -> SCNNode {
        let tree = SCNNode()
        let bark = Geometry.rgb(0.3, 0.2, 0.17)
        let base = SCNVector3(1.2, 0, -0.35), fork = SCNVector3(1.12, 0.85, -0.35)
        let wood = SCNNode()
        wood.addChildNode(Geometry.limb(from: base, to: fork, radius: 0.1, color: bark))
        let ends = [SCNVector3(0.72, 1.6, -0.15), SCNVector3(1.55, 1.7, -0.55), SCNVector3(1.2, 2.0, -0.25), SCNVector3(0.95, 1.85, -0.6),
                    SCNVector3(1.35, 1.55, 0.05)]
        for end in ends { wood.addChildNode(Geometry.limb(from: fork, to: end, radius: 0.055, color: bark)) }
        tree.addChildNode(Geometry.flattened(wood))
        let clusters: [(simd_float3, Float)] = [
            (simd_float3(1.2, 1.95, -0.35), 0.52), (simd_float3(0.75, 1.68, -0.18), 0.42), (simd_float3(1.62, 1.75, -0.52), 0.44),
            (simd_float3(1.0, 2.22, -0.48), 0.38), (simd_float3(1.45, 2.18, -0.12), 0.36), (simd_float3(0.9, 1.8, 0.15), 0.34),
            (simd_float3(1.3, 1.6, 0.05), 0.32), (simd_float3(0.6, 1.95, -0.45), 0.3)
        ]
        // Fine twigs into every cloud, glimpsed through the blossom.
        let twigs = SCNNode()
        for (index, (centre, radius)) in clusters.enumerated() {
            let from = ends[index % ends.count]
            twigs.addChildNode(Geometry.limb(from: from, to: SCNVector3(centre + simd_float3(0, -radius * 0.2, 0)), radius: 0.025, color: bark))
        }
        tree.addChildNode(Geometry.flattened(twigs))
        let strands: [(simd_float3, Float)] = [
            (simd_float3(0.45, 1.6, -0.1), 0.6), (simd_float3(0.7, 1.5, 0.25), 0.65), (simd_float3(1.9, 1.6, -0.45), 0.65),
            (simd_float3(1.6, 1.45, 0.1), 0.6), (simd_float3(1.0, 1.55, 0.4), 0.55), (simd_float3(1.8, 1.55, -0.85), 0.55),
            (simd_float3(1.3, 1.4, 0.3), 0.5)
        ]
        // Dense right through, no solid core: lavender on the shaded side warming to pink in the
        // sun, and paler at the crown where the light catches it, as in the reference.
        let lavender = simd_float3(0.62, 0.52, 0.8), pink = simd_float3(0.9, 0.52, 0.7), white = simd_float3(0.95, 0.82, 0.9)
        tree.addChildNode(Geometry.foliage(clusters: clusters, count: 6800, size: 0.032...0.056, colors: blossom, image: Textures.blossom,
                                           strands: strands, seed: 21, fill: 0.15) { point in
            let across = simd_clamp((point.x - 0.45) / 1.4, 0, 1)
            let height = simd_clamp((point.y - 1.7) / 0.8, 0, 1)
            let tone = simd_mix(simd_mix(lavender, pink, simd_float3(repeating: across)), white, simd_float3(repeating: height * 0.3))
            return UIColor(red: CGFloat(tone.x), green: CGFloat(tone.y), blue: CGFloat(tone.z), alpha: 1)
        })
        return tree
    }

    /// A small pine at the back, as in the garden behind the pavilion in the photograph.
    static func pine(at foot: simd_float3) -> SCNNode {
        let tree = SCNNode()
        tree.addChildNode(Geometry.limb(from: SCNVector3(foot), to: SCNVector3(foot + simd_float3(0.05, 0.75, 0)), radius: 0.05, color: Geometry.rgb(0.32, 0.22, 0.18)))
        let tiers: [(simd_float3, Float)] = [
            (foot + simd_float3(0, 0.55, 0), 0.32), (foot + simd_float3(0.08, 0.8, 0.05), 0.26), (foot + simd_float3(0.02, 1.02, 0), 0.18)
        ]
        tree.addChildNode(Geometry.foliage(clusters: tiers.map { ($0.0, $0.1) }, count: 2400, size: 0.028...0.045,
                                           colors: [Geometry.rgb(0.18, 0.38, 0.22), Geometry.rgb(0.24, 0.45, 0.26), Geometry.rgb(0.14, 0.3, 0.18)],
                                           image: Textures.leaf, seed: 31, wind: 0.008, fill: 0.2))
        return tree
    }

    static func petals() -> [(SCNParticleSystem, SCNNode)] {
        let emitter = SCNNode(); emitter.position = canopyCentre
        return [(Geometry.drift(color: Geometry.rgb(1, 0.82, 0.9), image: Textures.blossom, rate: 3.5, size: 0.05, shape: SCNSphere(radius: 0.6)), emitter)]
    }
}

// MARK: Torii gate beside a small pagoda

/// A vermilion torii with black feet, top rings, a gold-rimmed plaque and a curved black top beam,
/// on a stepping-stone approach between two stone lanterns, beside a three-tiered pagoda with
/// balconies and bells, a maple turning red and a few shrubs.
private enum ToriiGate {
    static let vermilion = Geometry.rgb(0.9, 0.27, 0.12)
    /// Lifted from true black so the beam still reads against the dark page.
    static let black = Geometry.rgb(0.24, 0.21, 0.21)
    static let gold = Geometry.rgb(0.85, 0.66, 0.28)
    static let roof = Geometry.rgb(0.34, 0.38, 0.38)
    static let maple = [Geometry.rgb(0.86, 0.22, 0.1), Geometry.rgb(0.96, 0.45, 0.14), Geometry.rgb(0.74, 0.14, 0.09), Geometry.rgb(0.98, 0.62, 0.2)]
    static let gate = simd_float2(-0.4, 0.55)
    static let tower = simd_float2(1.0, -0.6)
    static let canopyCentre = SCNVector3(1.5, 1.35, -1.05)

    static func island() -> SCNNode {
        let stones = (0..<6).map { simd_float2(-0.4 + (($0 % 2 == 0) ? -0.06 : 0.06), 1.45 - Float($0) * 0.3) }
        let root = Geometry.island(radius: 1.8, top: Geometry.rgb(0.2, 0.4, 0.15), seed: 12) { spot in
            stones.contains { simd_distance($0, spot) < 0.17 }
                || simd_distance(spot, tower) < 0.5
                || [-0.6, 0.6].contains { simd_distance(spot, simd_float2(gate.x + $0, gate.y)) < 0.13 }
                || [simd_float2(-1.2, 0.8), simd_float2(0.4, 1.05)].contains { simd_distance($0, spot) < 0.15 }
                || simd_distance(spot, simd_float2(1.5, -1.05)) < 0.1
        }
        let approach = SCNNode()
        var random = Seeded(5)
        for spot in stones {
            let slab = SCNCylinder(radius: CGFloat(random.range(0.12...0.15)), height: 0.04); slab.radialSegmentCount = 11
            let stone = Geometry.node(slab, Geometry.rgb(0.6, 0.58, 0.54).darker(CGFloat(random.range(0...0.12))), at: SCNVector3(spot.x, 0.02, spot.y))
            stone.scale = SCNVector3(1.25, 1, 0.9); stone.eulerAngles.y = random.range(0...3)
            approach.addChildNode(stone)
        }
        root.addChildNode(Geometry.flattened(approach))
        let torii = toriiGate(); torii.position = SCNVector3(gate.x, 0, gate.y)
        root.addChildNode(torii)
        let pagodaNode = pagoda(); pagodaNode.position = SCNVector3(tower.x, 0, tower.y); pagodaNode.scale = SCNVector3(1.45, 1.45, 1.45)
        root.addChildNode(pagodaNode)
        root.addChildNode(Geometry.lamp(at: SCNVector3(tower.x, 0.55, tower.y + 0.45), color: UIColor(red: 1, green: 0.5, blue: 0.3, alpha: 1),
                                        intensity: 600, range: 1.0))
        for spot in [simd_float2(-1.2, 0.8), simd_float2(0.4, 1.05)] {
            let light = lantern(); light.position = SCNVector3(spot.x, 0, spot.y)
            root.addChildNode(Geometry.lamp(at: SCNVector3(spot.x, 0.5, spot.y), intensity: 650, range: 0.9))
            root.addChildNode(light)
        }
        root.addChildNode(mapleTree())
        root.addChildNode(shrubs())
        return root
    }

    static func toriiGate() -> SCNNode {
        let gate = SCNNode()
        for x: Float in [-0.6, 0.6] {
            let pillar = SCNCone(topRadius: 0.06, bottomRadius: 0.075, height: 1.7); pillar.radialSegmentCount = 24
            gate.addChildNode(Geometry.node(pillar, Geometry.lacquer(vermilion), at: SCNVector3(x, 0.95, 0)))
            let foot = SCNCylinder(radius: 0.095, height: 0.22); foot.radialSegmentCount = 24
            gate.addChildNode(Geometry.node(foot, black, at: SCNVector3(x, 0.11, 0)))
            let collar = SCNCylinder(radius: 0.1, height: 0.03); collar.radialSegmentCount = 24
            gate.addChildNode(Geometry.node(collar, black.darker(0.2), at: SCNVector3(x, 0.235, 0)))
            // The daiwa: a black ring where each pillar meets the top beams.
            let ring = SCNCylinder(radius: 0.078, height: 0.07); ring.radialSegmentCount = 24
            gate.addChildNode(Geometry.node(ring, black, at: SCNVector3(x, 1.62, 0)))
        }
        let nuki = SCNBox(width: 1.62, height: 0.09, length: 0.08, chamferRadius: 0.005)
        gate.addChildNode(Geometry.node(nuki, Geometry.lacquer(vermilion), at: SCNVector3(0, 1.38, 0)))
        // The plaque between the beams: black, framed in gold.
        let frame = SCNBox(width: 0.22, height: 0.26, length: 0.05, chamferRadius: 0.005)
        gate.addChildNode(Geometry.node(frame, Geometry.lacquer(gold, shine: 0.9), at: SCNVector3(0, 1.53, 0.005)))
        let board = SCNBox(width: 0.17, height: 0.21, length: 0.06, chamferRadius: 0)
        gate.addChildNode(Geometry.node(board, black, at: SCNVector3(0, 1.53, 0.01)))
        let shimaki = SCNBox(width: 1.78, height: 0.08, length: 0.11, chamferRadius: 0.005)
        gate.addChildNode(Geometry.node(shimaki, Geometry.lacquer(vermilion), at: SCNVector3(0, 1.69, 0)))
        // The kasagi: a black top beam whose underside rises towards both ends.
        let half: CGFloat = 1.1, profile = UIBezierPath()
        let samples = 32
        for i in 0...samples {
            let x = -half + 2 * half * CGFloat(i) / CGFloat(samples)
            let y = 0.15 * pow(abs(x) / half, 2.4)
            if i == 0 { profile.move(to: CGPoint(x: x, y: y)) } else { profile.addLine(to: CGPoint(x: x, y: y)) }
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let x = -half + 2 * half * CGFloat(i) / CGFloat(samples)
            profile.addLine(to: CGPoint(x: x, y: 0.12 + 0.19 * pow(abs(x) / half, 2.4)))
        }
        profile.close()
        let kasagi = SCNShape(path: profile, extrusionDepth: 0.16)
        gate.addChildNode(Geometry.node(kasagi, Geometry.lacquer(black, shine: 0.5), at: SCNVector3(0, 1.73, 0)))
        return Geometry.flattened(gate)
    }

    static func pagoda() -> SCNNode {
        let tower = SCNNode()
        let plinth = SCNBox(width: 0.62, height: 0.1, length: 0.62, chamferRadius: 0.005)
        tower.addChildNode(Geometry.node(plinth, Geometry.textured(Textures.stone(Geometry.rgb(0.7, 0.67, 0.6)), repeat: CGSize(width: 3, height: 1)), at: SCNVector3(0, 0.05, 0)))
        var y: Float = 0.1
        let plaster = Geometry.rgb(0.95, 0.9, 0.8)
        for tier in 0..<3 {
            let width = Float(0.42 - 0.08 * Double(tier)), height: Float = 0.24
            let body = SCNBox(width: CGFloat(width), height: CGFloat(height), length: CGFloat(width), chamferRadius: 0)
            tower.addChildNode(Geometry.node(body, tier == 0 ? vermilion : vermilion.darker(0.08), at: SCNVector3(0, y + height / 2, 0)))
            // Plaster panels with a dark window on each face.
            for face in 0..<4 {
                let angle = Float(face) * .pi / 2
                let outward = simd_float3(sin(angle), 0, cos(angle))
                let panel = SCNBox(width: CGFloat(width) * 0.62, height: CGFloat(height) * 0.55, length: 0.01, chamferRadius: 0)
                let wall = Geometry.node(panel, plaster, at: SCNVector3(outward * (width / 2 + 0.004) + simd_float3(0, y + height / 2, 0)))
                wall.eulerAngles.y = angle
                tower.addChildNode(wall)
                let pane = SCNBox(width: CGFloat(width) * 0.22, height: CGFloat(height) * 0.38, length: 0.01, chamferRadius: 0)
                let window = Geometry.node(pane, Geometry.glow(Geometry.rgb(1, 0.55, 0.25), strength: 1.2), at: SCNVector3(outward * (width / 2 + 0.01) + simd_float3(0, y + height / 2, 0)))
                window.eulerAngles.y = angle
                tower.addChildNode(window)
            }
            // A balcony rail just above the floor of each tier.
            let rail = SCNTube(innerRadius: CGFloat(width) * 0.68, outerRadius: CGFloat(width) * 0.74, height: 0.02); rail.radialSegmentCount = 4
            let railNode = Geometry.node(rail, vermilion.darker(0.3), at: SCNVector3(0, y + 0.05, 0)); railNode.eulerAngles.y = .pi / 4
            tower.addChildNode(railNode)
            y += height
            let eave = width * 1.08
            let cap = Geometry.curvedRoof(sides: 4, eave: eave, apex: 0.03, height: 0.13, lift: 0.07, tile: roof, under: vermilion.darker(0.3),
                                          rows: 5, endTiles: false, rotation: .pi / 4)
            cap.position = SCNVector3(0, y, 0)
            tower.addChildNode(cap)
            // Paper lanterns hanging from the two front corners of the lowest roof.
            if tier == 0 {
                for angle: Float in [.pi / 4, 3 * .pi / 4] {
                    let spot = simd_float3(cos(angle), 0, sin(angle)) * eave * 0.96
                    tower.addChildNode(Geometry.limb(from: SCNVector3(spot.x, y - 0.01, spot.z), to: SCNVector3(spot.x, y - 0.07, spot.z), radius: 0.003, color: black, taper: 1))
                    let paper = SCNSphere(radius: 0.032); paper.segmentCount = 16
                    let chochin = Geometry.node(paper, Geometry.glow(Geometry.rgb(1, 0.36, 0.2), strength: 3.4), at: SCNVector3(spot.x, y - 0.11, spot.z))
                    chochin.scale = SCNVector3(1, 1.35, 1)
                    tower.addChildNode(chochin)
                }
            }
            // A small bell under each lifted corner.
            for corner in 0..<4 {
                let angle = Float(corner) * .pi / 2 + .pi / 4
                let bell = SCNSphere(radius: 0.018); bell.segmentCount = 12
                let spot = simd_float3(cos(angle), 0, sin(angle)) * eave * 1.02
                tower.addChildNode(Geometry.node(bell, Geometry.lacquer(gold, shine: 0.9), at: SCNVector3(spot.x, y + 0.02, spot.z)))
            }
            y += 0.1
        }
        let spire = SCNCylinder(radius: 0.015, height: 0.42); spire.radialSegmentCount = 10
        tower.addChildNode(Geometry.node(spire, Geometry.lacquer(gold, shine: 0.9), at: SCNVector3(0, y + 0.21, 0)))
        // The nine rings of the spire.
        for i in 0..<9 {
            let ring = SCNCylinder(radius: 0.04 - CGFloat(i) * 0.0018, height: 0.011); ring.radialSegmentCount = 14
            tower.addChildNode(Geometry.node(ring, gold.lighter(0.1), at: SCNVector3(0, y + 0.07 + Float(i) * 0.034, 0)))
        }
        let jewel = SCNSphere(radius: 0.03); jewel.segmentCount = 14
        tower.addChildNode(Geometry.node(jewel, gold.lighter(0.2), at: SCNVector3(0, y + 0.44, 0)))
        return Geometry.flattened(tower)
    }

    /// A stone lantern of the kind that lines a shrine approach, with a warm light inside.
    static func lantern() -> SCNNode {
        let lantern = SCNNode()
        let stone = Geometry.rgb(0.62, 0.6, 0.56)
        let foot = SCNCylinder(radius: 0.08, height: 0.05); foot.radialSegmentCount = 12
        lantern.addChildNode(Geometry.node(foot, stone.darker(0.1), at: SCNVector3(0, 0.025, 0)))
        let post = SCNCylinder(radius: 0.04, height: 0.32); post.radialSegmentCount = 12
        lantern.addChildNode(Geometry.node(post, stone, at: SCNVector3(0, 0.2, 0)))
        let shelf = SCNBox(width: 0.18, height: 0.03, length: 0.18, chamferRadius: 0)
        lantern.addChildNode(Geometry.node(shelf, stone.darker(0.05), at: SCNVector3(0, 0.37, 0)))
        let glow = SCNBox(width: 0.14, height: 0.12, length: 0.14, chamferRadius: 0)
        lantern.addChildNode(Geometry.node(glow, Geometry.glow(Geometry.rgb(1, 0.74, 0.4), strength: 3), at: SCNVector3(0, 0.445, 0)))
        let cap = SCNPyramid(width: 0.27, height: 0.11, length: 0.27)
        lantern.addChildNode(Geometry.node(cap, stone.darker(0.1), at: SCNVector3(0, 0.505, 0)))
        let knob = SCNSphere(radius: 0.025); knob.segmentCount = 12
        lantern.addChildNode(Geometry.node(knob, stone.darker(0.1), at: SCNVector3(0, 0.63, 0)))
        return Geometry.flattened(lantern)
    }

    static func mapleTree() -> SCNNode {
        let tree = SCNNode()
        let bark = Geometry.rgb(0.28, 0.2, 0.17)
        let wood = SCNNode()
        let fork = SCNVector3(1.45, 0.85, -1.05)
        wood.addChildNode(Geometry.limb(from: SCNVector3(1.5, 0, -1.05), to: fork, radius: 0.065, color: bark))
        for end in [SCNVector3(1.15, 1.2, -0.95), SCNVector3(1.75, 1.25, -1.1), SCNVector3(1.5, 1.5, -1.2)] {
            wood.addChildNode(Geometry.limb(from: fork, to: end, radius: 0.035, color: bark))
        }
        tree.addChildNode(Geometry.flattened(wood))
        let clusters: [(simd_float3, Float)] = [
            (simd_float3(1.45, 1.28, -1.05), 0.38), (simd_float3(1.12, 1.12, -0.92), 0.28),
            (simd_float3(1.72, 1.18, -1.12), 0.29), (simd_float3(1.48, 1.55, -1.18), 0.26)
        ]
        // Deep red inside and below, turning orange and gold towards the sunlit crown.
        let red = simd_float3(0.62, 0.09, 0.06), orange = simd_float3(0.85, 0.3, 0.08), gold = simd_float3(0.92, 0.55, 0.15)
        tree.addChildNode(Geometry.foliage(clusters: clusters, count: 4200, size: 0.036...0.062, colors: maple, image: Textures.maple,
                                           seed: 41, fill: 0.15) { point in
            let t = simd_clamp((point.y - 0.95) / 0.75, 0, 1)
            let tone = t < 0.6 ? simd_mix(red, orange, simd_float3(repeating: t / 0.6)) : simd_mix(orange, gold, simd_float3(repeating: (t - 0.6) / 0.4))
            return UIColor(red: CGFloat(tone.x), green: CGFloat(tone.y), blue: CGFloat(tone.z), alpha: 1)
        })
        return tree
    }

    /// Low rounded shrubs at the foot of the pagoda.
    static func shrubs() -> SCNNode {
        let spots: [(simd_float3, Float)] = [(simd_float3(0.45, 0.1, -0.35), 0.14), (simd_float3(1.5, 0.1, -0.2), 0.16), (simd_float3(0.6, 0.1, -1.1), 0.13)]
        let group = SCNNode()
        group.addChildNode(Geometry.foliage(clusters: spots, count: 1500, size: 0.024...0.037,
                                            colors: [Geometry.rgb(0.22, 0.45, 0.24), Geometry.rgb(0.3, 0.52, 0.27)], image: Textures.leaf, seed: 51,
                                            wind: 0.006, fill: 0.1))
        return group
    }

    static func leaves() -> [(SCNParticleSystem, SCNNode)] {
        let emitter = SCNNode(); emitter.position = canopyCentre
        return [(Geometry.drift(color: Geometry.rgb(0.95, 0.38, 0.14), image: Textures.maple, rate: 2.2, size: 0.06, shape: SCNSphere(radius: 0.35)), emitter)]
    }
}
