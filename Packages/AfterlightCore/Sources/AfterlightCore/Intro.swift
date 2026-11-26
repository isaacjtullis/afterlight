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
        IntroScene(image: "01-valley", text: "The year was 2087.", bubble: .bottom),
        IntroScene(image: "02-rumor",
                   text: "No one knows how it started. A new kind of flu, overseas. The news said it was under control.",
                   bubble: .bottom),
        IntroScene(image: "03-shifts",
                   text: "Then came the rumors. People fine at breakfast were rushed to the hospital by lunch.",
                   bubble: .bottom),
        IntroScene(image: "04-shelves",
                   text: "Borders closed. Flights were cancelled. The world ground to a halt, and the shelves went bare.",
                   bubble: .bottom),
        IntroScene(image: "05-road",
                   text: "It killed 65 of every 100 it touched. Soon the sickness wasn’t the worst thing out there. Hungry people were.",
                   bubble: .bottom),
        IntroScene(image: "06-rich",
                   text: "The rich had seen it coming. They paid construction crews to carve deep bunkers into the mountain, and slipped below while everyone else starved.",
                   bubble: .bottom),
        IntroScene(image: "07-families",
                   text: "The crews knew what was coming too. In secret, they built one more shelter, for their own families.",
                   bubble: .top),
        IntroScene(image: "08-strikes",
                   text: "Then the bombs fell. Atomic fire on every city. The surface was no longer safe for anyone.",
                   bubble: .top),
        IntroScene(image: "09-collapse",
                   text: "The blasts shook the mountain. Every tunnel to the surface caved in. Whoever was inside was trapped there.",
                   bubble: .bottom),
        IntroScene(image: "10-radio", text: "The radio went quiet. No one below knew if anyone was left above.", bubble: .top),
        IntroScene(image: "11-generations",
                   text: "Life went on. Waterworks, grow lights, patient maintenance. The ones who came down had children in the dark: kids who knew the word “rain” and had never felt it.",
                   bubble: .bottom),
        IntroScene(image: "12-max",
                   text: "Today Max buried his father. He is the last one left in Shelter 4. Dad’s shovel is by the door. His cup is still beside the sink.",
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
