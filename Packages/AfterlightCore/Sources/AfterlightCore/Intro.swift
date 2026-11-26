import Foundation

/// The opening cinematic: twelve full-screen scenes, one line of narration each,
/// paced like Stories with segmented progress. Pure logic so it can be tested off-device.
public struct IntroScene: Equatable, Sendable {
    public enum Bubble: String, Sendable { case top, middle, bottom }
    public var image: String
    public var text: String
    /// Where the narration sits so the important detail stays visible.
    public var bubble: Bubble
}

public enum IntroScript {
    public static let scenes: [IntroScene] = [
        IntroScene(image: "01-valley", text: "In 3100 AD…", bubble: .bottom),
        IntroScene(image: "02-rumor",
                   text: "No one knows where it started. At first it was only a rumor between shifts: a sickness with no name and no cure.",
                   bubble: .bottom),
        IntroScene(image: "03-shifts",
                   text: "If you caught it, you died. Soon every crew was short, and every town was burying someone.",
                   bubble: .bottom),
        IntroScene(image: "04-shelves", text: "Then the deliveries stopped. The shelves went bare. People lined up anyway, for nothing.", bubble: .bottom),
        IntroScene(image: "05-road",
                   text: "Towns barricaded their roads. Anyone caught on the wrong side was left to die.",
                   bubble: .bottom),
        IntroScene(image: "06-rich",
                   text: "The rich never stood in those lines. They paid the miners to carve them shelters deep in the mountain, and bought their way below.",
                   bubble: .bottom),
        IntroScene(image: "07-families",
                   text: "So the miners carved one more, kept off every map. Not for the people who paid. For their own families.",
                   bubble: .top),
        IntroScene(image: "08-strikes",
                   text: "When the barricades failed, the governments turned to fire. They bombed the towns they had sealed.",
                   bubble: .top),
        IntroScene(image: "09-collapse",
                   text: "The bombs reached the mountain. The shelters held. Every tunnel back to the surface came down.",
                   bubble: .bottom),
        IntroScene(image: "10-radio", text: "The satellites went dark. One by one, the voices on the radio stopped answering.", bubble: .top),
        IntroScene(image: "11-generations",
                   text: "A hundred years passed underground. Children grew old in the dark. In the end, only Max and his father remained.",
                   bubble: .bottom),
        IntroScene(image: "12-max",
                   text: "Max buried his father. The pump had stopped. He took his father’s shovel and went looking for a way up.",
                   bubble: .top),
    ]

    /// Reading time: short lines move quickly, long ones get time to be read comfortably.
    public static func duration(_ s: IntroScene) -> Double {
        let words = s.text.split(separator: " ").count
        return Swift.max(1.9, 0.9 + Double(words) * 0.25)
    }
}

public struct IntroPlayer: Equatable, Sendable {
    public private(set) var index = 0
    /// 0…1 progress through the current scene.
    public private(set) var progress = 0.0
    public var held = false          // finger down: pause until released
    public var paused = false        // the Pause control
    public var backgrounded = false  // app not active
    public private(set) var skipped = false
    public let scenes: [IntroScene]

    public init(scenes: [IntroScene] = IntroScript.scenes) { self.scenes = scenes }

    public var scene: IntroScene { scenes[index] }
    public var isLast: Bool { index == scenes.count - 1 }
    /// On the final image the story holds and waits for the player to light the candle.
    public var waitingForCandle: Bool { skipped || (isLast && progress >= 1) }
    public var running: Bool { !held && !paused && !backgrounded && !waitingForCandle }

    public mutating func tick(_ dt: Double) {
        guard running else { return }
        progress = Swift.min(1, progress + dt / IntroScript.duration(scene))
        if progress >= 1 && !isLast { index += 1; progress = 0 }
    }

    /// Tap on the right half.
    public mutating func next() {
        if isLast { progress = 1 } else { index += 1; progress = 0 }
    }

    /// Tap on the left half: restart this scene, or go back if it has barely begun.
    public mutating func back() {
        if progress < 0.15 && index > 0 { index -= 1 }
        progress = 0
        skipped = false
    }

    /// Skip intro: jump to Max at the grave, waiting for the candle.
    public mutating func skip() {
        index = scenes.count - 1
        progress = 1
        skipped = true
    }
}
