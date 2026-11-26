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
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var built = false
    private var observers: [NSObjectProtocol] = []

    /// How loud each sound sits in the mix.
    private func gain(_ s: Sfx) -> Float {
        switch s {
        case .step: return 0.55
        case .stepMetal: return 0.5
        case .stepWood: return 0.55
        case .climb: return 0.45
        case .whoosh: return 0.5
        case .swell: return 0.9
        case .spark: return 0.6
        default: return 0.9
        }
    }

    func start() {
        // .playback so the game is heard even with the ring/silent switch on; mixes with the player's music.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        if !built {
            built = true
            reverb.loadFactoryPreset(.mediumChamber)
            reverb.wetDryMix = 18
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
            ambientNode.volume = 0.45
            ambientNode.play()
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

    func cavern(_ on: Bool) {
        reverb.wetDryMix = on ? 45 : 18
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

    private func synth(_ s: Sfx, variant v: Int) -> AVAudioPCMBuffer {
        let pitch = 1.0 + Double(v - 1) * 0.06
        switch s {
        case .scoop:
            // The blade bites (a dull thump and a crunch), then loose dirt patters down.
            var g = Grit(), g2 = Grit()
            let patter = (0..<9).map { _ in Double.random(in: 0.12...0.5) }
            return buffer(seconds: 0.65) { (_: Int, t: Double, _: inout Double) -> Float in
                let freq: Double = (140.0 - 70.0 * min(1.0, t / 0.08)) * pitch
                let thump: Double = sin(2.0 * Double.pi * freq * t) * env(t, attack: 0.003, decay: 0.05)
                let crunch: Double = g.band(0.35 * pitch, 0.02) * env(t, attack: 0.004, decay: 0.07)
                var fall = 0.0
                for p in patter where t > p && t < p + 0.03 { let u: Double = t - p; fall += g2.band(0.5, 0.05) * exp(-u / 0.008) * 0.5 }
                return Float(thump * 0.8 + crunch * 1.3 + fall)
            }
        case .pick:
            // Steel point into packed earth: a bright tick that rings briefly, a crack, and grit.
            var g = Grit()
            return buffer(seconds: 0.5) { (_: Int, t: Double, _: inout Double) -> Float in
                var ring = 0.0
                let pf: [Double] = [2350, 3720, 5100]
                for i in 0..<3 { ring += partial(pf[i] * pitch, t, 0.05 - Double(i) * 0.012) }
                let crack = g.band(0.6, 0.08) * env(t, attack: 0.001, decay: 0.03)
                let dull: Double = sin(2.0 * Double.pi * 190.0 * pitch * t) * env(t, attack: 0.002, decay: 0.04)
                let grit: Double = t > 0.06 && Double.random(in: 0...1) < 0.006 ? Double.random(in: -0.4...0.4) * exp(-t / 0.2) : 0
                return Float(ring * 0.35 + crack * 1.2 + dull * 0.5 + grit)
            }
        case .chop:
            // Blade into a root: a hollow woody knock with a short creak.
            var g = Grit()
            return buffer(seconds: 0.45) { (_: Int, t: Double, _: inout Double) -> Float in
                var knock = 0.0
                let kf: [Double] = [165, 392, 731, 1180]
                for i in 0..<4 { knock += partial(kf[i] * pitch, t, 0.11 - Double(i) * 0.02) / Double(i + 1) }
                let click = g.band(0.7, 0.1) * env(t, attack: 0.0005, decay: 0.008)
                let wob: Double = 520.0 + 90.0 * sin(t * 60.0)
                let creak: Double = t > 0.05 ? sin(2.0 * Double.pi * wob * t) * env(t - 0.05, attack: 0.02, decay: 0.06) * 0.12 : 0
                return Float(knock * 1.0 + click * 0.9 + creak)
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
            // A boot on packed dirt: soft heel thud, then a gravelly crunch of a few grains.
            var g = Grit()
            let grains = (0..<5).map { _ in Double.random(in: 0.008...0.07) }
            return buffer(seconds: 0.14) { (_: Int, t: Double, _: inout Double) -> Float in
                let thud: Double = sin(2.0 * Double.pi * 85.0 * pitch * t) * env(t, attack: 0.002, decay: 0.022)
                var crunch = g.band(0.42 * pitch, 0.03) * env(t, attack: 0.004, decay: 0.035)
                for gr in grains where t > gr && t < gr + 0.006 { let u: Double = t - gr; crunch += Double.random(in: -0.8...0.8) * exp(-u / 0.0015) }
                return Float(thud * 0.9 + crunch * 0.8)
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
        // A low room tone with slow drips, so the underground never sounds dead.
        let drips = (0..<5).map { _ in (Double.random(in: 0.5...7.5), Double.random(in: 900...1500)) }
        return buffer(seconds: 8) { (_: Int, t: Double, lp: inout Double) -> Float in
            lp += (Double.random(in: -1...1) - lp) * 0.004
            var d = 0.0
            for (at, f) in drips where t > at && t < at + 0.25 {
                let u: Double = t - at
                let fr: Double = f + 600.0 * u
                d += sin(2.0 * Double.pi * fr * u) * exp(-u / 0.035) * 0.06
            }
            return Float(sin(2 * .pi * 46.25 * t) * 0.05 + sin(2 * .pi * 69.375 * t) * 0.03 + lp * 0.3 + d)
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
