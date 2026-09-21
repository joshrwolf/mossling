import SwiftUI
import SpriteKit
import Observation
import MosslingCore
import MosslingApplication

@MainActor @Observable
private final class ForestDirector {
    @ObservationIgnored let scene = ForestScene(canvasSize: CGSize(width: 390, height: 600))
    @ObservationIgnored private var playback = ForestPlayback()
    @ObservationIgnored private var snapshot: ForestSnapshot?
    @ObservationIgnored private var motion = false
    @ObservationIgnored private var lastActive: Bool?
    @ObservationIgnored private var lastReduceMotion: Bool?
    var momentTitle: String?
    var zoomPercent = 100

    init() {
        scene.momentFinished = { [weak self] in self?.momentTitle = nil }
        scene.cameraChanged = { [weak self] in self?.zoomPercent = $0 }
    }

    func update(_ snapshot: ForestSnapshot, active: Bool, reduceMotion: Bool) {
        guard self.snapshot != snapshot || lastActive != active || lastReduceMotion != reduceMotion else { return }
        lastActive = active
        lastReduceMotion = reduceMotion
        self.snapshot = snapshot
        motion = active && !reduceMotion
        let transition = playback.receive(snapshot, active: active, reduceMotion: reduceMotion)
        switch transition.moment {
        case .evolution: momentTitle = snapshot.stage.title
        case .discovery: momentTitle = transition.discoveries.first.map { $0.title + " unlocked" }
        case .none, .snack: momentTitle = nil
        }
        scene.present(transition, motion: motion)
    }

    func finishMoment() {
        if let snapshot { scene.settle(snapshot, motion: motion) }
        momentTitle = nil
    }
}

struct ForestCanvas: View {
    let snapshot: ForestSnapshot
    var active = true
    var announcementTopInset: CGFloat = 0
    var draftKind: HabitatKind?
    var selectedCell: ForestCell?
    var onSelectCell: ((ForestCell) -> Void)?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var reducedLuminance
    #endif
    @State private var director = ForestDirector()
    @State private var visible = false

    private var reduceMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return systemReduceMotion
    }

    private var running: Bool {
        #if os(watchOS)
        active && visible && scenePhase == .active && !reducedLuminance
        #else
        active && visible && scenePhase == .active
        #endif
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                #if os(iOS)
                ForestSurface(scene: director.scene, paused: !running, framesPerSecond: 60, onTap: select)
                #else
                ForestSurface(scene: director.scene, paused: !running, framesPerSecond: reduceMotion ? 15 : 30)
                    .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle()).onTapGesture(perform: select)
                #endif
            }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityRepresentation {
                    Group {
                        if reduceMotion {
                            Text("Woodland clearing")
                        } else {
                            Button("Woodland clearing") { director.scene.react() }
                                .accessibilityHint("Visit a habitat object")
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityValue(([snapshot.stage.title] + ForestRegion.allCases.filter { snapshot.world.regions.contains($0) }.map(\.title) + snapshot.world.placements.map { $0.kind.title }).joined(separator: "; "))
                    .accessibilityIdentifier("forestScene")
                    #if os(iOS)
                    .accessibilityAction(named: "Zoom in") { director.scene.magnify(by: 1.25) }
                    .accessibilityAction(named: "Zoom out") { director.scene.magnify(by: 0.8) }
                    .accessibilityAction(named: "Center habitat") { director.scene.centerCamera() }
                    #endif
                }
                .overlay(alignment: .bottomTrailing) {
                    #if os(iOS)
                    Button("Center habitat", systemImage: "scope") { director.scene.centerCamera() }
                        .labelStyle(.iconOnly).font(.body).padding(12)
                        .background(MossPalette.ink.opacity(0.9), in: Circle())
                        .foregroundStyle(MossPalette.cream).padding(12)
                        .accessibilityIdentifier("centerHabitat")
                        .accessibilityValue("\(director.zoomPercent)% zoom")
                    #endif
                }
                .overlay(alignment: .top) {
                    if let title = director.momentTitle {
                        VStack(spacing: 6) {
                            Text(title).font(.headline)
                            Button("Skip animation") { director.finishMoment() }
                                .font(.caption)
                                .accessibilityIdentifier("skipForestAnimation")
                        }
                        .padding(12)
                        .foregroundStyle(MossPalette.cream)
                        .background(MossPalette.ink.opacity(0.95), in: RoundedRectangle(cornerRadius: 16))
                        .padding(.top, announcementTopInset)
                    }
                }
                .onAppear { director.scene.resize(to: geometry.size); visible = true; update() }
                .onChange(of: geometry.size) { _, size in director.scene.resize(to: size) }
                .onDisappear { visible = false; update() }
                .onChange(of: snapshot) { _, _ in update() }
                .onChange(of: running) { _, _ in update() }
                .onChange(of: reduceMotion) { _, _ in update() }
                .onChange(of: selectedCell) { _, _ in showDraft() }
                .onChange(of: draftKind) { _, _ in showDraft() }
        }
    }

    private func select(_ location: CGPoint) {
        if let onSelectCell, let cell = director.scene.cell(at: location) { onSelectCell(cell) }
        else { director.scene.react() }
    }

    private func update() {
        director.update(snapshot, active: running, reduceMotion: reduceMotion)
        showDraft()
    }

    private func showDraft() { director.scene.showPlacement(draftKind, at: selectedCell) }
}

#if os(iOS)
private final class ForestSKView: SKView {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        (scene as? ForestScene)?.stopCameraMotion()
        super.touchesBegan(touches, with: event)
    }
}

private struct ForestSurface: UIViewRepresentable {
    let scene: ForestScene
    let paused: Bool
    let framesPerSecond: Int
    let onTap: (CGPoint) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(scene: scene, onTap: onTap) }

    func makeUIView(context: Context) -> SKView {
        let view = ForestSKView()
        view.ignoresSiblingOrder = true
        context.coordinator.install(on: view)
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        context.coordinator.onTap = onTap
        if view.scene !== scene { view.presentScene(scene) }
        view.preferredFramesPerSecond = framesPerSecond
        if paused { context.coordinator.stopDisplayLink(); scene.stopCameraMotion() }
        view.isPaused = paused
    }

    static func dismantleUIView(_ view: SKView, coordinator: Coordinator) {
        coordinator.stopDisplayLink()
        coordinator.scene.stopCameraMotion()
        view.gestureRecognizers?.forEach(view.removeGestureRecognizer)
        view.presentScene(nil)
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let scene: ForestScene
        var onTap: (CGPoint) -> Void
        private var pinch: UIPinchGestureRecognizer!
        private var previousAnchor: CGPoint?
        private var displayLink: CADisplayLink?
        private var canCoast = false

        init(scene: ForestScene, onTap: @escaping (CGPoint) -> Void) {
            self.scene = scene; self.onTap = onTap
        }
        func install(on view: UIView) {
            let pan = UIPanGestureRecognizer(target: self, action: #selector(drag(_:)))
            pan.maximumNumberOfTouches = 2
            pinch = UIPinchGestureRecognizer(target: self, action: #selector(zoom(_:)))
            let tap = UITapGestureRecognizer(target: self, action: #selector(tap(_:)))
            pan.delegate = self; pinch.delegate = self
            tap.require(toFail: pan); tap.require(toFail: pinch)
            [pan, pinch, tap].forEach(view.addGestureRecognizer)
        }
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
            (gestureRecognizer is UIPanGestureRecognizer && other is UIPinchGestureRecognizer) ||
            (gestureRecognizer is UIPinchGestureRecognizer && other is UIPanGestureRecognizer)
        }
        @objc private func drag(_ gesture: UIPanGestureRecognizer) {
            let delta = gesture.translation(in: gesture.view)
            gesture.setTranslation(.zero, in: gesture.view)
            guard pinch.state != .began, pinch.state != .changed else { canCoast = false; return }
            if gesture.state == .began { scene.stopCameraMotion(); canCoast = false }
            if gesture.state == .changed, gesture.numberOfTouches == 1 {
                canCoast = true
                scene.moveCamera(by: delta)
            }
            if gesture.state == .ended, canCoast {
                canCoast = false
                scene.endCameraDrag(velocity: gesture.velocity(in: gesture.view))
                stopDisplayLink()
                let link = CADisplayLink(target: self, selector: #selector(coast(_:)))
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
                link.add(to: .main, forMode: .common)
                displayLink = link
            }
            if gesture.state == .cancelled || gesture.state == .failed {
                canCoast = false; stopDisplayLink(); scene.stopCameraMotion(); scene.finishCameraInteraction()
            }
        }
        @objc private func zoom(_ gesture: UIPinchGestureRecognizer) {
            switch gesture.state {
            case .began:
                canCoast = false
                scene.stopCameraMotion()
                previousAnchor = gesture.location(in: gesture.view)
                gesture.scale = 1
            case .changed:
                let anchor = gesture.location(in: gesture.view)
                scene.magnify(by: gesture.scale, from: previousAnchor ?? anchor, to: anchor)
                previousAnchor = anchor
                gesture.scale = 1
            case .ended, .cancelled, .failed:
                previousAnchor = nil
                scene.finishCameraInteraction()
            default: break
            }
        }
        func stopDisplayLink() { displayLink?.invalidate(); displayLink = nil }
        @objc private func coast(_ link: CADisplayLink) {
            if !scene.advanceCamera(to: link.timestamp) { stopDisplayLink() }
        }
        @objc private func tap(_ gesture: UITapGestureRecognizer) { onTap(gesture.location(in: gesture.view)) }
    }
}
#else
private struct ForestSurface: View {
    let scene: ForestScene
    let paused: Bool
    let framesPerSecond: Int

    var body: some View {
        SpriteView(scene: scene, isPaused: paused, preferredFramesPerSecond: framesPerSecond)
    }
}
#endif

struct CompanionPortrait: View {
    var stage: CompanionStage = .seedling
    var body: some View {
        Image(decorative: ForestArt.character(stage).cgImage(), scale: 1).resizable().scaledToFit()
            .accessibilityLabel(stage.title)
    }
}
