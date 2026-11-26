import AVFoundation
import UIKit

/// All sound is synthesized at launch: no audio files to ship.
final class AudioEngine {
    enum Sfx: CaseIterable {
        case scoop, whoosh, clank, step, land, pour, chime, rush, click, swell, knock, spark
        case stepMetal, stepWood, pick, chop, climb, plank, bag
    }

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private let submix = AVAudioMixerNode()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sfx: [AVAudioPCMBuffer]] = [:]
    private var next = 0
    private var ambientNode = AVAudioPlayerNode()
    private var windNode = AVAudioPlayerNode()
    private var musicNode = AVAudioPlayerNode()
    private var music: AVAudioPCMBuffer? = nil
    private var musicBuilding = false
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var built = false
    private var observers: [NSObjectProtocol] = []

    /// How loud each sound sits in the mix.
    private func gain(_ s: Sfx) -> Float {
        // Quiet and soft: sound should sit under the picture, not on top of it.
        switch s {
        case .step, .stepMetal, .stepWood: return 0.14
        case .climb: return 0.12
        case .whoosh: return 0.12
        case .scoop, .pick, .chop: return 0.3
        case .bag, .plank: return 0.3
        case .swell: return 0.5
        case .chime: return 0.35
        case .spark: return 0.2
        default: return 0.4
        }
    }

    func start() {
        // .playback so the game is heard even with the ring/silent switch on; mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !built {
            built = true
            reverb.loadFactoryPreset(.mediumChamber)
            reverb.wetDryMix = 9
            // Every player feeds a mixer (which takes many inputs), the mixer feeds the reverb, the reverb the output.
            // A reverb has a single input: wiring several players straight into it leaves all but one unconnected,
            // and starting an unconnected player crashes.
            engine.attach(submix)
            engine.attach(reverb)
            engine.connect(submix, to: reverb, format: nil)
            engine.connect(reverb, to: engine.mainMixerNode, format: nil)
            for _ in 0..<14 {
                let p = AVAudioPlayerNode()
                engine.attach(p)
                engine.connect(p, to: submix, format: format)
                players.append(p)
            }
            engine.attach(ambientNode); engine.connect(ambientNode, to: engine.mainMixerNode, format: format)
            engine.attach(windNode); engine.connect(windNode, to: submix, format: format)
            engine.attach(musicNode); engine.connect(musicNode, to: engine.mainMixerNode, format: format)
            windNode.volume = 0
            for s in Sfx.allCases { buffers[s] = (0..<4).map { v in normalized(synth(s, variant: v), peak: 0.85) } }
            let nc = NotificationCenter.default
            observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
                let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if raw == AVAudioSession.InterruptionType.ended.rawValue { self?.resume() }
            })
            observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.resume() })
            observers.append(nc.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in self?.resume() })
        }
        resume()
    }

    /// Restart after an interruption (a call, Siri, a permission prompt, a route change).
    func resume() {
        guard built else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning {
            engine.prepare()
            do { try engine.start() } catch { return }
        }
        for p in players where !p.isPlaying { p.play() }
        if !ambientNode.isPlaying {
            ambientNode.scheduleBuffer(ambientBuffer(), at: nil, options: .loops)
            ambientNode.volume = 0.07
            ambientNode.play()
        }
        if !musicNode.isPlaying {
            if let m = music {
                musicNode.scheduleBuffer(m, at: nil, options: .loops)
                musicNode.volume = musicOn ? 0.17 : 0
                musicNode.play()
            } else if !musicBuilding {
                // ~27 seconds of music takes a moment to synthesize: do it off the main thread.
                musicBuilding = true
                DispatchQueue.global(qos: .utility).async {
                    let m = self.musicBuffer()
                    DispatchQueue.main.async { self.music = m; self.musicBuilding = false; self.resume() }
                }
            }
        }
        if !windNode.isPlaying {
            windNode.scheduleBuffer(windBuffer(), at: nil, options: .loops)
            windNode.play()
        }
    }

    func play(_ s: Sfx, volume: Float = 1) {
        guard built, let bs = buffers[s], !bs.isEmpty else { return }
        if !engine.isRunning { resume(); guard engine.isRunning else { return } }
        let p = players[next % players.count]
        next += 1
        if !p.isPlaying { p.play() }
        p.volume = gain(s) * volume
        p.scheduleBuffer(bs[Int.random(in: 0..<bs.count)], at: nil, options: .interrupts)
    }

    /// The lo-fi bed. On by default; the player can turn it off and keep just the close sounds.
    var musicOn = UserDefaults.standard.object(forKey: "afterlight.music") as? Bool ?? true {
        didSet { UserDefaults.standard.set(musicOn, forKey: "afterlight.music"); musicNode.volume = musicOn ? 0.17 : 0 }
    }

    func cavern(_ on: Bool) {
        reverb.wetDryMix = on ? 26 : 9
        windNode.volume = on ? 0.6 : 0
    }

    // MARK: synthesis

    private func buffer(seconds: Double, _ fill: (Int, Double, inout Double) -> Float) -> AVAudioPCMBuffer {
        let n = AVAudioFrameCount(seconds * format.sampleRate)
        let b = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: n)!
        b.frameLength = n
        let ch = b.floatChannelData![0]
        var state = 0.0
        for i in 0..<Int(n) { ch[i] = fill(i, Double(i) / format.sampleRate, &state) }
        return b
    }

    /// Scale a buffer so its loudest sample sits at `peak`, with a tiny fade at the end to avoid clicks.
    private func normalized(_ b: AVAudioPCMBuffer, peak: Float) -> AVAudioPCMBuffer {
        let ch = b.floatChannelData![0]
        let n = Int(b.frameLength)
        var m: Float = 0
        for i in 0..<n { m = max(m, abs(ch[i])) }
        guard m > 1e-5 else { return b }
        let k = peak / m
        let fade = min(n, 220)
        for i in 0..<n {
            var v = ch[i] * k
            if i >= n - fade { v *= Float(n - i) / Float(fade) }
            ch[i] = v
        }
        return b
    }

    /// One decaying sine partial.
    private func partial(_ f: Double, _ t: Double, _ decay: Double) -> Double {
        let w: Double = 2.0 * Double.pi * f * t
        return sin(w) * exp(-t / decay)
    }

    private func env(_ t: Double, attack a: Double, decay d: Double) -> Double {
        t < a ? t / a : exp(-(t - a) / d)
    }

    /// Band-limited noise with its own little filter state, for grit and crunch.
    private struct Grit {
        var lo = 0.0, lo2 = 0.0
        mutating func band(_ fast: Double, _ slow: Double) -> Double {
            let n = Double.random(in: -1...1)
            lo += (n - lo) * fast
            lo2 += (lo - lo2) * slow
            return lo - lo2
        }
    }


    /// Close-mic crunch: a cluster of tiny grain clicks, each its own little band of noise.
    /// Dense at the bite, thinning out as the soil settles. This is most of the "ASMR" in a dig.
    private func crunch(_ t: Double, _ grains: [(at: Double, f: Double, a: Double)], _ g: inout Grit) -> Double {
        var s = 0.0
        for gr in grains where t >= gr.at && t < gr.at + 0.004 {
            let u = t - gr.at
            s += sin(2.0 * Double.pi * gr.f * u + g.band(0.9, 0.3) * 2) * exp(-u / 0.0011) * gr.a
        }
        return s
    }

    private func grainCloud(count: Int, over span: Double, low: Double, high: Double, front: Double = 2.2) -> [(at: Double, f: Double, a: Double)] {
        (0..<count).map { _ in
            let r = Double.random(in: 0...1)
            let at = pow(r, front) * span          // bunched up front
            return (at, Double.random(in: low...high), Double.random(in: 0.35...1) * (1 - 0.6 * r))
        }
    }

    private func synth(_ s: Sfx, variant v: Int) -> AVAudioPCMBuffer {
        let pitch = 1.0 + Double(v - 1) * 0.06
        switch s {
        case .scoop:
            // Spade into soft earth, close to the ear: a soft push, a dense crunch of grains, a shush of loose soil.
            var g = Grit(), h = Grit()
            let cloud = grainCloud(count: 70 + v * 9, over: 0.32, low: 1800 * pitch, high: 5200 * pitch)
            let settle = grainCloud(count: 18, over: 0.25, low: 900, high: 2600, front: 1)
            return buffer(seconds: 0.62) { (_: Int, t: Double, lp: inout Double) -> Float in
                let push: Double = sin(2.0 * Double.pi * (95.0 - 30.0 * min(1, t / 0.06)) * pitch * t) * env(t, attack: 0.006, decay: 0.045)
                let c = crunch(t, cloud, &g)
                let late: Double = t > 0.3 ? crunch(t - 0.3, settle, &h) * 0.5 : 0
                lp += (Double.random(in: -1...1) - lp) * 0.08
                let shush: Double = lp * sin(Double.pi * min(1, t / 0.5)) * 0.35
                return Float(push * 0.55 + c * 0.9 + late + shush)
            }
        case .pick:
            // Pick into packed earth or stone: a dull, wooden-handled tock, a gritty crackle, a few chips falling.
            var g = Grit()
            let cloud = grainCloud(count: 34, over: 0.12, low: 2600, high: 6800, front: 3)
            let chips = grainCloud(count: 9, over: 0.35, low: 1200, high: 3000, front: 1)
            return buffer(seconds: 0.5) { (_: Int, t: Double, _: inout Double) -> Float in
                var tock = 0.0
                let tf: [Double] = [310, 820, 1460]
                for i in 0..<3 { tock += partial(tf[i] * pitch, t, 0.035 - Double(i) * 0.008) / Double(i + 1) }
                let c = crunch(t, cloud, &g)
                let fall: Double = t > 0.1 ? crunch(t - 0.1, chips, &g) * 0.6 : 0
                return Float(tock * 0.7 + c * 0.85 + fall)
            }
        case .chop:
            // Blade into root: a soft woody knock and the crackle of fibres tearing.
            var g = Grit()
            let fibres = grainCloud(count: 46, over: 0.28, low: 700, high: 2400, front: 1.6)
            return buffer(seconds: 0.48) { (_: Int, t: Double, _: inout Double) -> Float in
                var knock = 0.0
                let kf: [Double] = [180, 410, 760]
                for i in 0..<3 { knock += partial(kf[i] * pitch, t, 0.08 - Double(i) * 0.02) / Double(i + 1) }
                return Float(knock * 0.75 + crunch(t, fibres, &g) * 0.9)
            }
        case .whoosh:
            return buffer(seconds: 0.3) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * (0.05 + t * 0.6)
                return Float(lp * sin(.pi * min(1, t / 0.3)))
            }
        case .clank:
            return buffer(seconds: 1.2) { (_: Int, t: Double, _: inout Double) -> Float in
                let f = [587.0, 1271, 1983, 2961, 4103]
                var s = 0.0
                for (i, fr) in f.enumerated() {
                    let di = Double(i)
                    let tone: Double = sin(2.0 * Double.pi * fr * pitch * t)
                    let decay: Double = exp(-t / (0.9 - di * 0.14))
                    s += tone * decay / (di * 0.7 + 1.0)
                }
                return Float(s)
            }
        case .step:
            // A soft boot on grit: a cushioned heel, then a little crunch rolling toward the toe.
            var g = Grit()
            let cloud = grainCloud(count: 16 + v * 3, over: 0.09, low: 1500, high: 4200, front: 1.4)
            return buffer(seconds: 0.14) { (_: Int, t: Double, _: inout Double) -> Float in
                let heel: Double = sin(2.0 * Double.pi * 72.0 * pitch * t) * env(t, attack: 0.004, decay: 0.02)
                return Float(heel * 0.6 + crunch(t, cloud, &g) * 0.7)
            }
        case .stepMetal:
            // A boot on steel plate: a muffled thump and a faint ring.
            var g = Grit()
            return buffer(seconds: 0.28) { (_: Int, t: Double, _: inout Double) -> Float in
                let thud: Double = sin(2.0 * Double.pi * 110.0 * pitch * t) * env(t, attack: 0.002, decay: 0.03)
                var ring = 0.0
                let mf: [Double] = [910, 1430, 2210]
                for i in 0..<3 { ring += partial(mf[i] * pitch, t, 0.09 - Double(i) * 0.02) }
                let scuff = g.band(0.5, 0.05) * env(t, attack: 0.002, decay: 0.012)
                return Float(thud + ring * 0.16 + scuff * 0.4)
            }
        case .stepWood:
            return buffer(seconds: 0.2) { (_: Int, t: Double, _: inout Double) -> Float in
                var k = 0.0
                let wf: [Double] = [140, 330, 610]
                for i in 0..<3 { k += partial(wf[i] * pitch, t, 0.05 - Double(i) * 0.012) / Double(i + 1) }
                return Float(k)
            }
        case .climb:
            // Hands and boots finding the next hold: a cloth rustle and a small grip tick.
            var g = Grit()
            return buffer(seconds: 0.26) { (_: Int, t: Double, _: inout Double) -> Float in
                let rustle: Double = t < 0.2 ? g.band(0.25, 0.04) * sin(Double.pi * min(1.0, t / 0.2)) : 0
                let tick: Double = t > 0.16 ? sin(2.0 * Double.pi * 240.0 * pitch * t) * env(t - 0.16, attack: 0.001, decay: 0.018) : 0
                return Float(rustle * 0.7 + tick * 0.8)
            }
        case .plank:
            // A board dropped into place: a wooden thunk and a rattle as it settles.
            return buffer(seconds: 0.6) { (_: Int, t: Double, _: inout Double) -> Float in
                var k = 0.0
                let bf: [Double] = [118, 286, 520]
                for i in 0..<3 { k += partial(bf[i] * pitch, t, 0.14 - Double(i) * 0.03) / Double(i + 1) }
                var rattle = 0.0
                for h in [0.11, 0.17, 0.21] where t > h { rattle += partial(300, t - h, 0.012) * 0.35 }
                return Float(k + rattle)
            }
        case .bag:
            // Something going into the bag: a short zip of teeth and a soft cloth flop.
            var g = Grit()
            return buffer(seconds: 0.34) { (_: Int, t: Double, _: inout Double) -> Float in
                let rate: Double = 55.0 + 140.0 * t
                let phase: Double = (t * rate).truncatingRemainder(dividingBy: 1)
                let teeth: Double = (t < 0.22 && phase < 0.08) ? g.band(0.8, 0.2) : 0
                let flop: Double = t > 0.22 ? sin(2.0 * Double.pi * 95.0 * t) * env(t - 0.22, attack: 0.003, decay: 0.03) : 0
                return Float(teeth * 1.2 + flop * 0.6)
            }
        case .land:
            return buffer(seconds: 0.35) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * 0.06
                return Float((lp * 1.4 + sin(2 * .pi * 70 * t) * 0.4) * env(t, attack: 0.003, decay: 0.08))
            }
        case .pour:
            return buffer(seconds: 1.4) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * 0.12
                let grit = Double.random(in: 0...1) < 0.004 ? Double.random(in: -0.6...0.6) : 0
                return Float((lp * 0.7 + grit) * env(t, attack: 0.02, decay: 0.45))
            }
        case .chime:
            return buffer(seconds: 2.2) { (_: Int, t: Double, _: inout Double) -> Float in
                let notes = [1046.5, 1318.5, 1568, 2093]
                var s = 0.0
                for (i, f) in notes.enumerated() {
                    let st = Double(i) * 0.09
                    if t > st { s += sin(2 * .pi * f * (t - st)) * exp(-(t - st) / 0.7) }
                }
                return Float(s)
            }
        case .rush:
            return buffer(seconds: 4) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * (0.01 + 0.08 * min(1, t / 2))
                let bf: Double = 60.0 - 30.0 * min(1.0, t / 2.5)
                let boom: Double = sin(2.0 * Double.pi * bf * t) * exp(-t / 1.2)
                let swell: Double = lp * 1.2 * sin(Double.pi * min(1.0, t / 4.0))
                return Float(swell + boom * 0.6)
            }
        case .click:
            return buffer(seconds: 0.15) { (_: Int, t: Double, _: inout Double) -> Float in
                Float((t < 0.015 ? (sin(2 * .pi * 2300 * t) > 0 ? 0.2 : -0.2) : 0) + sin(2 * .pi * 180 * t) * exp(-t / 0.03) * 0.4)
            }
        case .swell:
            return buffer(seconds: 8) { (_: Int, t: Double, _: inout Double) -> Float in
                let fs = [110.0, 164.8, 220, 246.9, 329.6, 440]
                var s = 0.0
                for (i, f) in fs.enumerated() { s += sin(2 * .pi * f * t + Double(i)) * (i % 2 == 0 ? 1 : 0.6) }
                let e = min(1, t / 2.2) * exp(-max(0, t - 2.4) / 2.2)
                return Float(s * e * 0.4)
            }
        case .knock:
            return buffer(seconds: 2.2) { (_: Int, t: Double, _: inout Double) -> Float in
                let hits = [0.0, 0.22, 0.44, 1.1, 1.32]
                var s = 0.0
                for h in hits where t > h { s += sin(2 * .pi * 95 * (t - h)) * exp(-(t - h) / 0.05) }
                return Float(s)
            }
        case .spark:
            return buffer(seconds: 0.25) { (_: Int, t: Double, _: inout Double) -> Float in
                Float(Double.random(in: 0...1) < 0.08 ? Double.random(in: -0.4...0.4) * exp(-t / 0.08) : 0)
            }
        }
    }

    private func ambientBuffer() -> AVAudioPCMBuffer {
        // Room tone only: a warm, very low hush that breathes slowly. No drips: a repeating drip is the first
        // thing a player hears and the last thing they want to keep hearing.
        buffer(seconds: 16) { (_: Int, t: Double, lp: inout Double) -> Float in
            lp += (Double.random(in: -1...1) - lp) * 0.006
            let breathe = 0.75 + 0.25 * sin(2 * .pi * t / 16)
            return Float((lp * 0.32 + sin(2 * .pi * 41.2 * t) * 0.02) * breathe)
        }
    }

    /// The lo-fi bed: four lazy major-seventh chords on a soft electric piano, a round bass, a brushed beat,
    /// tape wow and a little dust, all under a low-pass so nothing is bright. About 27 seconds, looping.
    private func musicBuffer() -> AVAudioPCMBuffer {
        let bpm = 70.0, beat = 60.0 / bpm, bar = beat * 4
        func hz(_ midi: Double) -> Double { 440 * pow(2, (midi - 69) / 12) }
        // Fmaj7 · Em7 · Dm9 · Cmaj7, two bars each
        let chords: [[Double]] = [[53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 57, 60, 64], [48, 52, 55, 59]]
        let roots: [Double] = [41, 40, 38, 36]
        var notes: [(at: Double, f: Double, a: Double, d: Double)] = []
        for (ci, ch) in chords.enumerated() {
            let start = Double(ci) * bar * 2
            for hit in [0.0, beat * 2.5, bar, bar + beat * 2.5] {
                for (k, m) in ch.enumerated() {
                    // a lazy, slightly late strum
                    notes.append((start + hit + Double(k) * 0.018 + Double.random(in: 0...0.012), hz(m), hit == 0 || hit == bar ? 0.16 : 0.1, 2.4))
                }
            }
            notes.append((start, hz(roots[ci]), 0.32, 3.2))
            notes.append((start + bar + beat * 2, hz(roots[ci] + 7), 0.2, 1.6))
        }
        let length = bar * 8
        let crackles = (0..<70).map { _ in (Double.random(in: 0..<length), Double.random(in: 0.2...1)) }
        let kicks = stride(from: 0.0, to: length, by: bar).flatMap { [$0, $0 + beat * 2.5] }
        let hats = stride(from: beat / 2, to: length, by: beat)
        return buffer(seconds: length) { (_: Int, t: Double, lp: inout Double) -> Float in
            // tape wow: the whole loop drifts in pitch, very slightly
            let wow = 1 + 0.0035 * sin(2 * .pi * 0.45 * t) + 0.001 * sin(2 * .pi * 5.1 * t)
            var s = 0.0
            for n in notes where t >= n.at && t < n.at + n.d * 3 {
                let u = t - n.at
                let ph = 2 * Double.pi * n.f * u * wow
                // electric piano: a sine with a soft second harmonic and a short bell on the attack
                let e = env(u, attack: 0.008, decay: n.d)
                s += (sin(ph) + 0.22 * sin(2 * ph) + 0.12 * sin(7 * ph) * exp(-u / 0.08)) * e * n.a
            }
            for k in kicks where t >= k && t < k + 0.25 { let u = t - k; s += sin(2 * .pi * (58 - 20 * min(1, u / 0.1)) * u) * exp(-u / 0.09) * 0.3 }
            for h in hats where t >= h && t < h + 0.06 { let u = t - h; s += Double.random(in: -1...1) * exp(-u / 0.012) * 0.025 }
            for (at, a) in crackles where t >= at && t < at + 0.002 { s += Double.random(in: -1...1) * a * 0.05 }
            s += Double.random(in: -1...1) * 0.004    // hiss
            // low-pass around 2.5 kHz: nothing sharp
            lp += (s - lp) * 0.3
            return Float(lp * 0.9)
        }
    }

    private func windBuffer() -> AVAudioPCMBuffer {
        buffer(seconds: 10) { (_: Int, t: Double, lp: inout Double) -> Float in
            lp += (Double.random(in: -1...1) - lp) * (0.02 + 0.015 * sin(2 * .pi * t / 10))
            return Float(lp * 0.5)
        }
    }
}

final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let heavy = UIImpactFeedbackGenerator(style: .heavy)
    func bite() { light.impactOccurred(intensity: 0.7) }
    func clank() { rigid.impactOccurred() }
    func big() { heavy.impactOccurred() }
    func tap() { light.impactOccurred(intensity: 0.4) }
}
