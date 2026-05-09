import Testing
import CoreGraphics
import Metal
import MetalKit
@testable import MiniMetal

// MARK: - Resolution

@Suite struct ResolutionTests {
    @Test func storesDimensions() {
        let r = Resolution(width: 640, height: 480)
        #expect(r.width == 640)
        #expect(r.height == 480)
    }

    @Test func convertsToCGSize() {
        let r = Resolution(width: 1280, height: 720)
        #expect(r.size == CGSize(width: 1280, height: 720))
    }

    @Test func equatableAndHashable() {
        let a = Resolution(width: 100, height: 200)
        let b = Resolution(width: 100, height: 200)
        let c = Resolution(width: 200, height: 100)
        #expect(a == b)
        #expect(a != c)
        #expect(a.hashValue == b.hashValue)
    }
}

// MARK: - FrameAction

@Suite struct FrameActionTests {
    @Test func casesAreDistinct() {
        #expect(FrameAction.continue == .continue)
        #expect(FrameAction.quit == .quit)
        #expect(FrameAction.continue != .quit)
    }
}

// MARK: - MiniMetalWindow

/// Renderer used to verify delegate wiring without actually presenting
/// the window.
@MainActor
final class CountingRenderer: MiniMetalWindowDelegate {
    var drawCount = 0
    var lastResize: CGSize?

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        lastResize = size
    }

    func draw(in view: MTKView) {
        drawCount += 1
    }
}

@Suite struct MiniMetalWindowTests {
    /// Skip window construction tests on hosts where Metal is unavailable
    /// (e.g., headless CI without GPU access).
    static var hasMetal: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    @MainActor
    @Test func createsWindowWithTitleAndSize() throws {
        try #require(Self.hasMetal)
        let window = try MiniMetalWindow(
            title: "Test Renderer",
            resolution: .init(width: 640, height: 480))
        #expect(window.window.title == "Test Renderer")
        #expect(window.window.contentView === window.view)
        #expect(window.view.frame.size == CGSize(width: 640, height: 480))
        #expect(window.view.device != nil)
    }

    @MainActor
    @Test func exposesMetalDevice() throws {
        try #require(Self.hasMetal)
        let window = try MiniMetalWindow(
            title: "Devices",
            resolution: .init(width: 100, height: 100))
        // Identity check: `device` should be the same MTLDevice as the view's.
        #expect(window.device === window.view.device)
    }

    @MainActor
    @Test func acceptsCustomDevice() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let window = try MiniMetalWindow(
            title: "Custom",
            resolution: .init(width: 100, height: 100),
            device: device)
        #expect(window.view.device === device)
    }

    @MainActor
    @Test func delegateRoundTrips() throws {
        try #require(Self.hasMetal)
        let window = try MiniMetalWindow(
            title: "Delegate",
            resolution: .init(width: 100, height: 100))
        let renderer = CountingRenderer()
        window.delegate = renderer
        #expect((window.delegate as AnyObject?) === renderer)

        // Driving the underlying MTKViewDelegate (via the internal adapter)
        // should forward to the user delegate without going through the
        // run loop.
        window.view.delegate?.mtkView(window.view, drawableSizeWillChange: CGSize(width: 200, height: 100))
        window.view.delegate?.draw(in: window.view)

        #expect(renderer.drawCount == 1)
        #expect(renderer.lastResize == CGSize(width: 200, height: 100))
    }

    @MainActor
    @Test func delegateIsHeldWeakly() throws {
        try #require(Self.hasMetal)
        let window = try MiniMetalWindow(
            title: "Weak",
            resolution: .init(width: 100, height: 100))

        weak var weakRenderer: CountingRenderer?
        do {
            let renderer = CountingRenderer()
            weakRenderer = renderer
            window.delegate = renderer
            #expect(weakRenderer != nil)
        }
        // Renderer has gone out of scope; the weak delegate slot should be
        // cleared and the window should not have retained it.
        #expect(weakRenderer == nil)
        #expect(window.delegate == nil)
    }
}
