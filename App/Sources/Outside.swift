import SwiftUI
import AfterlightCore

/// Out through the surface door: grey sky, a stretch of ground, a horizon past where the flashlight
/// stops, wind you can see and hear change its mind. Max walks with the same controls.
struct OutsideView: View {
    let walk: OutsideWalk
    let thought: String?

    var body: some View {
        TimelineView(.animation) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let horizon = h * 0.52
                // Sky: a thin grey light, brighter toward the horizon.
                ctx.fill(Path(CGRect(x: 0, y: 0, width: w, height: horizon + 2)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.32, green: 0.35, blue: 0.4), Color(red: 0.72, green: 0.72, blue: 0.7)]),
                                               startPoint: .zero, endPoint: CGPoint(x: 0, y: horizon)))
                // Far hills: they barely move as he walks.
                var far = Path(); far.move(to: CGPoint(x: 0, y: horizon))
                for i in 0...40 {
                    let x = CGFloat(i) / 40 * w
                    let k = Double(x) / 90 + walk.x * 0.02
                    far.addLine(to: CGPoint(x: x, y: horizon - 18 - CGFloat(sin(k) * 10 + sin(k * 2.7) * 5)))
                }
                far.addLine(to: CGPoint(x: w, y: horizon)); far.closeSubpath()
                ctx.fill(far, with: .color(Color(red: 0.5, green: 0.52, blue: 0.54)))
                // A mountain, very far off. It doesn't get closer.
                var m = Path()
                m.move(to: CGPoint(x: w * 0.55, y: horizon - 14)); m.addLine(to: CGPoint(x: w * 0.7, y: horizon - 70)); m.addLine(to: CGPoint(x: w * 0.86, y: horizon - 10)); m.closeSubpath()
                ctx.fill(m, with: .color(Color(red: 0.6, green: 0.62, blue: 0.66).opacity(0.7)))
                // The ground he walks on: dark, uneven, scrolling with him.
                ctx.fill(Path(CGRect(x: 0, y: horizon, width: w, height: h - horizon)),
                         with: .linearGradient(Gradient(colors: [Color(red: 0.36, green: 0.33, blue: 0.3), Color(red: 0.16, green: 0.14, blue: 0.13)]),
                                               startPoint: CGPoint(x: 0, y: horizon), endPoint: CGPoint(x: 0, y: h)))
                for i in 0..<26 {
                    let s = Double(i) * 53.7
                    let x = CGFloat((s * 11 - walk.x * 38).truncatingRemainder(dividingBy: Double(w) + 60)) - 30
                    let xx = x < -30 ? x + w + 60 : x
                    let y = horizon + 30 + CGFloat(i % 7) * (h - horizon - 60) / 7
                    ctx.fill(Path(ellipseIn: CGRect(x: xx, y: y, width: 10 + CGFloat(i % 4) * 6, height: 4)), with: .color(.black.opacity(0.25)))
                }
                // Wind: grass-streaks and grit blowing the way the wind goes.
                for i in 0..<60 {
                    let seed = Double(i) * 12.9898
                    let speed = 60 + 140 * abs(walk.wind)
                    let dir = walk.wind >= 0 ? 1.0 : -1.0
                    let px = (seed * 37 + t * speed * dir).truncatingRemainder(dividingBy: Double(w))
                    let x = CGFloat(px < 0 ? px + Double(w) : px)
                    let y = CGFloat((seed * 91).truncatingRemainder(dividingBy: Double(h)))
                    var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x - CGFloat(dir * (6 + 14 * abs(walk.wind))), y: y + 1))
                    ctx.stroke(p, with: .color(.white.opacity(0.18)), lineWidth: 1)
                }
                // Max, small against all of it.
                let mx = w * 0.42, my = h * 0.74
                let step = walk.walking ? sin(t * 9) * 3 : 0
                ctx.fill(Path(roundedRect: CGRect(x: mx - 7, y: my - 30, width: 14, height: 24), cornerRadius: 4), with: .color(Color(red: 0.93, green: 0.86, blue: 0.74)))
                ctx.fill(Path(ellipseIn: CGRect(x: mx - 7, y: my - 44, width: 14, height: 14)), with: .color(Color(red: 0.95, green: 0.82, blue: 0.7)))
                ctx.fill(Path(ellipseIn: CGRect(x: mx - 8, y: my - 47, width: 16, height: 9)), with: .color(Color(red: 0.29, green: 0.23, blue: 0.36)))
                var scarf = Path(); scarf.move(to: CGPoint(x: mx, y: my - 30))
                scarf.addLine(to: CGPoint(x: mx - CGFloat(walk.wind * 22), y: my - 28 + CGFloat(sin(t * 7) * 3)))
                ctx.stroke(scarf, with: .color(Color(red: 0.78, green: 0.27, blue: 0.18)), lineWidth: 4)
                ctx.fill(Path(CGRect(x: mx - 5 + CGFloat(step), y: my - 6, width: 4, height: 8)), with: .color(.black.opacity(0.7)))
                ctx.fill(Path(CGRect(x: mx + 1 - CGFloat(step), y: my - 6, width: 4, height: 8)), with: .color(.black.opacity(0.7)))
            }
        }
        .overlay(alignment: .top) {
            if let thought {
                Text(thought).font(.avenir(15)).foregroundStyle(Color.cream).padding(.horizontal, 16).padding(.vertical, 9)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.45))).padding(.top, 140)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The ending's last word: what happened, what Max gained, what he gave up. Shown once.
struct EpilogueView: View {
    let lines: [String]
    let close: () -> Void
    var body: some View {
        ZStack {
            Color.black.opacity(0.72).ignoresSafeArea()
            VStack(spacing: 16) {
                Text("AFTERLIGHT").font(.avenir(12, "DemiBold")).tracking(6).foregroundStyle(Color.amber)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, l in
                    Text(l).font(.avenir(16)).foregroundStyle(Color.cream).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                Button(action: close) {
                    Text("Keep playing").font(.avenir(15, "DemiBold")).foregroundStyle(.black).padding(.horizontal, 22).frame(height: 44)
                        .background(Capsule().fill(Color.amber))
                }.padding(.top, 8).accessibilityIdentifier("epilogue.close")
            }
            .padding(28).frame(maxWidth: 440)
        }
    }
}
