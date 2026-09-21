import SwiftUI
import SpriteKit
import MosslingCore

/// Frames share a canvas and timing; clips may contain any number of authored poses.
struct ActivityArtClip {
    struct Frame {
        let asset: String
        let rect: CGRect
        let seconds: Double
    }
    let frames: [Frame]
    let poster: Int

    static func movement(_ movement: ActivityMovement) -> Self {
        switch movement {
        case .wallPush: grid("BrackenPushMotions", column: 0)
        case .inclinePush: grid("BrackenPushMotions", column: 1)
        case .floorPush: grid("BrackenPushMotions", column: 2)
        case .squat: grid("BrackenStrengthMotions", column: 0)
        case .singleLegCalfRaise: grid("BrackenStrengthMotions", column: 1)
        case .freeLunge: grid("BrackenStrengthMotions", column: 2)
        case .bandSideLegRaise: grid("BrackenResistanceMotions", column: 0, x: 0, width: 576)
        case .weightedLegCurl: grid("BrackenResistanceMotions", column: 1, x: 610, width: 462)
        case .weightedKneeExtension: grid("BrackenResistanceMotions", column: 2, x: 1100, width: 436)
        case .jumpingJack: grid("BrackenCoordinationMotions", column: 0)
        case .standingToeRaise: grid("BrackenCoordinationMotions", column: 1)
        case .stepPunch: grid("BrackenCoordinationMotions", column: 2)
        case .walk: grid("BrackenEverydayMotions", column: 0)
        case .chairStand: grid("BrackenEverydayMotions", column: 1)
        case .calfRaise: grid("BrackenEverydayMotions", column: 2)
        case .shoulderMobility: grid("BrackenMarchMotions", column: 0)
        case .march: grid("BrackenMarchMotions", column: 1)
        case .seatedMarch: grid("BrackenMarchMotions", column: 2)
        case .sideStep: grid("BrackenStepMotions", column: 0)
        case .stepJack: grid("BrackenStepMotions", column: 1)
        case .miniSquat: grid("BrackenStepMotions", column: 2)
        case .reverseLunge: grid("BrackenSupportMotions", column: 0)
        case .sideLegRaise: grid("BrackenSupportMotions", column: 1)
        case .legCurl: grid("BrackenSupportMotions", column: 2)
        case .seatedKneeExtension: grid("BrackenSeatedMotions", column: 0)
        case .seatedToeRaise: grid("BrackenSeatedMotions", column: 1)
        case .wallSlide: grid("BrackenWallSlideMotions", column: 0)
        case .standingPunch: grid("BrackenPunchMotions", column: 0)
        case .custom:
            Self(frames: [.init(asset: "BrackenActivities", rect: CGRect(x: 1176, y: 516, width: 241, height: 466), seconds: 1)], poster: 0)
        }
    }

    static func activity(_ activity: ActivityDefinition) -> Self {
        let clip = movement(activity.movement)
        let held = ["paused-squat", "paused-leg-curl", "paused-knee-extension"].contains(activity.catalogVariationID ?? "")
        let brisk = ["brisk-walk", "brisk-march"].contains(activity.catalogVariationID ?? "")
        return Self(frames: clip.frames.enumerated().map { index, frame in
            Frame(asset: frame.asset, rect: frame.rect, seconds: held && index == clip.poster ? 2 : brisk ? 0.55 : frame.seconds)
        }, poster: clip.poster)
    }

    private static func grid(_ asset: String, column: Int, x: CGFloat? = nil, width: CGFloat = 512) -> Self {
        Self(frames: (0..<2).map { row in
            Frame(asset: asset, rect: CGRect(x: x ?? CGFloat(column * 512), y: CGFloat(row * 512), width: width, height: 512), seconds: 0.85)
        }, poster: 1)
    }
}

@MainActor
private enum ActivityArtwork {
    private static var atlases: [String: SKTexture] = [:]
    private static var images: [String: CGImage] = [:]

    static func image(_ frame: ActivityArtClip.Frame) -> CGImage {
        let key = "\(frame.asset)-\(frame.rect)"
        if let image = images[key] { return image }
        let atlas = atlases[frame.asset] ?? SKTexture(imageNamed: frame.asset)
        atlases[frame.asset] = atlas
        let rect = frame.rect, size = atlas.size()
        let texture = SKTexture(rect: CGRect(x: rect.minX / size.width, y: 1 - rect.maxY / size.height,
                                            width: rect.width / size.width, height: rect.height / size.height), in: atlas)
        let image = texture.cgImage()
        images[key] = image
        return image
    }
}

struct ActivityIllustration: View {
    let activity: ActivityDefinition
    var frame: Int? = nil

    var body: some View {
        let clip = ActivityArtClip.activity(activity)
        let index = min(max(frame ?? clip.poster, 0), clip.frames.count - 1)
        Image(decorative: ActivityArtwork.image(clip.frames[index]), scale: 1)
            .resizable().scaledToFit().accessibilityHidden(true)
    }
}

struct ActivityDemonstration: View {
    let activity: ActivityDefinition
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    #if os(watchOS)
    @Environment(\.isLuminanceReduced) private var reducedLuminance
    #endif
    @State private var frame: Int?
    @State private var replay = 0
    @State private var playing = false

    private var reducedMotion: Bool {
        #if DEBUG && targetEnvironment(simulator)
        if ProcessInfo.processInfo.arguments.contains("--ui-testing"),
           ProcessInfo.processInfo.arguments.contains("--ui-testing-reduce-motion") { return true }
        #endif
        return systemReduceMotion
    }
    private var active: Bool {
        #if os(watchOS)
        scenePhase == .active && !reducedLuminance && !reducedMotion
        #else
        scenePhase == .active && !reducedMotion
        #endif
    }
    private var playbackID: String { "\(activity.catalogVariationID ?? activity.movement.rawValue)-\(active)-\(replay)" }

    var body: some View {
        VStack(spacing: 6) {
            ActivityIllustration(activity: activity, frame: active ? frame : nil)
                .frame(height: 180)
            if ActivityArtClip.activity(activity).frames.count > 1, !reducedMotion {
                Button {
                    replay += 1
                } label: {
                    Label("Replay movement", systemImage: "arrow.counterclockwise")
                        .font(.caption).frame(minHeight: 44)
                }.disabled(playing || !active).accessibilityIdentifier("replayMovement")
            }
        }
        .task(id: playbackID) {
            frame = nil
            playing = false
            let clip = ActivityArtClip.activity(activity)
            guard active, clip.frames.count > 1 else { return }
            playing = true
            for _ in 0..<2 {
                for index in clip.frames.indices {
                    guard !Task.isCancelled else { return }
                    frame = index
                    do { try await Task.sleep(for: .seconds(clip.frames[index].seconds)) }
                    catch { return }
                }
            }
            frame = nil
            playing = false
        }
    }
}
