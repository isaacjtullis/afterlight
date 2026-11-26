import SpriteKit
import AfterlightCore

/// Renders the game: terrain chunks, props, Max, light and dust. Game logic lives in AfterlightCore.
final class GameScene: SKScene {
    weak var model: GameModel?
    private(set) var game: Game

    // camera state, in tiles
    private let cam = SKCameraNode()
    private var camX = 23.5, camY = 28.4, zoom = 1.2, look = 0.5, shake = 0.0, kickX = 0.0, kickY = 0.0
    private(set) var S: CGFloat = 30        // points per tile at zoom 1
    private var sc: CGFloat { S * CGFloat(zoom) }

    private var chunks: [Int: SKSpriteNode] = [:]
    private var propNodes: [String: (node: SKSpriteNode, key: String)] = [:]
    private var climbNode = SKShapeNode()
    private var climbKey = ""
    private let maxNode = SKSpriteNode()
    private let odiNode = SKSpriteNode()
    private let maraNode = SKSpriteNode()
    private let waterNode = SKShapeNode()
    private let darkNode = SKSpriteNode()
    private let skyNode = SKSpriteNode()
    private var layerNodes: [(TerrainArt.Layer, SKSpriteNode)] = []
    private let sunNode = SKSpriteNode(texture: Art.radial)
    private var rayNodes: [SKShapeNode] = []
    private let beamNode = SKShapeNode()
    private let candleGlow = SKSpriteNode(texture: Art.radial)
    private var lampGlows: [SKSpriteNode] = []
    private let glintNode = SKSpriteNode(texture: Art.star)
    private var dropNodes: [SKSpriteNode] = []
    private let planNode = SKNode()
    private let markerNode = SKSpriteNode(texture: Art.radial)
    private var lanternK = 1.0
    private let guideNode = SKShapeNode()
    private let bubble = SKShapeNode()
    private let bubbleLabel = SKLabelNode(fontNamed: "AvenirNext-MediumItalic")
    private var bubbleText = ""

    private struct Clod { var x, y, vx, vy, life, max, size: Double; var node: SKSpriteNode; var spark: Bool }
    private struct Mote { var x, y, vx, vy, life, max, a, size, p: Double; var node: SKSpriteNode; var glowColor: UIColor? }
    private struct Puff { var x, y, r, vr, life, max, a: Double; var node: SKSpriteNode }
    private var clods: [Clod] = []
    private var motes: [Mote] = []
    private var puffs: [Puff] = []
    private var scarf: [(x: Double, y: Double, px: Double, py: Double)] = []
    private var lastTime: TimeInterval = 0

    private var planTarget: Int? = nil
    /// CI smoke test: trace the first few game frames step by step.
    static let profiling = ProcessInfo.processInfo.arguments.contains("-smoketest")
    static var profiledFrames = 0

    init(game: Game, size: CGSize) {
        self.game = game
        super.init(size: size)
        scaleMode = .resizeFill
        backgroundColor = UIColor(red: 0.08, green: 0.04, blue: 0.06, alpha: 1)
        anchorPoint = CGPoint(x: 0.5, y: 0.5)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func didMove(to view: SKView) {
        view.ignoresSiblingOrder = true
        camera = cam
        addChild(cam)
        layout()
        skyNode.zPosition = -100; cam.addChild(skyNode)
        for l in TerrainArt.parallaxLayers() {
            let n = SKSpriteNode(texture: SKTexture(cgImage: l.image))
            n.anchorPoint = CGPoint(x: 0, y: 1); n.zPosition = -90 + CGFloat(layerNodes.count)
            cam.addChild(n); layerNodes.append((l, n))
        }
        sunNode.blendMode = .add; sunNode.zPosition = -95; sunNode.color = UIColor(red: 1, green: 0.88, blue: 0.7, alpha: 1); sunNode.colorBlendFactor = 1
        cam.addChild(sunNode)
        for i in 0..<6 {
            let r = SKShapeNode(); r.blendMode = .add; r.zPosition = -94; r.strokeColor = .clear
            r.fillColor = UIColor(red: 1, green: 0.86, blue: 0.7, alpha: 0.02 + 0.008 * CGFloat(i % 3)); cam.addChild(r); rayNodes.append(r)
        }
        darkNode.zPosition = 50; darkNode.anchorPoint = CGPoint(x: 0.5, y: 0.5); cam.addChild(darkNode)
        maxNode.zPosition = 25; addChild(maxNode)
        odiNode.zPosition = 24; addChild(odiNode)
        maraNode.zPosition = 24; addChild(maraNode)
        waterNode.zPosition = 45; waterNode.lineWidth = 0; addChild(waterNode)
        climbNode.zPosition = 15; addChild(climbNode)
        beamNode.zPosition = 60; beamNode.blendMode = .add; beamNode.strokeColor = .clear; addChild(beamNode)
        candleGlow.zPosition = 61; candleGlow.blendMode = .add; candleGlow.color = UIColor(red: 1, green: 0.63, blue: 0.27, alpha: 1); candleGlow.colorBlendFactor = 1; addChild(candleGlow)
        glintNode.zPosition = 62; glintNode.blendMode = .add; addChild(glintNode)
        planNode.zPosition = 70; addChild(planNode)
        markerNode.zPosition = 63; markerNode.blendMode = .add; markerNode.color = UIColor(red: 1, green: 0.85, blue: 0.6, alpha: 1); markerNode.colorBlendFactor = 1; addChild(markerNode)
        bubble.zPosition = 90; bubble.fillColor = UIColor(red: 0.04, green: 0.03, blue: 0.06, alpha: 0.72)
        bubble.strokeColor = UIColor(red: 1, green: 0.75, blue: 0.47, alpha: 0.22); bubble.lineWidth = 1
        bubbleLabel.fontSize = 15; bubbleLabel.fontColor = UIColor(red: 0.96, green: 0.86, blue: 0.71, alpha: 1)
        bubbleLabel.numberOfLines = 0; bubbleLabel.preferredMaxLayoutWidth = 260
        bubbleLabel.verticalAlignmentMode = .center; bubbleLabel.horizontalAlignmentMode = .center
        bubble.addChild(bubbleLabel); cam.addChild(bubble)
        let chev = CGMutablePath()
        chev.move(to: CGPoint(x: -7, y: 9)); chev.addLine(to: CGPoint(x: 6, y: 0)); chev.addLine(to: CGPoint(x: -7, y: -9))
        guideNode.path = chev; guideNode.lineWidth = 3.5; guideNode.lineCap = .round; guideNode.lineJoin = .round
        guideNode.strokeColor = UIColor(red: 1, green: 0.82, blue: 0.55, alpha: 1); guideNode.fillColor = .clear
        guideNode.glowWidth = 3; guideNode.zPosition = 89; guideNode.isHidden = true; cam.addChild(guideNode)
        buildDecals()
        resetScarf()
        camX = game.max.pos.x + 0.5; camY = game.max.pos.y - 1.4
    }

    override func didChangeSize(_ oldSize: CGSize) { layout() }

    private func layout() {
        // Portrait phones: about 8 tiles across so Max and his room fill the frame. Landscape keeps the wide view.
        S = size.height > size.width ? max(30, min(64, size.width / 8)) : max(22, min(46, min(size.width / 11.5, size.height / 10.5)))
        for n in chunks.values { n.removeFromParent() }
        chunks.removeAll()
        for n in propNodes.values { n.node.removeFromParent() }
        propNodes.removeAll()
        game.world.markAllDirty()
        skyNode.size = size
        let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [TerrainArt.color(0x0e0a0d), TerrainArt.color(0x2a1d26), TerrainArt.color(0x6a4a48), TerrainArt.color(0x3a2830), TerrainArt.color(0x120d10)] as CFArray, locations: [0, 0.42, 0.6, 0.74, 1])!
        if let ctx = CGContext(data: nil, width: 4, height: 256, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: 256), end: CGPoint(x: 0, y: 0), options: [])
            if let img = ctx.makeImage() { skyNode.texture = SKTexture(cgImage: img) }
        }
        children.compactMap { $0 as? SKLabelNode }.forEach { $0.removeFromParent() }
        if view != nil { buildDecals() }
    }

    func reset(_ g: Game) {
        game = g
        layout()
        resetScarf()
        camX = g.max.pos.x; camY = g.max.pos.y - 1.4
    }

    func terrainChanged() { game.world.markAllDirty() }

    private func sp(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: CGFloat(x) * S, y: -CGFloat(y) * S) }

    func worldX(fromScreenX x: CGFloat) -> Double { camX + Double((x - size.width / 2) / sc) }
    /// Where a world point sits on screen, in SwiftUI's top-left coordinates.
    func viewPoint(_ p: V2) -> CGPoint {
        CGPoint(x: size.width / 2 + CGFloat(p.x - camX) * sc, y: size.height / 2 + CGFloat(p.y - camY) * sc)
    }

    // MARK: frame

    nonisolated(unsafe) static var updateCalls = 0
    nonisolated(unsafe) static var updateDone = 0
    nonisolated(unsafe) static var lastStep = ""
    nonisolated(unsafe) static var onMain = true

    override func update(_ currentTime: TimeInterval) {
        GameScene.updateCalls += 1
        GameScene.onMain = Thread.isMainThread
        defer { GameScene.updateDone += 1 }
        let dt = lastTime == 0 ? 1.0 / 60 : min(1.0 / 20, currentTime - lastTime)
        lastTime = currentTime
        var target: Int? = nil
        var latest: Game? = nil
        MainActor.assumeIsolated {
            model?.tick(dt)
            target = model?.planTarget
            latest = model?.game
        }
        planTarget = target
        if let latest, latest !== game { reset(latest) }
        let steps: [(String, () -> Void)] = [
            ("camera", { self.updateCamera(dt) }), ("chunks", updateChunks), ("props", updateProps), ("climbs", updateClimbs),
            ("parallax", updateParallax), ("scarf", { self.updateScarf(dt) }), ("actors", drawActors), ("particles", { self.updateParticles(dt) }),
            ("lights", updateLights), ("plan", updatePlan), ("bubble", updateBubble), ("marker", updateMarker), ("guide", updateGuide),
        ]
        for (name, f) in steps {
            if GameScene.profiling {
                let t0 = CACurrentMediaTime()
                GameScene.lastStep = name
                f()
                let ms = (CACurrentMediaTime() - t0) * 1000
                if ms > 30 { print("FRAME slow \(name) \(Int(ms))ms"); fflush(stdout) }
            } else { f() }
        }

    }

    // MARK: camera

    private func updateCamera(_ dt: Double) {
        let m = game.max
        var z = 1.2
        if m.pos.x > 32.3 || m.pos.y > 30.6 { z = 1.0 }
        if m.pos.y < 10 { z = 1.05 }
        if game.story.flags.contains("broke") && m.pos.x > Double(Landmarks.caveStart) - 1 && m.pos.y > 12 {
            z = 0.72 - clampD((abs(m.vx) - 3) * 0.035, 0, 0.17)
        }
        if let p = game.planning {
            let end = Double(planTarget ?? p.reach)
            let span = abs(max(end, Double(p.reach), m.pos.x) - min(m.pos.x, Double(p.face), end)) + 4
            z = clampD(Double(size.width) / (span * Double(S)), 0.42, 0.85)
        }
        if let c = game.cine, c.t > 2.4 { z = 0.92 }
        zoom = damp(zoom, z, 1.4, dt)
        look = damp(look, (abs(m.vx) > 0.3 ? m.vx * 0.45 + Double(m.face) * 0.3 : Double(m.face) * 0.8) + ((game.cine?.t ?? 9) < 2.4 ? 2.5 : 0), 1.5, dt)
        let portrait = size.height > size.width
        var tx = m.pos.x + look * (portrait ? 0.45 : 1), ty = m.pos.y - (portrait ? 0.9 : 1.4) - m.lookUp * 3.2
        if game.story.flags.contains("broke") && m.pos.x > Double(Landmarks.caveStart) - 1 && m.pos.y > 12 { ty -= 3 }
        if let p = game.planning { tx = (m.pos.x + Double(planTarget ?? p.reach)) / 2 }
        if let c = game.cine, let f = c.focus { tx = lerpD(tx, f.x, c.focusWeight); ty = lerpD(ty, f.y, c.focusWeight) }
        if let j = game.activeJob, let s = j.plan.steps.first { tx = s.endPos.x; ty = s.endPos.y - 1.4 }
        let rate = game.cine != nil ? 1.6 : 3.0
        camX = damp(camX, tx, rate, dt); camY = damp(camY, ty, rate * 0.87, dt)
        shake = damp(shake, 0, 9, dt); kickX = damp(kickX, 0, 10, dt); kickY = damp(kickY, 0, 10, dt)
        let jx = Double.random(in: -1...1) * shake, jy = Double.random(in: -1...1) * shake
        cam.position = sp(camX + kickX + jx, camY + kickY + jy)
        cam.setScale(1 / CGFloat(zoom))
    }

    // MARK: terrain

    private func visibleTileRect(margin: Double = 2) -> (Int, Int, Int, Int) {
        let hw = Double(size.width / sc) / 2 + margin, hh = Double(size.height / sc) / 2 + margin
        return (Int((camX - hw).rounded(.down)), Int((camY - hh).rounded(.down)), Int((camX + hw).rounded(.up)), Int((camY + hh).rounded(.up)))
    }

    private func updateChunks() {
        let w = game.world
        let n = World.chunk
        let (x0, y0, x1, y1) = visibleTileRect(margin: 4)
        let cx0 = max(0, x0 / n), cx1 = min(w.chunksX - 1, x1 / n), cy0 = max(0, y0 / n), cy1 = min(w.chunksY - 1, y1 / n)
        var budget = 6
        if cx0 <= cx1 && cy0 <= cy1 {
            for cy in cy0...cy1 {
                for cx in cx0...cx1 {
                    let idx = cy * w.chunksX + cx
                    let exists = chunks[idx] != nil
                    guard !exists || w.dirtyChunks.contains(idx), budget > 0 else { continue }
                    budget -= 1
                    w.dirtyChunks.remove(idx)
                    guard let img = TerrainArt.render(world: w, cx: cx, cy: cy) else { continue }
                    let node = chunks[idx] ?? SKSpriteNode()
                    node.texture = SKTexture(cgImage: img)
                    node.size = CGSize(width: CGFloat(n) * S, height: CGFloat(n) * S)
                    node.anchorPoint = CGPoint(x: 0, y: 1)
                    node.position = sp(Double(cx * n), Double(cy * n))
                    node.zPosition = 10
                    if !exists { addChild(node); chunks[idx] = node }
                }
            }
        }
        // drop far-away chunks to keep memory low
        for (idx, node) in chunks {
            let cx = idx % w.chunksX, cy = idx / w.chunksX
            if cx < cx0 - 3 || cx > cx1 + 3 || cy < cy0 - 3 || cy > cy1 + 3 { node.removeFromParent(); chunks[idx] = nil }
        }
    }

    private func buildDecals() {
        for d in game.world.decals {
            let l = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
            l.text = d.text
            l.fontSize = CGFloat(d.size) * S
            l.fontColor = UIColor(red: 0.85, green: 0.7, blue: 0.5, alpha: 0.42)
            l.horizontalAlignmentMode = d.vertical ? .center : .left
            l.verticalAlignmentMode = .baseline
            l.position = sp(d.pos.x, d.pos.y)
            if d.vertical { l.zRotation = .pi / 2 }
            l.zPosition = 12
            addChild(l)
        }
    }

    // MARK: props

    private func updateProps() {
        let g = game
        var alive = Set<String>()
        let (x0, y0, x1, y1) = visibleTileRect(margin: 8)
        for p0 in g.world.props {
            guard p0.pos.x > Double(x0) - 40, p0.pos.x < Double(x1) + 8, p0.pos.y > Double(y0) - 8, p0.pos.y < Double(y1) + 8 else { continue }
            var p = p0
            if p.kind == .workbench && !g.inv.has(.flashlight) { p.flags.insert("flashlight") }
            if p.kind == .pump && g.story.flags.contains("pumpFixed") { p.flags.insert("fixed") }
            if p.kind == .maraTap && g.story.coop.water.outpostTapFlow > 0 { p.flags.insert("flowing") }
            let crop = p.kind == .planter ? (p.planted == nil ? 0 : max(0.08, g.cropProgress(p))) : 0
            let key = "\(p.kind.rawValue)|\(p.stock.isEmpty)|\(p.flags.sorted().joined())|\(Int(crop * 10))|\(g.story.flags.contains("power"))|\(S)"
            alive.insert(p.id)
            if let e = propNodes[p.id], e.key == key { continue }
            let (bx, by, bw, bh) = Art.bounds(p.kind)
            let powered = g.story.flags.contains("power")
            guard let img = Art.image(widthTiles: bw, heightTiles: bh, ppt: min(80, S * 2), originX: -bx, originY: -by, { ctx in
                Art.drawProp(ctx, p, crop: crop, powered: powered)
            }) else { continue }
            let node = propNodes[p.id]?.node ?? SKSpriteNode()
            node.texture = SKTexture(cgImage: img)
            node.size = CGSize(width: bw * S, height: bh * S)
            node.anchorPoint = CGPoint(x: -bx / bw, y: 1 + by / bh)
            node.position = sp(p.pos.x, p.pos.y)
            node.zPosition = p.kind == .warmPipe ? 11 : 20
            if node.parent == nil { addChild(node) }
            propNodes[p.id] = (node, key)
        }
        for (id, e) in propNodes where !alive.contains(id) { e.node.removeFromParent(); propNodes[id] = nil }
    }

    private func updateClimbs() {
        let cl = game.world.climbs
        let key = cl.map { "\($0.id)\($0.top)" }.joined() + "\(S)"
        guard key != climbKey else { return }
        climbKey = key
        let path = CGMutablePath()
        for c in cl {
            switch c.kind {
            case .rungs, .ladder:
                let top = c.kind == .rungs ? c.top + 0.4 : c.top
                if c.kind == .ladder {
                    path.move(to: sp(c.x - 0.55, c.bottom)); path.addLine(to: sp(c.x - 0.55, top))
                    path.move(to: sp(c.x + 0.55, c.bottom)); path.addLine(to: sp(c.x + 0.55, top))
                }
                var y = c.bottom - 0.4
                while y > top { path.move(to: sp(c.x - 0.7, y)); path.addLine(to: sp(c.x + 0.7, y)); y -= 0.7 }
            case .rope:
                path.move(to: sp(c.x, c.top - 0.2)); path.addLine(to: sp(c.x + 0.05, c.bottom))
                var y = c.bottom - 0.6
                while y > c.top { path.move(to: sp(c.x - 0.12, y)); path.addLine(to: sp(c.x + 0.14, y)); y -= 0.9 }
            case .foothold:
                // Notches cut into whichever side the earth is on.
                let d: Double = game.world.solid(c.x + 0.5, c.bottom - 0.6) ? 1 : -1
                var y = c.bottom - 0.45
                var k = 0
                while y > c.top - 0.1 {
                    let wx = c.x + d * (k % 2 == 0 ? 0.55 : 0.66)
                    path.move(to: sp(wx, y)); path.addLine(to: sp(wx + d * 0.22, y - 0.08))
                    y -= 0.5; k += 1
                }
            }
        }
        climbNode.path = path
        climbNode.strokeColor = UIColor(red: 0.42, green: 0.36, blue: 0.3, alpha: 1)
        climbNode.lineWidth = max(1.5, S * 0.08)
        climbNode.lineCap = .round
    }

    // MARK: parallax

    private func updateParallax() {
        let show = camX > Double(Landmarks.caveStart) - 14
        skyNode.isHidden = !show; sunNode.isHidden = !show
        layerNodes.forEach { $0.1.isHidden = !show }
        rayNodes.forEach { $0.isHidden = !show }
        guard show else { return }
        let W = size.width, H = size.height
        func screen(_ lx: Double, _ ly: Double, _ f: Double, _ k: Double) -> CGPoint {
            // camera space: origin at screen center, y up
            let ax = TerrainArt.parallaxAnchorX
            let x = CGFloat(((lx - ax) - (camX - ax) * f) * k) * sc
            let y = CGFloat(((ly - 25) - (camY - 25) * f) * k) * sc
            return CGPoint(x: x, y: -y)
        }
        for (l, n) in layerNodes {
            let p = screen(Double(l.origin.x), Double(l.origin.y), l.f, l.k)
            n.position = p
            n.size = CGSize(width: CGFloat(l.image.width) / l.pxPerUnit * CGFloat(l.k) * sc, height: CGFloat(l.image.height) / l.pxPerUnit * CGFloat(l.k) * sc)
        }
        // Not a sun: a far-off crack of light high in the cavern wall.
        let sun = screen(150, 18, 0.18, 0.55)
        sunNode.position = sun
        let R = max(W, H) * 1.9
        sunNode.size = CGSize(width: R, height: R)
        sunNode.alpha = 0.5
        let t = game.time
        for (i, r) in rayNodes.enumerated() {
            let a = CGFloat(-Double.pi / 2 + Double(i - 3) * 0.3 + sin(t * 0.13 + Double(i) * 1.7) * 0.05)
            let wv: CGFloat = 0.045 + 0.025 * CGFloat(sin(Double(i) * 2.3))
            let L = max(W, H) * 1.5
            let p = CGMutablePath()
            p.move(to: sun)
            p.addLine(to: CGPoint(x: sun.x + cos(a - wv) * L, y: sun.y + sin(a - wv) * L))
            p.addLine(to: CGPoint(x: sun.x + cos(a + wv) * L, y: sun.y + sin(a + wv) * L))
            p.closeSubpath()
            r.path = p
        }
        _ = H
    }

    // MARK: actors

    private func bodyPt(_ lx: Double, _ ly: Double, _ m: Max) -> (Double, Double) {
        let a = m.lean + m.tilt, c = cos(a), s = sin(a)
        return (m.pos.x + m.visOff.x + Double(m.face) * (lx * c - ly * s), m.pos.y + m.visOff.y + lx * s + ly * c)
    }

    private func resetScarf() {
        let p = game.max.pos
        var pts: [(x: Double, y: Double, px: Double, py: Double)] = []
        for i in 0..<9 {
            let x: Double = p.x - Double(i) * 0.1
            let y: Double = p.y - 1.1
            pts.append((x: x, y: y, px: x, py: y))
        }
        scarf = pts
    }

    private func updateScarf(_ dt: Double) {
        let m = game.max
        let (nx, ny) = bodyPt(-0.05, -1.1 + m.crouch + m.bob, m)
        if abs(nx - scarf[0].x) > 3 || abs(ny - scarf[0].y) > 3 { resetScarf() }
        scarf[0] = (x: nx, y: ny, px: nx, py: ny)
        let sp = abs(m.vx), wind = (game.story.flags.contains("broke") && m.pos.x > Double(Landmarks.caveStart)) ? -1.4 : 0
        let t = game.time
        for i in 1..<scarf.count {
            var q = scarf[i]
            let vx = (q.x - q.px) * 0.95, vy = (q.y - q.py) * 0.95
            q.px = q.x; q.py = q.y
            let ax = -m.vx * 4.5 + wind + sin(t * (6 + sp) + Double(i) * 0.9) * (1.4 + sp * 1.5)
            let ay = 5 + cos(t * 5 + Double(i)) * (0.5 + sp * 0.8) - (sp > 4 ? sp * 0.7 : 0)
            q.x += vx + ax * dt * dt; q.y += vy + ay * dt * dt
            scarf[i] = q
        }
        let L = 0.11
        for _ in 0..<4 {
            for i in 1..<scarf.count {
                let a = scarf[i - 1], b = scarf[i]
                let dx = b.x - a.x, dy = b.y - a.y, d = max(1e-4, (dx * dx + dy * dy).squareRoot()), df = (d - L) / d
                if i == 1 { scarf[i].x -= dx * df; scarf[i].y -= dy * df }
                else {
                    scarf[i - 1].x += dx * df * 0.5; scarf[i - 1].y += dy * df * 0.5
                    scarf[i].x -= dx * df * 0.5; scarf[i].y -= dy * df * 0.5
                }
            }
        }
    }

    private func drawActors() {
        let g = game
        var m = g.max
        if let j = g.activeJob {
            // Max is out on the job: show him working at the current step.
            let done = JobResolver.completedSteps(j.plan, elapsed: Date().timeIntervalSince(j.startedAt))
            let step = j.plan.steps[min(done, j.plan.steps.count - 1)]
            m.pos = step.endPos
            m.swingOn = j.plan.kind == .dig
            m.swing = (g.time / 0.5).truncatingRemainder(dividingBy: 1)
            m.shovel = m.swingOn ? -2.3 + sin(g.time * 12) * 1.2 : -2.2
        }
        lanternK = damp(lanternK, g.lanternOut ? g.candle : 0, 6, 1.0 / 60)
        let backView = m.mode == .climb && (g.world.climbs.first { $0.id == m.climbID }.map { $0.kind == .ladder || $0.kind == .rungs } ?? false)
        let ppt = min(90, S * 2.2)
        let ox = 2.6, oy = 3.4
        let flick = g.flicker * 0.35 * sin(g.time * 31) + 0.05 * sin(g.time * 13)
        let (hx, hy) = bodyPt(-0.3, -1.1 + m.crouch, m)
        let lampX = hx + sin(m.lant) * 0.3, lampY = hy + cos(m.lant) * 0.3
        let scarfPts = scarf.map { CGPoint(x: $0.x - m.pos.x, y: $0.y - m.pos.y) }
        let img = Art.image(widthTiles: 5.2, heightTiles: 4.6, ppt: ppt, originX: CGFloat(ox), originY: CGFloat(oy)) { ctx in
            ActorArt.drawScarf(ctx, scarfPts)
            ActorArt.drawMax(ctx, m, time: g.time, flashlight: g.inv.has(.flashlight), flashOn: g.story.flags.contains("flashOn"), carrying: g.inv.count(.chargeCrystal) > 0, wood: g.inv.wood, back: backView)
            if lanternK > 0.02 {
                ActorArt.drawLantern(ctx, hook: CGPoint(x: hx - m.pos.x, y: hy - m.pos.y), lamp: CGPoint(x: lampX - m.pos.x, y: lampY - m.pos.y), swing: m.lant, flicker: flick)
            }
        }
        if let img { maxNode.texture = SKTexture(cgImage: img) }
        maxNode.size = CGSize(width: 5.2 * S, height: 4.6 * S)
        maxNode.anchorPoint = CGPoint(x: ox / 5.2, y: 1 - oy / 4.6)
        maxNode.position = sp(m.pos.x + m.visOff.x, m.pos.y + m.visOff.y)
        maxNode.isHidden = !g.started

        // Mara
        let (vx0, _, vx1, _) = visibleTileRect(margin: 3)
        let mr = g.mara
        if g.story.chapter >= 3 && mr.pos.x > Double(vx0) && mr.pos.x < Double(vx1) {
            maraNode.isHidden = false
            let working = g.activeJobID(for: "mara").flatMap { g.job($0) }?.status == .working && !mr.walking
            if let img = Art.image(widthTiles: 1.8, heightTiles: 2.0, ppt: ppt, originX: 0.9, originY: 1.9, { ctx in
                ActorArt.drawMara(ctx, face: mr.face, walking: mr.walking, working: working, time: g.time)
            }) { maraNode.texture = SKTexture(cgImage: img) }
            maraNode.size = CGSize(width: 1.8 * S, height: 2.0 * S)
            maraNode.anchorPoint = CGPoint(x: 0.5, y: 1 - 1.9 / 2.0)
            maraNode.position = sp(mr.pos.x, mr.pos.y)
        } else {
            maraNode.isHidden = true
        }
        // Cold water in the sump, and the line out of it while the pump runs.
        let wp = CGMutablePath()
        wp.addRect(CGRect(origin: sp(80, 14), size: CGSize(width: 7 * S, height: 1.7 * S)))
        waterNode.path = wp
        waterNode.fillColor = UIColor(red: 0.3, green: 0.55, blue: 0.68, alpha: 0.38 + 0.04 * CGFloat(sin(g.time * 1.7)))

        // Odi (a later chapter)
        let o = g.odi
        if g.story.chapter >= 5 && o.pos.x > Double(vx0) && o.pos.x < Double(vx1) {
            odiNode.isHidden = false
            if let img = Art.image(widthTiles: 1.6, heightTiles: 2.0, ppt: ppt, originX: 0.8, originY: 1.9, { ctx in
                ActorArt.drawOdi(ctx, face: o.face, walking: o.walking, time: g.time)
            }) { odiNode.texture = SKTexture(cgImage: img) }
            odiNode.size = CGSize(width: 1.6 * S, height: 2.0 * S)
            odiNode.anchorPoint = CGPoint(x: 0.5, y: 1 - 1.9 / 2.0)
            odiNode.position = sp(o.pos.x, o.pos.y)
        } else {
            odiNode.isHidden = true
        }

        // loose finds waiting to be picked up
        while dropNodes.count < g.drops.count {
            let n = SKSpriteNode(texture: Art.star); n.blendMode = .add; n.zPosition = 62; addChild(n); dropNodes.append(n)
        }
        for (i, n) in dropNodes.enumerated() {
            if i < g.drops.count {
                let d = g.drops[i]
                n.isHidden = false
                n.position = sp(d.pos.x, d.pos.y)
                let tw = 0.8 + 0.4 * sin(g.time * 5)
                n.size = CGSize(width: 0.7 * S * CGFloat(tw), height: 0.7 * S * CGFloat(tw))
                n.zRotation = CGFloat(g.time * 0.6)
            } else { n.isHidden = true }
        }
    }

    // MARK: particles

    private func sprite(_ tex: SKTexture, z: CGFloat, add: Bool) -> SKSpriteNode {
        let n = SKSpriteNode(texture: tex)
        n.zPosition = z
        if add { n.blendMode = .add }
        n.colorBlendFactor = 1
        addChild(n)
        return n
    }

    func burst(at p: V2, kind: SwingKind, carved: Bool, face: Int) {
        let colors: [UIColor] = [UIColor(red: 0.65, green: 0.48, blue: 0.35, alpha: 1), UIColor(red: 0.54, green: 0.38, blue: 0.28, alpha: 1),
                                 UIColor(red: 0.77, green: 0.59, blue: 0.43, alpha: 1), UIColor(red: 0.45, green: 0.31, blue: 0.24, alpha: 1)]
        let n = carved ? 13 : 5
        for _ in 0..<n {
            let s = Double.random(in: 0.05...0.13)
            let node = sprite(Art.circle, z: 26, add: false)
            node.color = colors.randomElement()!
            let side = kind == .side
            clods.append(Clod(x: p.x + Double.random(in: -0.3...0.3), y: p.y + Double.random(in: -0.3...0.3),
                              vx: (side ? -Double(face) * Double.random(in: 0.8...3.4) : Double.random(in: -2.4...2.4)) + Double.random(in: -0.6...0.6),
                              vy: -Double.random(in: side ? 1.5...5 : 3.5...7.5), life: Double.random(in: 0.9...1.8), max: 1.8, size: s, node: node, spark: false))
        }
        for _ in 0..<(carved ? 9 : 3) { addMote(x: p.x + Double.random(in: -0.4...0.4), y: p.y + Double.random(in: -0.4...0.4), vx: kind == .side ? -Double(face) * 0.5 : 0) }
        if carved { addPuff(p.x - Double(face) * 0.2, p.y, 0.3) }
        shake = 0.022
        if kind == .side { kickX += Double(face) * 0.04 } else { kickY += 0.05 }
    }

    func sparks(at p: V2) {
        for _ in 0..<8 {
            let node = sprite(Art.circle, z: 64, add: true)
            node.color = Bool.random() ? UIColor(red: 1, green: 0.82, blue: 0.54, alpha: 1) : UIColor(red: 0.84, green: 0.72, blue: 1, alpha: 1)
            clods.append(Clod(x: p.x, y: p.y, vx: Double.random(in: -3...3), vy: -Double.random(in: 1...4), life: 0.4, max: 0.4, size: 0.06, node: node, spark: true))
        }
        shake = 0.03
    }

    func pour(at p: V2) {
        for _ in 0..<26 {
            let node = sprite(Art.circle, z: 26, add: false)
            node.color = UIColor(red: 0.54, green: 0.38, blue: 0.28, alpha: 1)
            clods.append(Clod(x: p.x + Double.random(in: -0.8...0.8), y: p.y, vx: Double.random(in: -0.4...0.4), vy: Double.random(in: 0...1), life: 2, max: 2, size: Double.random(in: 0.05...0.11), node: node, spark: false))
        }
        for _ in 0..<20 { addMote(x: p.x + Double.random(in: -1.2...1.2), y: p.y + 0.8, vx: 0) }
        addPuff(p.x, p.y + 1.4, 0.6)
        shake = 0.06
    }

    func sparkle(at p: V2) { for _ in 0..<12 { addMote(x: p.x + Double.random(in: -0.3...0.3), y: p.y, vx: 0, glow: UIColor(red: 0.8, green: 0.66, blue: 1, alpha: 1)) } }

    func landPuff() { let m = game.max; addPuff(m.pos.x, m.pos.y - 0.1, 0.3); for _ in 0..<8 { addMote(x: m.pos.x, y: m.pos.y - 0.3, vx: m.vx * 0.3) } }

    private func addMote(x: Double, y: Double, vx: Double, glow: UIColor? = nil) {
        guard motes.count < 140 else { return }
        let node = sprite(Art.circle, z: 61, add: true)
        motes.append(Mote(x: x, y: y, vx: vx + Double.random(in: -0.5...0.5), vy: glow != nil ? -Double.random(in: 0.25...0.6) : Double.random(in: -0.5...0.15),
                          life: Double.random(in: 3.5...7), max: 7, a: Double.random(in: 0.35...0.9), size: Double.random(in: 0.025...0.06), p: Double.random(in: 0...6), node: node, glowColor: glow))
    }

    private func addPuff(_ x: Double, _ y: Double, _ r: Double) {
        let node = sprite(Art.radial, z: 61, add: true)
        node.color = UIColor(red: 0.9, green: 0.75, blue: 0.6, alpha: 1)
        puffs.append(Puff(x: x, y: y, r: r, vr: 0.9, life: 1.6, max: 1.6, a: 0.45, node: node))
    }

    private func updateParticles(_ dt: Double) {
        let w = game.world
        for i in clods.indices.reversed() {
            var c = clods[i]
            c.life -= dt
            if c.life <= 0 { c.node.removeFromParent(); clods.remove(at: i); continue }
            c.vy += (c.spark ? 18 : 30) * dt
            var nx = c.x + c.vx * dt, ny = c.y + c.vy * dt
            if w.solid(nx, ny) {
                if !w.solid(c.x, ny) { c.vx *= -0.3; nx = c.x } else { ny = c.vy > 0 ? ny.rounded(.down) - 0.005 : c.y; c.vy *= -0.25; c.vx *= 0.5; if abs(c.vy) < 0.8 { c.vy = 0 } }
            }
            c.x = nx; c.y = ny
            c.node.position = sp(c.x, c.y)
            let sz = CGFloat(c.size) * S * 1.1
            c.node.size = CGSize(width: sz, height: sz)
            c.node.alpha = CGFloat(min(1, c.life / 0.4))
            clods[i] = c
        }
        // ambient dust near Max
        if motes.count < 70 && game.started {
            let a = Double.random(in: 0...6.28), d = Double.random(in: 1...7)
            let x = game.max.pos.x + cos(a) * d, y = game.max.pos.y - 1 + sin(a) * d * 0.6
            if !w.solid(x, y) { addMote(x: x, y: y, vx: 0); motes[motes.count - 1].a = Double.random(in: 0.15...0.45); motes[motes.count - 1].vx = Double.random(in: -0.1...0.1) }
        }
        let t = game.time
        for i in motes.indices.reversed() {
            var m = motes[i]
            m.life -= dt
            if m.life <= 0 || w.solid(m.x, m.y) { m.node.removeFromParent(); motes.remove(at: i); continue }
            m.vx *= pow(0.6, dt); m.vy = m.vy * pow(0.6, dt) + 0.03 * dt
            m.x += (m.vx + sin(t * 0.7 + m.p) * 0.06) * dt
            m.y += (m.vy + cos(t * 0.5 + m.p) * 0.04) * dt
            let L = m.glowColor != nil ? 1 : lightAt(m.x, m.y)
            let a = min(1, m.a * L * min(1, m.life / 1.5, (m.max - m.life) / 0.8 + 0.2))
            m.node.color = m.glowColor ?? UIColor(red: 1, green: 0.87, blue: 0.7, alpha: 1)
            m.node.alpha = CGFloat(a)
            m.node.position = sp(m.x, m.y)
            let sz = CGFloat(m.size) * S
            m.node.size = CGSize(width: sz, height: sz)
            motes[i] = m
        }
        for i in puffs.indices.reversed() {
            var p = puffs[i]
            p.life -= dt; p.r += p.vr * dt; p.vr *= pow(0.4, dt)
            if p.life <= 0 { p.node.removeFromParent(); puffs.remove(at: i); continue }
            p.node.position = sp(p.x, p.y)
            p.node.size = CGSize(width: CGFloat(p.r * 2) * S, height: CGFloat(p.r * 2) * S)
            p.node.alpha = CGFloat(p.a * (p.life / p.max) * 0.3 * min(1, lightAt(p.x, p.y) + 0.05))
            puffs[i] = p
        }
    }

    // MARK: light

    private func lanternPos() -> (Double, Double) {
        let m = game.max
        let (hx, hy) = bodyPt(-0.3, -1.1 + m.crouch, m)
        return (hx + sin(m.lant) * 0.3, hy + cos(m.lant) * 0.3)
    }
    private func flashOrigin() -> (Double, Double) { let m = game.max; return bodyPt(0.2, -0.98 + m.crouch + m.bob, m) }
    private var beamAngle: Double { game.max.face > 0 ? game.max.beamA : .pi - game.max.beamA }

    private func lightAt(_ x: Double, _ y: Double) -> Double {
        var v = 0.0
        let (lx, ly) = lanternPos()
        let R = 4.8 * lanternK
        let d = ((x - lx) * (x - lx) + (y - ly) * (y - ly)).squareRoot()
        if d < R { v += pow(1 - d / R, 1.4) }
        if game.max.flashI > 0 {
            let (fx, fy) = flashOrigin()
            let dx = x - fx, dy = y - fy, dd = (dx * dx + dy * dy).squareRoot()
            if dd < 17 {
                var da = abs(atan2(dy, dx) - beamAngle)
                if da > .pi { da = 2 * .pi - da }
                if da < 0.42 { v += (1 - dd / 17) * (1 - da / 0.42) * 1.6 * game.max.flashI }
            }
        }
        for l in game.world.props where l.kind == .lamp {
            let dd = ((x - l.pos.x) * (x - l.pos.x) + (y - l.pos.y + 1.2) * (y - l.pos.y + 1.2)).squareRoot()
            if dd < 4.5 { v += (1 - dd / 4.5) * 0.8 }
        }
        if game.ambient > 0 && x > Double(Landmarks.caveStart) && y > 12 { v += 0.12 * game.ambient }
        return v
    }

    private func updateLights() {
        let g = game
        let W = size.width, H = size.height
        let lw = Int(W / 4) + 2, lh = Int(H / 4) + 2
        guard let ctx = CGContext(data: nil, width: lw, height: lh, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.setFillColor(TerrainArt.color(0x14090e)); ctx.fill(CGRect(x: 0, y: 0, width: lw, height: lh))
        ctx.translateBy(x: 0, y: CGFloat(lh)); ctx.scaleBy(x: 0.25, y: -0.25)
        ctx.translateBy(x: W / 2 - CGFloat(camX) * sc, y: H / 2 - CGFloat(camY) * sc)
        ctx.scaleBy(x: sc, y: sc)
        ctx.setBlendMode(.destinationOut)
        let space = CGColorSpaceCreateDeviceRGB()
        func light(_ x: Double, _ y: Double, _ R: Double, _ I: Double, rays: [V2]?) {
            guard R > 0.1, I > 0.01 else { return }
            let g = CGGradient(colorsSpace: space, colors: [TerrainArt.color(0, CGFloat(I)), TerrainArt.color(0, CGFloat(I * 0.8)), TerrainArt.color(0, CGFloat(I * 0.32)), TerrainArt.color(0, 0)] as CFArray,
                               locations: [0, 0.35, 0.7, 1])!
            ctx.saveGState()
            if let rays, rays.count > 2 {
                ctx.addLines(between: rays.map { CGPoint(x: $0.x, y: $0.y) }); ctx.closePath(); ctx.clip()
            }
            ctx.drawRadialGradient(g, startCenter: CGPoint(x: x, y: y), startRadius: 0, endCenter: CGPoint(x: x, y: y), endRadius: CGFloat(R), options: [])
            ctx.restoreGState()
        }
        let (lx, ly) = lanternPos()
        let flick = 0.05 * sin(g.time * 13) + 0.035 * sin(g.time * 29 + 1) + g.flicker * 0.35 * sin(g.time * 31)
        let R = 4.9 * (1 + flick) * lanternK
        light(lx, ly, R, 0.98, rays: g.world.castLight(from: V2(lx, ly), radius: R, a0: 0, a1: 2 * .pi, rays: 64))
        var beam: [V2]? = nil
        if g.inv.has(.flashlight) && g.max.flashI > 0 {
            let (fx, fy) = flashOrigin()
            var pts = [V2(fx, fy)]
            pts.append(contentsOf: g.world.castLight(from: V2(fx, fy), radius: 17, a0: beamAngle - 0.33, a1: beamAngle + 0.33, rays: 36))
            beam = pts
            light(fx, fy, 17, 0.95 * g.max.flashI, rays: pts)
            light(fx, fy, 1.8, 0.5 * g.max.flashI, rays: nil)
        }
        let (vx0, vy0, vx1, vy1) = visibleTileRect(margin: 6)
        for l in g.world.props where l.kind == .lamp && l.pos.x > Double(vx0) && l.pos.x < Double(vx1) && l.pos.y > Double(vy0) && l.pos.y < Double(vy1) {
            let o = V2(l.pos.x, l.pos.y - 1.2)
            light(o.x, o.y, 4.8, 0.95, rays: g.world.castLight(from: o, radius: 4.8, a0: 0, a1: 2 * .pi, rays: 40))
        }
        if g.story.flags.contains("power") { light(25.5, 27.6, 8, 0.95, rays: g.world.castLight(from: V2(25.5, 27.6), radius: 8, a0: 0, a1: 2 * .pi, rays: 48)) }
        if abs(g.max.pos.x - 80) < 30 && g.max.pos.y < 14 { light(80.5, 7, 7, 0.95, rays: g.world.castLight(from: V2(80.5, 7), radius: 7, a0: 0, a1: 2 * .pi, rays: 48)) }
        if g.odi.walking { light(g.odi.pos.x + Double(g.odi.face) * 0.3, g.odi.pos.y - 0.5, 3.6, 0.9, rays: nil) }
        if g.ambient > 0 { light(135, 30, 60, 0.92 * g.ambient, rays: nil) }
        if let b = g.world.buried.first(where: { $0.id == "crystal" && !$0.revealed }), abs(b.pos.x - lx) < 6 { light(b.pos.x, b.pos.y - 0.1, 1.1, 0.35, rays: nil) }
        if let img = ctx.makeImage() {
            darkNode.texture = SKTexture(cgImage: img)
            darkNode.texture?.filteringMode = .linear
        }
        darkNode.size = CGSize(width: CGFloat(lw * 4), height: CGFloat(lh * 4))
        darkNode.position = CGPoint(x: CGFloat(lw * 4) / 2 - W / 2, y: H / 2 - CGFloat(lh * 4) / 2)

        // additive glows above the darkness
        candleGlow.position = sp(lx, ly)
        let gr = 4.8 * (1 + flick) * S
        candleGlow.size = CGSize(width: gr, height: gr)
        candleGlow.alpha = 0.22 * CGFloat(lanternK)
        if let beam {
            let p = CGMutablePath()
            p.addLines(between: beam.map { sp($0.x, $0.y) }); p.closeSubpath()
            beamNode.path = p
            beamNode.fillColor = UIColor(red: 1, green: 0.93, blue: 0.8, alpha: 0.07 * CGFloat(g.max.flashI))
            beamNode.isHidden = false
        } else { beamNode.isHidden = true }
        let lamps = g.world.props.filter { $0.kind == .lamp }
        while lampGlows.count < lamps.count { let n = sprite(Art.radial, z: 60, add: true); n.color = UIColor(red: 1, green: 0.75, blue: 0.45, alpha: 1); lampGlows.append(n) }
        for (i, n) in lampGlows.enumerated() {
            if i < lamps.count {
                n.isHidden = false; n.position = sp(lamps[i].pos.x, lamps[i].pos.y - 1.2)
                n.size = CGSize(width: 3.2 * S, height: 3.2 * S); n.alpha = 0.22
            } else { n.isHidden = true }
        }
        // the glint: a sparkle through the soil
        if let b = g.world.buried.first(where: { $0.id == "crystal" && !$0.revealed }) {
            let d = abs(g.max.pos.x - b.pos.x), L = lightAt(b.pos.x, b.pos.y)
            if d < 6.5 && L > 0.03 {
                let vis = min(1, (L + 0.35) * (1 - d / 6.5) * 1.7)
                let tw = 0.55 + 0.45 * sin(g.time * 4.1) * sin(g.time * 1.7 + 0.6)
                glintNode.isHidden = false
                glintNode.position = sp(b.pos.x + 0.05, b.pos.y - 0.08)
                let s = CGFloat(0.84 * (0.7 + 0.5 * tw)) * S
                glintNode.size = CGSize(width: s, height: s)
                glintNode.alpha = CGFloat(vis * (0.55 + 0.45 * tw))
                glintNode.zRotation = CGFloat(g.time * 0.4)
                if Double.random(in: 0...1) < 0.06 * vis { addMote(x: b.pos.x + Double.random(in: -0.25...0.25), y: b.pos.y - 0.1, vx: 0, glow: UIColor(red: 0.78, green: 0.65, blue: 1, alpha: 1)) }
            } else { glintNode.isHidden = true }
        } else { glintNode.isHidden = true }
    }

    // MARK: overlays

    private func updatePlan() {
        planNode.removeAllChildren()
        guard let p = game.planning else { return }
        let f = Double(p.floorRow)
        let tgt = planTarget
        let end = tgt ?? p.reach
        let lo = min(p.face, end, p.reach), hi = max(p.face, end, p.reach)
        for c in lo...hi {
            let inSel = tgt != nil ? (c - p.face) * p.dir >= 0 && (c - end) * p.dir <= 0 : false
            let inReach = (c - p.face) * p.dir >= 0 && (c - p.reach) * p.dir <= 0
            guard inSel || (tgt == nil && inReach) else { continue }
            let ok = inReach && !(p.blockedAt.map { (c - $0) * p.dir >= 0 } ?? false)
            for r in [p.floorRow - 2, p.floorRow - 1] where game.world.m(c, r).solid {
                let n = SKShapeNode(rect: CGRect(x: CGFloat(c) * S + 1, y: -CGFloat(r + 1) * S + 1, width: S - 2, height: S - 2), cornerRadius: 3)
                n.fillColor = ok ? UIColor(red: 1, green: 0.7, blue: 0.36, alpha: tgt == nil ? 0.13 : 0.26) : UIColor(red: 0.94, green: 0.31, blue: 0.27, alpha: 0.22)
                n.strokeColor = ok ? UIColor(red: 1, green: 0.78, blue: 0.5, alpha: 0.75) : UIColor(red: 1, green: 0.43, blue: 0.35, alpha: 0.8)
                n.lineWidth = 1.5
                planNode.addChild(n)
            }
        }
        if (p.reach - p.face) * p.dir >= 0 {
            let ex = Double(p.dir > 0 ? p.reach + 1 : p.reach)
            let l = SKShapeNode(); let path = CGMutablePath()
            path.move(to: sp(ex, f - 2.6)); path.addLine(to: sp(ex, f + 0.1)); l.path = path
            l.strokeColor = UIColor(red: 1, green: 0.83, blue: 0.6, alpha: 1); l.lineWidth = 2
            planNode.addChild(l)
            let t = SKLabelNode(fontNamed: "AvenirNext-DemiBold"); t.text = "Stamina runs out here"; t.fontSize = 13 / CGFloat(zoom)
            t.fontColor = UIColor(red: 1, green: 0.83, blue: 0.6, alpha: 1); t.position = sp(ex, f - 2.9); planNode.addChild(t)
        }
    }

    private func updateBubble() {
        let g = game
        let show = g.thoughtT > 0 && !g.thoughtText.isEmpty
        bubble.isHidden = !show
        guard show else { return }
        if bubbleText != g.thoughtText {
            bubbleText = g.thoughtText
            bubbleLabel.text = bubbleText
            let fr = bubbleLabel.calculateAccumulatedFrame()
            bubble.path = CGPath(roundedRect: CGRect(x: -fr.width / 2 - 12, y: -fr.height / 2 - 8, width: fr.width + 24, height: fr.height + 16), cornerWidth: 12, cornerHeight: 12, transform: nil)
        }
        let m = g.max
        let fr = bubble.calculateAccumulatedFrame()
        var x = CGFloat(m.pos.x - camX) * sc, y = -CGFloat(m.pos.y - 2.3 - camY) * sc + fr.height / 2 + 6
        x = max(-size.width / 2 + fr.width / 2 + 10, min(size.width / 2 - fr.width / 2 - 10, x))
        y = min(size.height / 2 - fr.height / 2 - 110, y)
        bubble.position = CGPoint(x: x, y: y)
        bubble.alpha = CGFloat(min(1, g.thoughtT / 0.4))
    }

    private func updateMarker() {
        guard let c = game.context else { markerNode.isHidden = true; return }
        markerNode.isHidden = false
        markerNode.position = sp(c.anchor.x, c.anchor.y + 0.6 + 0.08 * sin(game.time * 3))
        let s = CGFloat(c.prominent ? 0.9 : 0.6) * S
        markerNode.size = CGSize(width: s, height: s)
        markerNode.alpha = 0.5 + 0.2 * CGFloat(sin(game.time * 3))
    }

    /// Points toward the current objective from the edge of the screen when it's out of view.
    private func updateGuide() {
        guard let t = game.guide, game.context == nil else { guideNode.isHidden = true; return }
        let x = CGFloat(t.x - camX) * sc, y = -CGFloat(t.y - camY) * sc
        let hw = size.width / 2 - 34, hh = size.height / 2 - 150
        if abs(x) < hw && abs(y) < hh {
            // In view: hover a small arrow over it, unless Max is already there.
            let d = hypot(t.x - game.max.pos.x, t.y - game.max.pos.y)
            guideNode.isHidden = d < 2.5
            guideNode.position = CGPoint(x: x, y: y + 30 + CGFloat(sin(game.time * 4)) * 5)
            guideNode.zRotation = -.pi / 2
            guideNode.alpha = 0.8
            return
        }
        let k = min(hw / max(abs(x), 1), hh / max(abs(y), 1))
        let bob = CGFloat(sin(game.time * 4)) * 4
        let ang = atan2(y, x)
        guideNode.isHidden = false
        guideNode.position = CGPoint(x: x * k - cos(ang) * bob, y: y * k - sin(ang) * bob)
        guideNode.zRotation = ang
        guideNode.alpha = 0.65 + 0.25 * CGFloat(sin(game.time * 3))
    }
}
