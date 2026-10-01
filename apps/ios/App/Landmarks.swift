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
            LandmarkView(id: id, build: build, energy: energy, listening: listening, active: active)
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
        "pavilion": { LandmarkScene(root: Pavilion.island(), particles: Pavilion.petals()) },
        "torii": { LandmarkScene(root: ToriiGate.island(), particles: ToriiGate.leaves()) }
    ]
}

struct LandmarkScene {
    var root: SCNNode
    var particles: [(SCNParticleSystem, SCNNode)]
}

/// Renders a landmark on a transparent SceneKit view.
///
/// Built for a screen that is on for a whole conversation: a few hundred triangles of flat-shaded
/// geometry, no shadows, two lights, 30 frames a second, and nothing drawn at all while the app is
/// in the background, the conversation is closing or Reduce Motion is on.
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
        camera.fieldOfView = 32
        camera.zNear = 0.1; camera.zFar = 50
        let cameraNode = SCNNode(); cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 2.3, 8.2)
        cameraNode.look(at: SCNVector3(0, 1.0, 0))
        scene.rootNode.addChildNode(cameraNode)

        let sun = SCNLight(); sun.type = .directional; sun.intensity = 950
        sun.color = UIColor(red: 1, green: 0.93, blue: 0.84, alpha: 1)
        let sunNode = SCNNode(); sunNode.light = sun; sunNode.eulerAngles = SCNVector3(-0.75, -0.6, 0)
        scene.rootNode.addChildNode(sunNode)
        let fill = SCNLight(); fill.type = .ambient; fill.intensity = 420
        fill.color = UIColor(red: 0.72, green: 0.66, blue: 0.78, alpha: 1)
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

private enum Geometry {
    static func material(_ color: UIColor, doubleSided: Bool = false) -> SCNMaterial {
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .lambert
        material.isDoubleSided = doubleSided
        return material
    }
    static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> UIColor { UIColor(red: r, green: g, blue: b, alpha: 1) }

    static func node(_ geometry: SCNGeometry, _ color: UIColor, at position: SCNVector3 = SCNVector3Zero) -> SCNNode {
        geometry.materials = [material(color)]
        let node = SCNNode(geometry: geometry); node.position = position
        return node
    }

    /// A cylinder from `a` to `b`, for trunks and branches.
    static func limb(from a: SCNVector3, to b: SCNVector3, radius: CGFloat, color: UIColor) -> SCNNode {
        let dx = b.x - a.x, dy = b.y - a.y, dz = b.z - a.z
        let length = sqrt(dx * dx + dy * dy + dz * dz)
        let cylinder = SCNCone(topRadius: radius * 0.7, bottomRadius: radius, height: CGFloat(length))
        cylinder.radialSegmentCount = 8
        let node = node(cylinder, color, at: SCNVector3((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2))
        // A cylinder stands on y; point that axis along the limb.
        let axis = simd_normalize(simd_float3(Float(dx), Float(dy), Float(dz)))
        node.simdOrientation = simd_quatf(from: simd_float3(0, 1, 0), to: axis)
        return node
    }

    /// A floating island: a grassy top over a rocky cone, the base every landmark stands on.
    static func island(radius: CGFloat, top: UIColor, rock: UIColor) -> SCNNode {
        let island = SCNNode()
        let grass = SCNCylinder(radius: radius, height: 0.14); grass.radialSegmentCount = 12
        island.addChildNode(node(grass, top, at: SCNVector3(0, -0.07, 0)))
        let earth = SCNCone(topRadius: radius * 0.98, bottomRadius: radius * 0.18, height: 1.1); earth.radialSegmentCount = 10
        island.addChildNode(node(earth, rock, at: SCNVector3(0, -0.69, 0)))
        return island
    }

    /// A many-sided roof whose surface sags towards the eaves and lifts at every corner, the curve
    /// both Korean and Japanese roofs share. Returns the tiled top and a separately coloured
    /// underside, flat-shaded so a low triangle count still reads as crafted.
    static func curvedRoof(sides: Int, eave: Float, apex: Float, height: Float, lift: Float,
                           top: UIColor, under: UIColor, rotation: Float = 0) -> SCNNode {
        let steps = 7
        var upper: [SCNVector3] = [], upperNormals: [SCNVector3] = []
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
        func add(_ a: simd_float3, _ b: simd_float3, _ c: simd_float3) {
            var n = simd_normalize(simd_cross(b - a, c - a))
            var (q, r) = (b, c)
            if n.y < 0 { n = -n; swap(&q, &r) }
            for vertex in [a, q, r] { upper.append(SCNVector3(vertex)); upperNormals.append(SCNVector3(n)) }
            let drop = simd_float3(0, -0.025, 0)
            for vertex in [a, r, q] { lower.append(SCNVector3(vertex + drop)); lowerNormals.append(SCNVector3(-n)) }
        }
        for sector in 0..<sides {
            for i in 0..<steps { for j in 0..<steps {
                let u0 = Float(i) / Float(steps), u1 = Float(i + 1) / Float(steps)
                let v0 = Float(j) / Float(steps), v1 = Float(j + 1) / Float(steps)
                let a = point(sector, u0, v0), b = point(sector, u1, v0), c = point(sector, u1, v1), d = point(sector, u0, v1)
                add(a, b, c); add(a, c, d)
            } }
        }
        func geometry(_ vertices: [SCNVector3], _ normals: [SCNVector3], _ color: UIColor) -> SCNGeometry {
            let element = SCNGeometryElement(indices: Array(0..<Int32(vertices.count)), primitiveType: .triangles)
            let geometry = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(normals: normals)], elements: [element])
            geometry.materials = [material(color)]
            return geometry
        }
        let roof = SCNNode()
        roof.addChildNode(SCNNode(geometry: geometry(upper, upperNormals, top)))
        roof.addChildNode(SCNNode(geometry: geometry(lower, lowerNormals, under)))
        // Hip ridges from the apex to each lifted corner, and an upturned tip at every corner,
        // sized to the roof so a small pagoda cap is not crowded by them.
        let ridge = CGFloat(0.028 * min(1, eave / 1.18) + 0.006)
        for sector in 0..<sides {
            var previous = point(sector, 0, 0) + simd_float3(0, 0.03, 0)
            for step in 1...5 {
                let next = point(sector, 0, Float(step) / 5) + simd_float3(0, 0.03, 0)
                roof.addChildNode(limb(from: SCNVector3(previous), to: SCNVector3(next), radius: ridge, color: top.darker(0.18)))
                previous = next
            }
            let tip = point(sector, 0, 1)
            roof.addChildNode(limb(from: SCNVector3(tip), to: SCNVector3(tip * simd_float3(1.06, 1, 1.06) + simd_float3(0, 0.1 * min(1, eave / 1.18) + 0.02, 0)),
                                   radius: ridge * 1.1, color: top.darker(0.25)))
        }
        return roof
    }

    /// A falling-particle system: petals or leaves from a canopy.
    static func drift(color: UIColor, variation: UIColor? = nil, rate: CGFloat, shape: SCNGeometry) -> SCNParticleSystem {
        let system = SCNParticleSystem()
        system.particleImage = leafImage
        system.birthRate = rate
        system.particleLifeSpan = 5.5
        system.particleLifeSpanVariation = 1.5
        system.particleSize = 0.045
        system.particleSizeVariation = 0.02
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

    /// A soft almond shape, drawn once and shared by every petal and leaf.
    static let leafImage: UIImage = {
        let size = CGSize(width: 32, height: 32)
        return UIGraphicsImageRenderer(size: size).image { context in
            let path = UIBezierPath()
            path.move(to: CGPoint(x: 16, y: 2))
            path.addQuadCurve(to: CGPoint(x: 16, y: 30), controlPoint: CGPoint(x: 32, y: 16))
            path.addQuadCurve(to: CGPoint(x: 16, y: 2), controlPoint: CGPoint(x: 0, y: 16))
            UIColor.white.setFill(); path.fill()
        }
    }()
}

private extension UIColor {
    func darker(_ amount: CGFloat) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r * (1 - amount), green: g * (1 - amount), blue: b * (1 - amount), alpha: a)
    }
}

// MARK: Hexagonal pavilion beside a weeping cherry

/// A six-sided pavilion of the kind found in Korean palace gardens: a stepped stone base, red
/// pillars, a green painted band under the eaves, and a curved tiled roof with a finial, beside a
/// cherry tree in blossom.
private enum Pavilion {
    static let stone = Geometry.rgb(0.83, 0.77, 0.66)
    static let wood = Geometry.rgb(0.55, 0.18, 0.13)
    static let green = Geometry.rgb(0.16, 0.56, 0.47)
    static let tile = Geometry.rgb(0.36, 0.37, 0.4)
    static let blossom = [Geometry.rgb(1, 0.8, 0.88), Geometry.rgb(0.98, 0.7, 0.82), Geometry.rgb(1, 0.88, 0.93)]
    static let canopyCentre = SCNVector3(1.2, 1.75, -0.35)

    static func island() -> SCNNode {
        let root = Geometry.island(radius: 1.75, top: Geometry.rgb(0.3, 0.45, 0.27), rock: Geometry.rgb(0.42, 0.33, 0.27))
        let pavilion = building()
        pavilion.position = SCNVector3(-0.35, 0, 0.15)
        root.addChildNode(pavilion)
        root.addChildNode(cherry())
        return root
    }

    static func building() -> SCNNode {
        let building = SCNNode()
        // A hexagon's flat side faces the front, where the stairs meet it.
        let offset = Float.pi / 6
        let base = SCNCylinder(radius: 0.95, height: 0.26); base.radialSegmentCount = 6
        let baseNode = Geometry.node(base, stone, at: SCNVector3(0, 0.13, 0)); baseNode.eulerAngles.y = offset
        building.addChildNode(baseNode)
        let step = SCNCylinder(radius: 0.82, height: 0.12); step.radialSegmentCount = 6
        let stepNode = Geometry.node(step, stone.darker(0.06), at: SCNVector3(0, 0.32, 0)); stepNode.eulerAngles.y = offset
        building.addChildNode(stepNode)
        for i in 0..<3 {
            let stair = SCNBox(width: 0.5, height: 0.09, length: 0.16, chamferRadius: 0)
            building.addChildNode(Geometry.node(stair, stone.darker(0.03 * CGFloat(i)), at: SCNVector3(0, 0.045 + 0.09 * Float(i), 0.98 - 0.13 * Float(i))))
        }
        let floor = SCNCylinder(radius: 0.74, height: 0.05); floor.radialSegmentCount = 6
        let floorNode = Geometry.node(floor, wood.darker(0.2), at: SCNVector3(0, 0.4, 0)); floorNode.eulerAngles.y = offset
        building.addChildNode(floorNode)
        for i in 0..<6 {
            let angle = Float(i) * .pi / 3
            let pillar = SCNCylinder(radius: 0.045, height: 0.88); pillar.radialSegmentCount = 8
            building.addChildNode(Geometry.node(pillar, wood, at: SCNVector3(0.66 * cos(angle), 0.86, 0.66 * sin(angle))))
        }
        let band = SCNTube(innerRadius: 0.6, outerRadius: 0.72, height: 0.16); band.radialSegmentCount = 6
        let bandNode = Geometry.node(band, green, at: SCNVector3(0, 1.3, 0))
        bandNode.geometry?.materials = [Geometry.material(green, doubleSided: true)]
        building.addChildNode(bandNode)
        let trim = SCNTube(innerRadius: 0.62, outerRadius: 0.73, height: 0.03); trim.radialSegmentCount = 6
        building.addChildNode(Geometry.node(trim, Geometry.rgb(0.86, 0.33, 0.2), at: SCNVector3(0, 1.21, 0)))
        let roof = Geometry.curvedRoof(sides: 6, eave: 1.18, apex: 0.08, height: 0.56, lift: 0.2, top: tile, under: green)
        roof.position = SCNVector3(0, 1.38, 0)
        building.addChildNode(roof)
        // The finial: stacked knobs at the crown, as in the photograph.
        for (index, radius) in [0.1, 0.075, 0.055].enumerated() {
            let knob = SCNSphere(radius: radius); knob.segmentCount = 10
            building.addChildNode(Geometry.node(knob, tile.darker(0.15), at: SCNVector3(0, 1.98 + Float(index) * 0.12, 0)))
        }
        return building
    }

    static func cherry() -> SCNNode {
        let tree = SCNNode()
        let bark = Geometry.rgb(0.3, 0.2, 0.17)
        let base = SCNVector3(1.2, 0, -0.35)
        let fork = SCNVector3(1.15, 0.85, -0.35)
        tree.addChildNode(Geometry.limb(from: base, to: fork, radius: 0.09, color: bark))
        for end in [SCNVector3(0.75, 1.55, -0.2), SCNVector3(1.5, 1.65, -0.5), SCNVector3(1.2, 1.9, -0.25)] {
            tree.addChildNode(Geometry.limb(from: fork, to: end, radius: 0.05, color: bark))
        }
        // Clouds of blossom, then a few weeping strands hanging below them.
        let clusters: [(SCNVector3, CGFloat)] = [
            (SCNVector3(1.2, 1.9, -0.35), 0.48), (SCNVector3(0.75, 1.65, -0.2), 0.38), (SCNVector3(1.6, 1.7, -0.5), 0.4),
            (SCNVector3(1.0, 2.15, -0.45), 0.34), (SCNVector3(1.45, 2.1, -0.15), 0.32), (SCNVector3(0.9, 1.75, 0.15), 0.3)
        ]
        for (index, (position, radius)) in clusters.enumerated() {
            let cloud = SCNSphere(radius: radius); cloud.segmentCount = 9
            tree.addChildNode(Geometry.node(cloud, blossom[index % blossom.count], at: position))
        }
        for (index, position) in [SCNVector3(0.55, 1.3, -0.1), SCNVector3(0.8, 1.2, 0.2), SCNVector3(1.8, 1.35, -0.45), SCNVector3(1.55, 1.25, 0.05)].enumerated() {
            let strand = SCNSphere(radius: 0.13); strand.segmentCount = 8
            let node = Geometry.node(strand, blossom[(index + 1) % blossom.count], at: position)
            node.scale = SCNVector3(0.8, 2.1, 0.8)
            tree.addChildNode(node)
        }
        return tree
    }

    static func petals() -> [(SCNParticleSystem, SCNNode)] {
        let emitter = SCNNode(); emitter.position = canopyCentre
        return [(Geometry.drift(color: Geometry.rgb(1, 0.82, 0.9), rate: 3.5, shape: SCNSphere(radius: 0.55)), emitter)]
    }
}

// MARK: Torii gate beside a small pagoda

/// A vermilion torii with black bases and a black curved top beam, beside a three-tiered pagoda
/// and a small maple turning red.
private enum ToriiGate {
    static let vermilion = Geometry.rgb(0.9, 0.27, 0.12)
    /// Lifted from true black so the beam still reads against the dark page.
    static let black = Geometry.rgb(0.24, 0.21, 0.21)
    static let roof = Geometry.rgb(0.32, 0.36, 0.36)
    static let maple = [Geometry.rgb(0.86, 0.25, 0.12), Geometry.rgb(0.95, 0.45, 0.15), Geometry.rgb(0.75, 0.16, 0.1)]
    static let canopyCentre = SCNVector3(1.45, 1.3, -1.05)

    static func island() -> SCNNode {
        let root = Geometry.island(radius: 1.75, top: Geometry.rgb(0.29, 0.42, 0.26), rock: Geometry.rgb(0.4, 0.34, 0.3))
        let path = SCNBox(width: 0.62, height: 0.02, length: 1.7, chamferRadius: 0)
        root.addChildNode(Geometry.node(path, Geometry.rgb(0.5, 0.48, 0.45), at: SCNVector3(-0.4, 0.01, 0.75)))
        let gate = torii(); gate.position = SCNVector3(-0.4, 0, 0.55)
        root.addChildNode(gate)
        let tower = pagoda(); tower.position = SCNVector3(1.0, 0, -0.6); tower.scale = SCNVector3(1.45, 1.45, 1.45)
        root.addChildNode(tower)
        let light = lantern(); light.position = SCNVector3(-1.25, 0, 0.75)
        root.addChildNode(light)
        root.addChildNode(mapleTree())
        return root
    }

    static func torii() -> SCNNode {
        let gate = SCNNode()
        for x: Float in [-0.6, 0.6] {
            let pillar = SCNCone(topRadius: 0.06, bottomRadius: 0.075, height: 1.7); pillar.radialSegmentCount = 10
            gate.addChildNode(Geometry.node(pillar, vermilion, at: SCNVector3(x, 0.95, 0)))
            let foot = SCNCylinder(radius: 0.095, height: 0.2); foot.radialSegmentCount = 10
            gate.addChildNode(Geometry.node(foot, black, at: SCNVector3(x, 0.1, 0)))
        }
        let nuki = SCNBox(width: 1.6, height: 0.09, length: 0.08, chamferRadius: 0)
        gate.addChildNode(Geometry.node(nuki, vermilion, at: SCNVector3(0, 1.4, 0)))
        let strut = SCNBox(width: 0.09, height: 0.2, length: 0.07, chamferRadius: 0)
        gate.addChildNode(Geometry.node(strut, vermilion, at: SCNVector3(0, 1.54, 0)))
        let shimaki = SCNBox(width: 1.75, height: 0.08, length: 0.11, chamferRadius: 0)
        gate.addChildNode(Geometry.node(shimaki, vermilion, at: SCNVector3(0, 1.68, 0)))
        // The kasagi: a black top beam whose underside rises towards both ends.
        let half: CGFloat = 1.08, profile = UIBezierPath()
        let samples = 12
        for i in 0...samples {
            let x = -half + 2 * half * CGFloat(i) / CGFloat(samples)
            let y = 0.14 * pow(abs(x) / half, 2.4)
            if i == 0 { profile.move(to: CGPoint(x: x, y: y)) } else { profile.addLine(to: CGPoint(x: x, y: y)) }
        }
        for i in stride(from: samples, through: 0, by: -1) {
            let x = -half + 2 * half * CGFloat(i) / CGFloat(samples)
            profile.addLine(to: CGPoint(x: x, y: 0.11 + 0.17 * pow(abs(x) / half, 2.4)))
        }
        profile.close()
        let kasagi = SCNShape(path: profile, extrusionDepth: 0.15)
        kasagi.chamferRadius = 0
        gate.addChildNode(Geometry.node(kasagi, black, at: SCNVector3(0, 1.72, 0)))
        return gate
    }

    static func pagoda() -> SCNNode {
        let tower = SCNNode()
        let plinth = SCNBox(width: 0.6, height: 0.1, length: 0.6, chamferRadius: 0)
        tower.addChildNode(Geometry.node(plinth, Geometry.rgb(0.7, 0.67, 0.6), at: SCNVector3(0, 0.05, 0)))
        var y: Float = 0.1
        for tier in 0..<3 {
            let width = CGFloat(0.42 - 0.08 * Double(tier)), height: CGFloat = 0.24
            let body = SCNBox(width: width, height: height, length: width, chamferRadius: 0)
            tower.addChildNode(Geometry.node(body, tier == 0 ? vermilion : vermilion.darker(0.08), at: SCNVector3(0, y + Float(height) / 2, 0)))
            let band = SCNBox(width: width * 0.7, height: height * 0.45, length: width + 0.005, chamferRadius: 0)
            tower.addChildNode(Geometry.node(band, Geometry.rgb(0.95, 0.9, 0.8), at: SCNVector3(0, y + Float(height) / 2, 0)))
            y += Float(height)
            let cap = Geometry.curvedRoof(sides: 4, eave: Float(width) * 1.05, apex: 0.03, height: 0.13, lift: 0.07,
                                          top: roof, under: vermilion.darker(0.3), rotation: .pi / 4)
            cap.position = SCNVector3(0, y, 0)
            tower.addChildNode(cap)
            y += 0.1
        }
        let spire = SCNCylinder(radius: 0.015, height: 0.42); spire.radialSegmentCount = 6
        tower.addChildNode(Geometry.node(spire, Geometry.rgb(0.8, 0.62, 0.25), at: SCNVector3(0, y + 0.21, 0)))
        for i in 0..<4 {
            let ring = SCNCylinder(radius: 0.04, height: 0.015); ring.radialSegmentCount = 8
            tower.addChildNode(Geometry.node(ring, Geometry.rgb(0.85, 0.66, 0.28), at: SCNVector3(0, y + 0.1 + Float(i) * 0.075, 0)))
        }
        return tower
    }

    /// A stone lantern of the kind that lines a shrine approach, with a warm light inside.
    static func lantern() -> SCNNode {
        let lantern = SCNNode()
        let stone = Geometry.rgb(0.62, 0.6, 0.56)
        let post = SCNCylinder(radius: 0.045, height: 0.36); post.radialSegmentCount = 6
        lantern.addChildNode(Geometry.node(post, stone, at: SCNVector3(0, 0.18, 0)))
        let box = SCNBox(width: 0.16, height: 0.13, length: 0.16, chamferRadius: 0)
        lantern.addChildNode(Geometry.node(box, Geometry.rgb(1, 0.78, 0.45), at: SCNVector3(0, 0.43, 0)))
        let cap = SCNPyramid(width: 0.26, height: 0.1, length: 0.26)
        lantern.addChildNode(Geometry.node(cap, stone.darker(0.1), at: SCNVector3(0, 0.495, 0)))
        let knob = SCNSphere(radius: 0.025); knob.segmentCount = 8
        lantern.addChildNode(Geometry.node(knob, stone.darker(0.1), at: SCNVector3(0, 0.61, 0)))
        // Lit from within, so the light box glows rather than shading like stone.
        lantern.childNodes[1].geometry?.firstMaterial?.emission.contents = UIColor(red: 1, green: 0.7, blue: 0.35, alpha: 1)
        return lantern
    }

    static func mapleTree() -> SCNNode {
        let tree = SCNNode()
        let bark = Geometry.rgb(0.28, 0.2, 0.17)
        tree.addChildNode(Geometry.limb(from: SCNVector3(1.45, 0, -1.05), to: SCNVector3(1.4, 0.9, -1.05), radius: 0.06, color: bark))
        let clusters: [(SCNVector3, CGFloat)] = [
            (SCNVector3(1.4, 1.25, -1.05), 0.36), (SCNVector3(1.12, 1.1, -0.95), 0.26),
            (SCNVector3(1.65, 1.15, -1.1), 0.27), (SCNVector3(1.45, 1.5, -1.15), 0.24)
        ]
        for (index, (position, radius)) in clusters.enumerated() {
            let crown = SCNSphere(radius: radius); crown.segmentCount = 9
            tree.addChildNode(Geometry.node(crown, maple[index % maple.count], at: position))
        }
        return tree
    }

    static func leaves() -> [(SCNParticleSystem, SCNNode)] {
        let emitter = SCNNode(); emitter.position = canopyCentre
        return [(Geometry.drift(color: Geometry.rgb(0.95, 0.38, 0.14), rate: 2.2, shape: SCNSphere(radius: 0.35)), emitter)]
    }
}
