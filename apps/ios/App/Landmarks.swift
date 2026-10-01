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
    var body: some View {
        if let id = language.landmarkID, let build = Landmarks.all[id] {
            ZStack {
                // A halo behind the island: cheap in SwiftUI, and it lifts the scene off the black page.
                GeometryReader { geometry in
                    // Fades out inside the frame, so no edge of the gradient is ever cut off.
                    RadialGradient(colors: [(Landmarks.halo[id] ?? MuralColor.accent).opacity(0.26 + energy * 0.12), .clear],
                                   center: .center, startRadius: 2, endRadius: min(geometry.size.width, geometry.size.height) * 0.47)
                }
                LandmarkView(id: id, build: build, energy: energy, listening: listening, active: active)
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
    /// The soft light behind each landmark, so the scene glows against the black page.
    static let halo: [String: Color] = [
        "pavilion": Color(red: 0.86, green: 0.55, blue: 0.95),
        "torii": Color(red: 1, green: 0.5, blue: 0.25)
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
/// are no shadows and two lights, it runs at 30 frames a second, and nothing is drawn at all while
/// the app is in the background, the conversation is closing or Reduce Motion is on.
struct LandmarkView: UIViewRepresentable {
    let id: String
    let build: () -> LandmarkScene
    var energy: Double
    var listening: Bool
    var active: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.antialiasingMode = .multisampling2X
        view.preferredFramesPerSecond = 30
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
        camera.fieldOfView = 30
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
        cameraNode.look(at: SCNVector3(0, 0.95, 0))
        scene.rootNode.addChildNode(cameraNode)

        // Three-point light: a warm key from the front left, a cool rim from behind that outlines the
        // roofs and trees, and a low violet fill so shadows keep their colour instead of going dead.
        let key = SCNLight(); key.type = .directional; key.intensity = 1350
        key.color = UIColor(red: 1, green: 0.9, blue: 0.78, alpha: 1)
        let keyNode = SCNNode(); keyNode.light = key; keyNode.eulerAngles = SCNVector3(-0.8, -0.55, 0)
        scene.rootNode.addChildNode(keyNode)
        let rim = SCNLight(); rim.type = .directional; rim.intensity = 900
        rim.color = UIColor(red: 0.62, green: 0.72, blue: 1, alpha: 1)
        let rimNode = SCNNode(); rimNode.light = rim; rimNode.eulerAngles = SCNVector3(-0.35, 2.6, 0)
        scene.rootNode.addChildNode(rimNode)
        let fill = SCNLight(); fill.type = .ambient; fill.intensity = 260
        fill.color = UIColor(red: 0.62, green: 0.56, blue: 0.82, alpha: 1)
        let fillNode = SCNNode(); fillNode.light = fill
        scene.rootNode.addChildNode(fillNode)

        view.scene = scene
        view.pointOfView = cameraNode
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
        var pulse: SCNNode?
        var particles: [SCNParticleSystem] = []
        var baseRates: [CGFloat] = []
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
        cylinder.radialSegmentCount = 7
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

    /// A floating island: a grassy top over a rocky underside, ringed with stones, carpeted with
    /// swaying grass and a scattering of flowers. `clear` keeps grass off paths and buildings.
    static func island(radius: Float, top: UIColor, rock: UIColor, seed: UInt64, clear: (simd_float2) -> Bool) -> SCNNode {
        var random = Seeded(seed)
        let island = SCNNode()
        let ground = SCNNode()
        let soil = SCNCylinder(radius: CGFloat(radius), height: 0.14); soil.radialSegmentCount = 14
        ground.addChildNode(node(soil, top, at: SCNVector3(0, -0.07, 0)))
        let earth = SCNCone(topRadius: CGFloat(radius) * 0.98, bottomRadius: CGFloat(radius) * 0.22, height: 1.0); earth.radialSegmentCount = 11
        ground.addChildNode(node(earth, rock, at: SCNVector3(0, -0.64, 0)))
        let lower = SCNCone(topRadius: CGFloat(radius) * 0.24, bottomRadius: 0.03, height: 0.45); lower.radialSegmentCount = 8
        ground.addChildNode(node(lower, rock.darker(0.15), at: SCNVector3(0.1, -1.36, 0.05)))
        // Rocks around the rim and a few on the slope, for an edge that looks worn rather than cut.
        for index in 0..<16 {
            let angle = Float(index) / 16 * 2 * .pi + random.range(-0.12...0.12)
            let stone = SCNSphere(radius: CGFloat(random.range(0.07...0.13))); stone.segmentCount = 6
            let shade = rock.darker(CGFloat(random.range(-0.15...0.1)))
            let rim = node(stone, shade, at: SCNVector3(cos(angle) * radius * 0.97, random.range(-0.12...0.0), sin(angle) * radius * 0.97))
            rim.scale = SCNVector3(1.3, 0.7, 1.1)
            ground.addChildNode(rim)
        }
        for _ in 0..<7 {
            let angle = random.range(0...(2 * .pi)), depth = random.range(0.25...0.7)
            let stone = SCNSphere(radius: CGFloat(random.range(0.08...0.16))); stone.segmentCount = 6
            let r = radius * (0.98 - depth * 0.75)
            ground.addChildNode(node(stone, rock.darker(0.2), at: SCNVector3(cos(angle) * r, -depth, sin(angle) * r)))
        }
        island.addChildNode(flattened(ground))
        island.addChildNode(grass(radius: radius * 0.97, base: top, using: &random, clear: clear))
        return island
    }

    /// Grass blades and small flowers as one mesh, swaying from their tips.
    static func grass(radius: Float, base: UIColor, using random: inout Seeded, clear: (simd_float2) -> Bool) -> SCNNode {
        var positions: [SCNVector3] = [], normals: [SCNVector3] = [], colors: [simd_float4] = [], uvs: [CGPoint] = [], indices: [UInt32] = []
        let root = simd_float4(0.17, 0.3, 0.15, 1), tips = [simd_float4(0.42, 0.6, 0.3, 1), simd_float4(0.5, 0.66, 0.32, 1), simd_float4(0.36, 0.55, 0.28, 1)]
        var placed = 0, attempts = 0
        while placed < 1500 && attempts < 6000 {
            attempts += 1
            let r = radius * sqrt(random.unit()), a = random.range(0...(2 * .pi))
            let spot = simd_float2(cos(a) * r, sin(a) * r)
            guard !clear(spot) else { continue }
            placed += 1
            let height = random.range(0.06...0.15), width = random.range(0.012...0.022)
            let facing = random.range(0...(2 * .pi)), lean = random.range(-0.03...0.03)
            let side = simd_float3(cos(facing), 0, sin(facing)) * width
            let foot = simd_float3(spot.x, 0, spot.y)
            let tip = foot + simd_float3(lean, height, random.range(-0.03...0.03))
            let start = UInt32(positions.count)
            for (point, v) in [(foot - side, 0.0), (foot + side, 0.0), (tip, 1.0)] {
                positions.append(SCNVector3(point)); normals.append(SCNVector3(0, 1, 0)); uvs.append(CGPoint(x: 0.5, y: v))
            }
            let tipColor = tips[Int(random.unit() * Float(tips.count - 1) + 0.5)] * random.range(0.85...1.1)
            colors += [root, root, simd_float4(min(1, tipColor.x), min(1, tipColor.y), min(1, tipColor.z), 1)]
            indices += [start, start + 1, start + 2]
        }
        // Flowers: a few small white, yellow and pink dots raised above the blades.
        let petals = [simd_float4(1, 0.97, 0.92, 1), simd_float4(1, 0.86, 0.4, 1), simd_float4(1, 0.72, 0.82, 1)]
        var flowers = 0; attempts = 0
        while flowers < 45 && attempts < 800 {
            attempts += 1
            let r = radius * 0.92 * sqrt(random.unit()), a = random.range(0...(2 * .pi))
            let spot = simd_float2(cos(a) * r, sin(a) * r)
            guard !clear(spot) else { continue }
            flowers += 1
            let center = simd_float3(spot.x, random.range(0.06...0.11), spot.y), size: Float = 0.022
            let start = UInt32(positions.count), color = petals[flowers % petals.count]
            for corner in [simd_float3(-size, 0, 0), simd_float3(0, 0, -size), simd_float3(size, 0, 0), simd_float3(0, 0, size)] {
                positions.append(SCNVector3(center + corner)); normals.append(SCNVector3(0, 1, 0)); uvs.append(CGPoint(x: 0.5, y: 0.6)); colors.append(color)
            }
            indices += [start, start + 1, start + 2, start, start + 2, start + 3]
        }
        let geometry = mesh(positions: positions, normals: normals, colors: colors, uvs: uvs, indices: indices)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.white
        material.lightingModel = .lambert
        material.isDoubleSided = true
        material.shaderModifiers = [.geometry: wind]
        material.setValue(0.025, forKey: "windStrength")
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
        for card in cards {
            let start = UInt32(positions.count)
            let corners = [card.center - card.u - card.v, card.center + card.u - card.v, card.center + card.u + card.v, card.center - card.u + card.v]
            for corner in corners { positions.append(SCNVector3(corner)); normals.append(SCNVector3(card.normal)); vertexColors.append(card.color) }
            uvs += [CGPoint(x: 0, y: 1), CGPoint(x: 1, y: 1), CGPoint(x: 1, y: 0), CGPoint(x: 0, y: 0)]
            indices += [start, start + 1, start + 2, start, start + 2, start + 3]
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
    /// ridges, upturned corner tips and round end tiles along the eaves.
    static func curvedRoof(sides: Int, eave: Float, apex: Float, height: Float, lift: Float,
                           tile: UIColor, under: UIColor, rows: Int, endTiles: Bool, rotation: Float = 0) -> SCNNode {
        let steps = 7
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
            for step in 1...5 {
                let next = point(sector, 0, Float(step) / 5) + simd_float3(0, 0.03, 0)
                roof.addChildNode(limb(from: SCNVector3(previous), to: SCNVector3(next), radius: ridge, color: tile.darker(0.2), taper: 1))
                previous = next
            }
            let tip = point(sector, 0, 1)
            roof.addChildNode(limb(from: SCNVector3(tip), to: SCNVector3(tip * simd_float3(1.06, 1, 1.06) + simd_float3(0, 0.1 * scale + 0.02, 0)),
                                   radius: ridge * 1.15, color: tile.darker(0.28)))
            guard endTiles else { continue }
            // Round end tiles along the eave, facing outwards.
            for k in 1..<8 {
                let u = Float(k) / 8, spot = point(sector, u, 1)
                let outward = simd_normalize(simd_float3(spot.x, 0, spot.z))
                let disc = SCNCylinder(radius: CGFloat(0.035 * scale), height: 0.02); disc.radialSegmentCount = 8
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
        let root = Geometry.island(radius: 1.8, top: Geometry.rgb(0.26, 0.4, 0.24), rock: Geometry.rgb(0.42, 0.33, 0.27), seed: 11) { spot in
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
            let pillar = SCNCylinder(radius: 0.045, height: 0.88); pillar.radialSegmentCount = 8
            building.addChildNode(Geometry.node(pillar, Geometry.lacquer(wood), at: SCNVector3(corner.x, 0.86, corner.z)))
            let footing = SCNCylinder(radius: 0.065, height: 0.05); footing.radialSegmentCount = 8
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
            for k in 1..<4 {
                let p = simd_mix(a, b, simd_float3(repeating: Float(k) / 4))
                let baluster = SCNCylinder(radius: 0.01, height: 0.24); baluster.radialSegmentCount = 5
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
            for k in 1..<6 {
                let p = simd_mix(a, b, simd_float3(repeating: Float(k) / 6)) * 1.06 + outward * 0.02
                let dot = SCNCylinder(radius: 0.022, height: 0.01); dot.radialSegmentCount = 6
                let motif = Geometry.node(dot, paints[(i + k) % paints.count], at: SCNVector3(p.x, 1.22, p.z))
                motif.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: outward)
                building.addChildNode(motif)
            }
        }
        // Silk lanterns hanging under the front eaves: red, capped in blue, lit from within.
        for corner in corners where corner.z > -0.1 {
            let spot = corner * 1.14
            building.addChildNode(Geometry.limb(from: SCNVector3(spot.x, 1.3, spot.z), to: SCNVector3(spot.x, 1.13, spot.z), radius: 0.004, color: wood, taper: 1))
            let body = SCNCylinder(radius: 0.045, height: 0.11); body.radialSegmentCount = 10
            building.addChildNode(Geometry.node(body, Geometry.glow(Geometry.rgb(1, 0.3, 0.22), strength: 3.4), at: SCNVector3(spot.x, 1.07, spot.z)))
            for y: Float in [1.13, 1.01] {
                let cap = SCNCylinder(radius: 0.05, height: 0.02); cap.radialSegmentCount = 10
                building.addChildNode(Geometry.node(cap, Geometry.lacquer(Geometry.rgb(0.15, 0.3, 0.7)), at: SCNVector3(spot.x, y, spot.z)))
            }
            let tassel = SCNCone(topRadius: 0.012, bottomRadius: 0.004, height: 0.06); tassel.radialSegmentCount = 6
            building.addChildNode(Geometry.node(tassel, Geometry.rgb(0.95, 0.3, 0.25), at: SCNVector3(spot.x, 0.97, spot.z)))
        }
        let roof = Geometry.curvedRoof(sides: 6, eave: 1.2, apex: 0.08, height: 0.58, lift: 0.22, tile: tile, under: green, rows: 9, endTiles: true)
        roof.position = SCNVector3(0, 1.32, 0)
        building.addChildNode(roof)
        // The finial: stacked knobs at the crown, as in the photograph.
        for (index, radius) in [0.1, 0.078, 0.06, 0.035].enumerated() {
            let knob = SCNSphere(radius: radius); knob.segmentCount = 10
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
        tree.addChildNode(Geometry.foliage(clusters: clusters, count: 4200, size: 0.04...0.068, colors: blossom, image: Textures.blossom,
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
        tree.addChildNode(Geometry.foliage(clusters: tiers.map { ($0.0, $0.1) }, count: 1200, size: 0.035...0.055,
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
        let root = Geometry.island(radius: 1.8, top: Geometry.rgb(0.26, 0.39, 0.24), rock: Geometry.rgb(0.4, 0.34, 0.3), seed: 12) { spot in
            stones.contains { simd_distance($0, spot) < 0.17 }
                || simd_distance(spot, tower) < 0.5
                || [-0.6, 0.6].contains { simd_distance(spot, simd_float2(gate.x + $0, gate.y)) < 0.13 }
                || [simd_float2(-1.2, 0.8), simd_float2(0.4, 1.05)].contains { simd_distance($0, spot) < 0.15 }
                || simd_distance(spot, simd_float2(1.5, -1.05)) < 0.1
        }
        let approach = SCNNode()
        var random = Seeded(5)
        for spot in stones {
            let slab = SCNCylinder(radius: CGFloat(random.range(0.12...0.15)), height: 0.04); slab.radialSegmentCount = 7
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
            let pillar = SCNCone(topRadius: 0.06, bottomRadius: 0.075, height: 1.7); pillar.radialSegmentCount = 12
            gate.addChildNode(Geometry.node(pillar, Geometry.lacquer(vermilion), at: SCNVector3(x, 0.95, 0)))
            let foot = SCNCylinder(radius: 0.095, height: 0.22); foot.radialSegmentCount = 12
            gate.addChildNode(Geometry.node(foot, black, at: SCNVector3(x, 0.11, 0)))
            let collar = SCNCylinder(radius: 0.1, height: 0.03); collar.radialSegmentCount = 12
            gate.addChildNode(Geometry.node(collar, black.darker(0.2), at: SCNVector3(x, 0.235, 0)))
            // The daiwa: a black ring where each pillar meets the top beams.
            let ring = SCNCylinder(radius: 0.078, height: 0.07); ring.radialSegmentCount = 12
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
        let samples = 14
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
                    let paper = SCNSphere(radius: 0.032); paper.segmentCount = 10
                    let chochin = Geometry.node(paper, Geometry.glow(Geometry.rgb(1, 0.36, 0.2), strength: 3.4), at: SCNVector3(spot.x, y - 0.11, spot.z))
                    chochin.scale = SCNVector3(1, 1.35, 1)
                    tower.addChildNode(chochin)
                }
            }
            // A small bell under each lifted corner.
            for corner in 0..<4 {
                let angle = Float(corner) * .pi / 2 + .pi / 4
                let bell = SCNSphere(radius: 0.018); bell.segmentCount = 8
                let spot = simd_float3(cos(angle), 0, sin(angle)) * eave * 1.02
                tower.addChildNode(Geometry.node(bell, Geometry.lacquer(gold, shine: 0.9), at: SCNVector3(spot.x, y + 0.02, spot.z)))
            }
            y += 0.1
        }
        let spire = SCNCylinder(radius: 0.015, height: 0.42); spire.radialSegmentCount = 6
        tower.addChildNode(Geometry.node(spire, Geometry.lacquer(gold, shine: 0.9), at: SCNVector3(0, y + 0.21, 0)))
        for i in 0..<5 {
            let ring = SCNCylinder(radius: 0.042 - CGFloat(i) * 0.003, height: 0.014); ring.radialSegmentCount = 8
            tower.addChildNode(Geometry.node(ring, gold.lighter(0.1), at: SCNVector3(0, y + 0.08 + Float(i) * 0.06, 0)))
        }
        let jewel = SCNSphere(radius: 0.03); jewel.segmentCount = 8
        tower.addChildNode(Geometry.node(jewel, gold.lighter(0.2), at: SCNVector3(0, y + 0.44, 0)))
        return Geometry.flattened(tower)
    }

    /// A stone lantern of the kind that lines a shrine approach, with a warm light inside.
    static func lantern() -> SCNNode {
        let lantern = SCNNode()
        let stone = Geometry.rgb(0.62, 0.6, 0.56)
        let foot = SCNCylinder(radius: 0.08, height: 0.05); foot.radialSegmentCount = 6
        lantern.addChildNode(Geometry.node(foot, stone.darker(0.1), at: SCNVector3(0, 0.025, 0)))
        let post = SCNCylinder(radius: 0.04, height: 0.32); post.radialSegmentCount = 6
        lantern.addChildNode(Geometry.node(post, stone, at: SCNVector3(0, 0.2, 0)))
        let shelf = SCNBox(width: 0.18, height: 0.03, length: 0.18, chamferRadius: 0)
        lantern.addChildNode(Geometry.node(shelf, stone.darker(0.05), at: SCNVector3(0, 0.37, 0)))
        let glow = SCNBox(width: 0.14, height: 0.12, length: 0.14, chamferRadius: 0)
        lantern.addChildNode(Geometry.node(glow, Geometry.glow(Geometry.rgb(1, 0.74, 0.4), strength: 3), at: SCNVector3(0, 0.445, 0)))
        let cap = SCNPyramid(width: 0.27, height: 0.11, length: 0.27)
        lantern.addChildNode(Geometry.node(cap, stone.darker(0.1), at: SCNVector3(0, 0.505, 0)))
        let knob = SCNSphere(radius: 0.025); knob.segmentCount = 8
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
        tree.addChildNode(Geometry.foliage(clusters: clusters, count: 2600, size: 0.045...0.075, colors: maple, image: Textures.maple,
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
        group.addChildNode(Geometry.foliage(clusters: spots, count: 800, size: 0.03...0.045,
                                            colors: [Geometry.rgb(0.22, 0.45, 0.24), Geometry.rgb(0.3, 0.52, 0.27)], image: Textures.leaf, seed: 51,
                                            wind: 0.006, fill: 0.1))
        return group
    }

    static func leaves() -> [(SCNParticleSystem, SCNNode)] {
        let emitter = SCNNode(); emitter.position = canopyCentre
        return [(Geometry.drift(color: Geometry.rgb(0.95, 0.38, 0.14), image: Textures.maple, rate: 2.2, size: 0.06, shape: SCNSphere(radius: 0.35)), emitter)]
    }
}
