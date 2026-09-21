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

    init() {
        scene.momentFinished = { [weak self] in self?.momentTitle = nil }
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
                ForestSurface(scene: director.scene, paused: !running, framesPerSecond: reduceMotion ? 15 : 30)
                    .allowsHitTesting(false)
                Color.clear.contentShape(Rectangle())
            }
                .accessibilityRepresentation {
                    Group {
                        if reduceMotion {
                            Text("Woodland clearing")
                        } else {
                            Button("Woodland clearing") { director.scene.react() }
                                .accessibilityHint("Visit a habitat object")
                        }
                    }
                    .accessibilityValue(([snapshot.stage.title] + ForestRegion.allCases.filter { snapshot.world.regions.contains($0) }.map(\.title) + snapshot.world.placements.map { $0.kind.title }).joined(separator: "; "))
                    .accessibilityIdentifier("forestScene")
                }
                .onTapGesture { location in
                    if let onSelectCell, let cell = director.scene.cell(at: location) { onSelectCell(cell) }
                    else { director.scene.react() }
                }
                #if os(iOS)
                .gesture(DragGesture(minimumDistance: 12)
                    .onChanged { director.scene.moveCamera(by: $0.translation, ended: false) }
                    .onEnded { director.scene.moveCamera(by: $0.translation, ended: true) })
                #endif
                .overlay(alignment: .bottomTrailing) {
                    #if os(iOS)
                    HStack(spacing: 16) {
                        Button("Zoom out", systemImage: "minus.magnifyingglass") { director.scene.magnify(by: 0.8) }
                        Button("Center habitat", systemImage: "scope") { director.scene.centerCamera() }
                        Button("Zoom in", systemImage: "plus.magnifyingglass") { director.scene.magnify(by: 1.25) }
                    }
                    .labelStyle(.iconOnly).font(.body).padding(12)
                    .background(MossPalette.ink.opacity(0.9), in: Capsule())
                    .foregroundStyle(MossPalette.cream).padding(12)
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
                        .padding(.top, 84)
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

    private func update() {
        director.update(snapshot, active: running, reduceMotion: reduceMotion)
        showDraft()
    }

    private func showDraft() { director.scene.showPlacement(draftKind, at: selectedCell) }
}

#if os(iOS)
private struct ForestSurface: UIViewRepresentable {
    let scene: ForestScene
    let paused: Bool
    let framesPerSecond: Int

    func makeUIView(context: Context) -> SKView {
        let view = SKView()
        view.isUserInteractionEnabled = false
        view.ignoresSiblingOrder = true
        return view
    }

    func updateUIView(_ view: SKView, context: Context) {
        if view.scene !== scene { view.presentScene(scene) }
        view.preferredFramesPerSecond = framesPerSecond
        view.isPaused = paused
    }

    static func dismantleUIView(_ view: SKView, coordinator: ()) {
        view.presentScene(nil)
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
