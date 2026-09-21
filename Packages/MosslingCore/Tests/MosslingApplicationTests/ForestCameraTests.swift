import Testing
@testable import MosslingApplication

@Suite("Forest camera gestures")
struct ForestCameraTests {
    let viewport = ForestPoint(x: 400, y: 600)

    @Test func zoomKeepsTheTouchedPointFixedAndTracksCentroidTravel() {
        var camera = ForestCamera()
        camera.pan(by: .init(x: 20, y: -10), viewport: viewport)
        let start = ForestPoint(x: 250, y: 330)
        let end = ForestPoint(x: 260, y: 345)
        let localX = start.x - 200 - camera.offset.x
        let localY = start.y - 288 - camera.offset.y
        camera.magnify(by: 1.6, from: start, to: end, viewport: viewport)
        #expect(abs((200 + camera.offset.x + localX * camera.zoom) - end.x) < 0.0001)
        #expect(abs((288 + camera.offset.y + localY * camera.zoom) - end.y) < 0.0001)
        camera.magnify(by: 1 / 1.6, from: end, to: start, viewport: viewport)
        #expect(abs(camera.zoom - 1) < 0.0001)
        #expect(abs(camera.offset.x - 20) < 0.0001)
        #expect(abs(camera.offset.y + 10) < 0.0001)
    }

    @Test func limitsResetAndInvalidInputDoNotCorruptCamera() {
        var camera = ForestCamera()
        let center = ForestPoint(x: 200, y: 288)
        camera.magnify(by: 100, from: center, to: center, viewport: viewport)
        #expect(camera.zoom == 3)
        camera.magnify(by: 0.001, from: center, to: center, viewport: viewport)
        #expect(camera.zoom == 0.85)
        camera.pan(by: .init(x: 10_000, y: -10_000), viewport: viewport)
        #expect(camera.offset == .init(x: 260, y: -240))
        let saved = camera
        camera.magnify(by: .nan, from: center, to: center, viewport: viewport)
        camera.pan(by: .init(x: .infinity, y: 0), viewport: viewport)
        #expect(camera == saved)
        camera.reset()
        #expect(camera == ForestCamera())
    }
    @Test func coastIsShortFrameRateIndependentAndInterruptible() {
        var sixty = ForestCamera(), thirty = ForestCamera()
        sixty.coast(with: .init(x: 600, y: 300)); thirty.coast(with: .init(x: 600, y: 300))
        for _ in 0..<60 { sixty.advance(by: 1.0 / 60, viewport: viewport) }
        for _ in 0..<30 { thirty.advance(by: 1.0 / 30, viewport: viewport) }
        #expect(!sixty.isCoasting && !thirty.isCoasting)
        #expect(abs(sixty.offset.x - thirty.offset.x) < 0.1)
        #expect(sixty.offset.x > 55 && sixty.offset.x < 61)
        sixty.coast(with: .init(x: 600, y: 0))
        sixty.stop()
        let stopped = sixty
        sixty.advance(by: 1.0 / 60, viewport: viewport)
        #expect(sixty == stopped)
        thirty.pan(by: .init(x: 1000, y: 1000), viewport: viewport)
        thirty.coast(with: .init(x: 600, y: 300))
        thirty.advance(by: 1.0 / 60, viewport: viewport)
        #expect(!thirty.isCoasting)
        #expect(thirty.offset == .init(x: 260, y: 240))
        sixty.coast(with: .init(x: 9000, y: 0))
        #expect(sixty.velocity.x == 900)
        sixty.advance(by: 2, viewport: viewport)
        #expect(!sixty.isCoasting)
    }

}
