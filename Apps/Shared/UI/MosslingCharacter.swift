import SwiftUI
import MosslingCore

enum MossPalette {
    static let cream = Color(red: 0.97, green: 0.96, blue: 0.91)
    static let ink = Color(red: 0.16, green: 0.24, blue: 0.19)
    static let moss = Color(red: 0.33, green: 0.46, blue: 0.29)
    static let mint = Color(red: 0.78, green: 0.86, blue: 0.65)
    static let fern = Color(red: 0.38, green: 0.57, blue: 0.30)
    static let gold = Color(red: 0.88, green: 0.65, blue: 0.30)
    static let stone = Color(red: 0.89, green: 0.89, blue: 0.81)
}

/// A bundled watercolor body plus native face and fern layers lets the character
/// move independently. The art direction is deliberately separate from rewards.
struct MosslingCharacter: View {
    enum Mood: String, CaseIterable { case cozy, curious, celebrating, sleeping }
    var mood: Mood = .cozy
    var stage: Int = 0
    var animate = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    #endif
    @State private var breathing = false
    @State private var blinking = false

    private var isHappy: Bool { mood == .celebrating }
    private var isSleeping: Bool { mood == .sleeping }
    private var allowsMotion: Bool {
        #if os(watchOS)
        animate && !reduceMotion && scenePhase == .active && !isLuminanceReduced
        #else
        animate && !reduceMotion && scenePhase == .active
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let width = min(proxy.size.width, proxy.size.height * 1.12)
            ZStack {
                Ellipse()
                    .fill(MossPalette.ink.opacity(0.10))
                    .frame(width: width * 0.72, height: width * 0.10)
                    .offset(y: width * 0.34)
                    .scaleEffect(breathing && isHappy ? 0.8 : 1)

                ZStack {
                    Image("MossBody")
                        .resizable().scaledToFit()
                        .frame(width: width, height: width)
                    FernCrest(stage: stage)
                        .frame(width: width * 0.32, height: width * 0.37)
                        .rotationEffect(.degrees(breathing ? 4 : -3), anchor: .bottom)
                        .offset(x: width * 0.035, y: -width * 0.35)
                    HStack(spacing: width * 0.19) {
                        eye(width: width)
                        eye(width: width)
                    }
                    .offset(y: width * 0.04)
                    HStack(spacing: width * 0.37) {
                        Capsule().fill(Color(red: 0.85, green: 0.56, blue: 0.45).opacity(0.32))
                        Capsule().fill(Color(red: 0.85, green: 0.56, blue: 0.45).opacity(0.32))
                    }
                    .frame(width: width * 0.50, height: width * 0.037)
                    .offset(y: width * 0.11)
                    if isHappy {
                        Ellipse().fill(MossPalette.ink)
                            .frame(width: width * 0.075, height: width * 0.06)
                            .offset(y: width * 0.12)
                    } else {
                        SmileShape().stroke(MossPalette.ink, style: StrokeStyle(lineWidth: max(1.5, width * 0.012), lineCap: .round))
                            .frame(width: width * 0.065, height: width * 0.035)
                            .offset(y: width * 0.12)
                    }
                }
                .scaleEffect(x: breathing ? (isHappy ? 0.96 : 1.015) : 1,
                             y: breathing ? (isHappy ? 1.04 : 0.985) : 1,
                             anchor: .bottom)
                .offset(y: breathing && isHappy ? -width * 0.07 : 0)

                if isHappy {
                    Image(systemName: "sparkle")
                        .font(.system(size: width * 0.11)).foregroundStyle(MossPalette.gold)
                        .rotationEffect(.degrees(breathing ? 10 : -10))
                        .offset(x: width * 0.44, y: -width * 0.20)
                    Image(systemName: "sparkle")
                        .font(.system(size: width * 0.07)).foregroundStyle(MossPalette.gold)
                        .offset(x: -width * 0.44, y: -width * 0.05)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isHappy ? "Mossling is celebrating" : isSleeping ? "Mossling is resting" : "Your cozy woodland Mossling")
        .onAppear { updateAnimation() }
        .onChange(of: allowsMotion) { _, _ in updateAnimation() }
        .onChange(of: mood) { _, _ in updateAnimation() }
        .onDisappear { withAnimation(nil) { breathing = false; blinking = false } }
        .task(id: allowsMotion && !isSleeping && !isHappy) {
            guard allowsMotion, !isSleeping, !isHappy else { blinking = false; return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(4.8))
                    withAnimation(.easeOut(duration: 0.07)) { blinking = true }
                    try await Task.sleep(for: .seconds(0.16))
                    withAnimation(.easeOut(duration: 0.09)) { blinking = false }
                } catch { blinking = false; return }
            }
        }
    }

    @ViewBuilder private func eye(width: CGFloat) -> some View {
        if isSleeping || isHappy {
            SmileShape().stroke(MossPalette.ink, style: StrokeStyle(lineWidth: max(2, width * 0.014), lineCap: .round))
                .frame(width: width * 0.055, height: width * 0.025)
                .rotationEffect(.degrees(isHappy ? 180 : 0))
        } else {
            Ellipse().fill(MossPalette.ink).frame(width: width * 0.031, height: width * 0.047)
                .scaleEffect(y: blinking ? 0.08 : 1)
        }
    }

    private func updateAnimation() {
        withAnimation(nil) { breathing = false }
        guard allowsMotion else { return }
        withAnimation(.easeInOut(duration: isHappy ? 0.6 : 2.4).repeatForever(autoreverses: true)) {
            breathing = true
        }
    }
}

private struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 1.7))
        return path
    }
}

private struct FernCrest: View {
    var stage: Int
    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            let h = proxy.size.height
            ZStack {
                Capsule().fill(MossPalette.moss).frame(width: w * 0.075, height: h * 0.74)
                    .rotationEffect(.degrees(12)).offset(x: -w * 0.04, y: h * 0.11)
                Path { path in
                    path.move(to: CGPoint(x: w * 0.47, y: h * 0.72))
                    path.addCurve(to: CGPoint(x: w * 0.67, y: h * 0.04),
                                  control1: CGPoint(x: w * 0.54, y: h * 0.43),
                                  control2: CGPoint(x: w * 0.73, y: h * 0.23))
                    path.addCurve(to: CGPoint(x: w * 0.39, y: h * 0.15),
                                  control1: CGPoint(x: w * 0.53, y: -h * 0.07),
                                  control2: CGPoint(x: w * 0.26, y: h * 0.04))
                    path.addCurve(to: CGPoint(x: w * 0.54, y: h * 0.13),
                                  control1: CGPoint(x: w * 0.44, y: h * 0.21),
                                  control2: CGPoint(x: w * 0.57, y: h * 0.21))
                }.stroke(MossPalette.moss, style: StrokeStyle(lineWidth: w * 0.075, lineCap: .round))
                ForEach(0..<4) { index in
                    let fraction = CGFloat(index)
                    Ellipse().fill(index.isMultiple(of: 2) ? MossPalette.fern : MossPalette.moss)
                        .frame(width: w * (0.48 - fraction * 0.055), height: h * 0.15)
                        .rotationEffect(.degrees(-32))
                        .offset(x: w * 0.14, y: h * (0.28 - fraction * 0.18))
                    Ellipse().fill(MossPalette.fern)
                        .frame(width: w * (0.43 - fraction * 0.05), height: h * 0.14)
                        .rotationEffect(.degrees(35))
                        .offset(x: -w * 0.18, y: h * (0.31 - fraction * 0.18))
                }
                if stage > 0 {
                    Circle().fill(MossPalette.gold).frame(width: w * 0.16)
                        .offset(x: w * 0.10, y: -h * 0.42)
                }
                if stage > 1 {
                    Ellipse().fill(MossPalette.fern)
                        .frame(width: w * 0.63, height: h * 0.18)
                        .rotationEffect(.degrees(-50)).offset(x: w * 0.39, y: h * 0.16)
                    Ellipse().fill(MossPalette.moss)
                        .frame(width: w * 0.53, height: h * 0.15)
                        .rotationEffect(.degrees(55)).offset(x: -w * 0.36, y: h * 0.19)
                    Circle().fill(MossPalette.gold).frame(width: w * 0.12)
                        .offset(x: w * 0.56, y: -h * 0.07)
                }
            }.frame(width: w, height: h)
        }
    }
}

struct ForestHabitat: View {
    var mood: MosslingCharacter.Mood = .cozy
    var stage: Int = 0
    var unlocks: [ForestUnlock] = []
    var animate = true

    var body: some View {
        GeometryReader { proxy in
            let w = proxy.size.width
            ZStack {
                Circle().fill(MossPalette.mint.opacity(0.16)).frame(width: w * 0.85)
                Circle().fill(Color.white.opacity(0.40)).frame(width: w * 0.60).offset(x: w * 0.17, y: -35)
                Ellipse().fill(MossPalette.stone).frame(width: w * 0.88, height: 75).offset(y: 87)
                Ellipse().fill(MossPalette.mint.opacity(0.75)).frame(width: w * 0.74, height: 51).offset(y: 80)
                Image(systemName: "leaf.fill").font(.system(size: 17)).foregroundStyle(MossPalette.moss.opacity(0.50))
                    .rotationEffect(.degrees(25)).offset(x: w * 0.34, y: 80)
                if unlocks.contains(.fern) {
                    Image(systemName: "leaf.fill").font(.system(size: 30)).foregroundStyle(MossPalette.fern)
                        .rotationEffect(.degrees(-30)).offset(x: -w * 0.35, y: 65)
                    Image(systemName: "leaf.fill").font(.system(size: 19)).foregroundStyle(MossPalette.moss)
                        .rotationEffect(.degrees(30)).offset(x: -w * 0.30, y: 75)
                }
                if unlocks.contains(.pond) {
                    Ellipse().fill(Color(red: 0.63, green: 0.79, blue: 0.79))
                        .frame(width: 78, height: 25).offset(x: -w * 0.17, y: 101)
                    Ellipse().stroke(Color.white.opacity(0.55), lineWidth: 1)
                        .frame(width: 43, height: 12).offset(x: -w * 0.17, y: 101)
                }
                if unlocks.contains(.mushrooms) {
                    ZStack {
                        Capsule().fill(MossPalette.cream).frame(width: 8, height: 22).offset(y: 6)
                        Ellipse().fill(Color(red: 0.74, green: 0.43, blue: 0.31)).frame(width: 28, height: 17)
                        Circle().fill(MossPalette.cream).frame(width: 4).offset(x: -6, y: -1)
                        Circle().fill(MossPalette.cream).frame(width: 3).offset(x: 5, y: -3)
                    }.offset(x: w * 0.35, y: 62)
                }
                if stage > 0 {
                    Image(systemName: "sparkle").font(.system(size: 18)).foregroundStyle(MossPalette.gold)
                        .offset(x: w * 0.31, y: -55)
                }
                MosslingCharacter(mood: mood, stage: stage, animate: animate)
                    .frame(width: min(w * 0.70, 245), height: 230)
                    .offset(y: -4)
            }.frame(width: proxy.size.width, height: proxy.size.height)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Your Mossling in a peaceful forest clearing")
    }
}
