import Testing
import CoreGraphics
import Metal
import MetalKit
import simd
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

@Suite struct WindowTests {
    /// Skip window construction tests on hosts where Metal is unavailable
    /// (e.g., headless CI without GPU access).
    static var hasMetal: Bool {
        MTLCreateSystemDefaultDevice() != nil
    }

    @MainActor
    @Test func createsWindowWithTitleAndSize() throws {
        try #require(Self.hasMetal)
        let window = try Window(
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
        let window = try Window(
            title: "Devices",
            resolution: .init(width: 100, height: 100))
        // Identity check: `device` should be the same MTLDevice as the view's.
        #expect(window.device === window.view.device)
    }

    @MainActor
    @Test func acceptsCustomDevice() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let window = try Window(
            title: "Custom",
            resolution: .init(width: 100, height: 100),
            device: device)
        #expect(window.view.device === device)
    }

    @MainActor
    @Test func delegateRoundTrips() throws {
        try #require(Self.hasMetal)
        let window = try Window(
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
        let window = try Window(
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

// MARK: - #shader

@Suite struct ShaderMacroTests {
    @Test func extractsSingleVertexAndFragment() {
        let s = #shader("""
            vertex VertexOut vertex_main(uint vid [[vertex_id]]) { return VertexOut(); }
            fragment float4 fragment_main(VertexOut in [[stage_in]]) { return float4(0); }
            """)
        #expect(s.vertex == ["vertex_main"])
        #expect(s.fragment == ["fragment_main"])
        #expect(s.compute.isEmpty)
    }

    @Test func extractsMultipleEntryPointsInDeclarationOrder() {
        let s = #shader("""
            vertex VertexOut v_a(uint vid [[vertex_id]]) { return VertexOut(); }
            vertex VertexOut v_b(uint vid [[vertex_id]]) { return VertexOut(); }
            fragment float4 f_a(VertexOut in [[stage_in]]) { return float4(0); }
            fragment float4 f_b(VertexOut in [[stage_in]]) { return float4(0); }
            """)
        #expect(s.vertex == ["v_a", "v_b"])
        #expect(s.fragment == ["f_a", "f_b"])
    }

    @Test func extractsKernelEntryPoints() {
        let s = #shader("""
            kernel void compute_main(uint tid [[thread_position_in_grid]]) {}
            """)
        #expect(s.compute == ["compute_main"])
        #expect(s.vertex.isEmpty)
        #expect(s.fragment.isEmpty)
    }

    @Test func skipsCommentedDeclarations() {
        let s = #shader("""
            // vertex VertexOut commented_out(uint vid [[vertex_id]]) { return VertexOut(); }
            /* fragment float4 also_commented(VertexOut in [[stage_in]]) { return float4(0); } */
            vertex VertexOut real_vertex(uint vid [[vertex_id]]) { return VertexOut(); }
            """)
        #expect(s.vertex == ["real_vertex"])
        #expect(s.fragment.isEmpty)
    }

    @Test func sourceIsRoundTrippedVerbatim() {
        let body = """
            vertex VertexOut v(uint vid [[vertex_id]]) { return VertexOut(); }
            """
        let s = #shader("""
            vertex VertexOut v(uint vid [[vertex_id]]) { return VertexOut(); }
            """)
        #expect(s.source == body)
    }
}

// MARK: - @MetalLayout

@MetalLayout
private struct OneFloat {
    var x: Float
}

@MetalLayout
private struct CubeUniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
}

/// Mixes scalar and simd_float3 to exercise the float3-padded-to-vec4 rule:
/// without the size-16 alignment, c and d would land at MSL offsets that
/// don't match Swift's, silently corrupting GPU reads.
@MetalLayout
private struct AssortedFields {
    var a: Float
    var b: simd_float3
    var c: UInt32
    var d: Bool
}

@MetalLayout
private struct GenericSIMD {
    var p: SIMD4<Float>
    var q: SIMD2<Int32>
}

@Suite struct MetalLayoutTests {
    @Test func conformsToMetalUniform() {
        // Compile-time check: assignment fails if the macro didn't add
        // the conformance.
        let _: any MetalUniform.Type = OneFloat.self
    }

    @Test func emitsScalarStruct() {
        #expect(OneFloat.mslDeclaration == """
            struct OneFloat {
                float x;
            };
            """)
    }

    @Test func emitsMatrixStruct() {
        #expect(CubeUniforms.mslDeclaration == """
            struct CubeUniforms {
                float4x4 mvp;
                float4x4 model;
            };
            """)
        #expect(MemoryLayout<CubeUniforms>.stride == 128)
    }

    @Test func emitsAssortedStruct() {
        let decl = AssortedFields.mslDeclaration
        #expect(decl.contains("float a;"))
        #expect(decl.contains("float3 b;"))
        #expect(decl.contains("uint c;"))
        #expect(decl.contains("bool d;"))
        // Touching mslDeclaration above ran the stride precondition; if we
        // got here, Swift and MSL strides agree.
        #expect(MemoryLayout<AssortedFields>.stride == 48)
    }

    @Test func mapsGenericSIMD() {
        let decl = GenericSIMD.mslDeclaration
        #expect(decl.contains("float4 p;"))
        #expect(decl.contains("int2 q;"))
    }
}
