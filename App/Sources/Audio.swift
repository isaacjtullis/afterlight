import AVFoundation
import UIKit

/// All sound is synthesized at launch: no audio files to ship.
final class AudioEngine {
    enum Sfx: CaseIterable { case scoop, whoosh, clank, step, land, pour, chime, rush, click, swell, knock, spark }

    private let engine = AVAudioEngine()
    private let reverb = AVAudioUnitReverb()
    private var players: [AVAudioPlayerNode] = []
    private var buffers: [Sfx: [AVAudioPCMBuffer]] = [:]
    private var next = 0
    private var ambientNode = AVAudioPlayerNode()
    private var windNode = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var started = false

    func start() {
        guard !started else { return }
        started = true
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
        try? AVAudioSession.sharedInstance().setActive(true)
        reverb.loadFactoryPreset(.mediumChamber)
        reverb.wetDryMix = 18
        engine.attach(reverb)
        engine.connect(reverb, to: engine.mainMixerNode, format: format)
        for _ in 0..<10 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: reverb, format: format)
            players.append(p)
        }
        engine.attach(ambientNode); engine.connect(ambientNode, to: engine.mainMixerNode, format: format)
        engine.attach(windNode); engine.connect(windNode, to: reverb, format: format)
        for s in Sfx.allCases { buffers[s] = (0..<3).map { v in synth(s, variant: v) } }
        do { try engine.start() } catch { return }
        players.forEach { $0.play() }
        ambientNode.scheduleBuffer(ambientBuffer(), at: nil, options: .loops)
        ambientNode.volume = 0.5
        ambientNode.play()
        windNode.scheduleBuffer(windBuffer(), at: nil, options: .loops)
        windNode.volume = 0
        windNode.play()
    }

    func play(_ s: Sfx) {
        guard started, let bs = buffers[s], !bs.isEmpty else { return }
        let p = players[next % players.count]
        next += 1
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

    private func env(_ t: Double, attack a: Double, decay d: Double) -> Double {
        t < a ? t / a : exp(-(t - a) / d)
    }

    private func synth(_ s: Sfx, variant v: Int) -> AVAudioPCMBuffer {
        let pitch = 1.0 + Double(v - 1) * 0.07
        switch s {
        case .scoop:
            return buffer(seconds: 0.7) { (_: Int, t: Double, lp: inout Double) -> Float in
                let n = Double.random(in: -1...1)
                lp += (n - lp) * 0.18 * pitch
                let freq: Double = (150.0 - 80.0 * min(1.0, t / 0.1)) * pitch
                let thump: Double = sin(2.0 * Double.pi * freq * t) * env(t, attack: 0.004, decay: 0.06)
                var grit: Double = 0
                if t > 0.08 && Double.random(in: 0...1) < 0.002 { grit = Double.random(in: -0.5...0.5) }
                let body: Double = lp * 0.9 * env(t, attack: 0.004, decay: 0.09)
                return Float((body + thump * 0.6 + grit) * 0.7)
            }
        case .whoosh:
            return buffer(seconds: 0.3) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * (0.05 + t * 0.6)
                return Float(lp * 0.35 * sin(.pi * min(1, t / 0.3)))
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
                return Float(s * 0.22)
            }
        case .step:
            return buffer(seconds: 0.09) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * 0.08 * pitch
                return Float(lp * 1.6 * env(t, attack: 0.003, decay: 0.03))
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
                return Float(s * 0.12)
            }
        case .rush:
            return buffer(seconds: 4) { (_: Int, t: Double, lp: inout Double) -> Float in
                lp += (Double.random(in: -1...1) - lp) * (0.01 + 0.08 * min(1, t / 2))
                let bf: Double = 60.0 - 30.0 * min(1.0, t / 2.5)
                let boom: Double = sin(2.0 * Double.pi * bf * t) * exp(-t / 1.2)
                let swell: Double = lp * 1.2 * sin(Double.pi * min(1.0, t / 4.0))
                return Float((swell + boom * 0.6) * 0.6)
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
                return Float(s * 0.035 * e)
            }
        case .knock:
            return buffer(seconds: 2.2) { (_: Int, t: Double, _: inout Double) -> Float in
                let hits = [0.0, 0.22, 0.44, 1.1, 1.32]
                var s = 0.0
                for h in hits where t > h { s += sin(2 * .pi * 95 * (t - h)) * exp(-(t - h) / 0.05) }
                return Float(s * 0.5)
            }
        case .spark:
            return buffer(seconds: 0.25) { (_: Int, t: Double, _: inout Double) -> Float in
                Float(Double.random(in: 0...1) < 0.08 ? Double.random(in: -0.4...0.4) * exp(-t / 0.08) : 0)
            }
        }
    }

    private func ambientBuffer() -> AVAudioPCMBuffer {
        buffer(seconds: 8) { (_: Int, t: Double, lp: inout Double) -> Float in
            lp += (Double.random(in: -1...1) - lp) * 0.004
            return Float(sin(2 * .pi * 46.25 * t) * 0.05 + sin(2 * .pi * 69.375 * t) * 0.03 + lp * 0.3)
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
