// Spinning cube

import Metal
import MetalKit
import MiniMetal
import simd

@main
struct SpinningCube {
    static func main() async throws {
        let window = try Window(
            title: "MiniMetal — Spinning Cube",
            resolution: .init(width: 800, height: 600))
        window.view.depthStencilPixelFormat = .depth32Float
        window.view.clearColor = MTLClearColor(red: 0.05, green: 0.05, blue: 0.08, alpha: 1.0)
        window.view.clearDepth = 1.0

        let device = window.device
        let library = try await device.makeLibrary(source: shaderSource, options: nil)

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertex_main")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "fragment_main")
        pipelineDescriptor.colorAttachments[0].pixelFormat = window.view.colorPixelFormat
        pipelineDescriptor.depthAttachmentPixelFormat = window.view.depthStencilPixelFormat
        let pipeline = try await device.makeRenderPipelineState(descriptor: pipelineDescriptor)

        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true
        let depthState = device.makeDepthStencilState(descriptor: depthDescriptor)!

        let start = CACurrentMediaTime()

        await window.show { (frame: Frame) in
            let t = Float(CACurrentMediaTime() - start)
            let size = frame.view.drawableSize
            let aspect = size.height > 0 ? Float(size.width / size.height) : 1
            let model = rotationY(t * 0.9) * rotationX(t * 0.6)
            let viewMatrix = translation(0, 0, -4)
            let projection = perspective(fovY: .pi / 4, aspect: aspect, near: 0.1, far: 100)
            var uniforms = Uniforms(mvp: projection * viewMatrix * model, model: model)

            frame.encoder.setRenderPipelineState(pipeline)
            frame.encoder.setDepthStencilState(depthState)
            frame.encoder.setVertexBytes(
                &uniforms, length: MemoryLayout<Uniforms>.stride, index: 0)
            frame.encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 36)
            return .continue
        }
    }
}

// MARK: - Uniforms

private struct Uniforms {
    var mvp: simd_float4x4
    var model: simd_float4x4
}

// MARK: - Matrix helpers (column-major, right-handed, Metal clip space [0, 1])

private func rotationY(_ a: Float) -> simd_float4x4 {
    let c = cos(a)
    let s = sin(a)
    return simd_float4x4(
        SIMD4(c, 0, -s, 0),
        SIMD4(0, 1, 0, 0),
        SIMD4(s, 0, c, 0),
        SIMD4(0, 0, 0, 1))
}

private func rotationX(_ a: Float) -> simd_float4x4 {
    let c = cos(a)
    let s = sin(a)
    return simd_float4x4(
        SIMD4(1, 0, 0, 0),
        SIMD4(0, c, s, 0),
        SIMD4(0, -s, c, 0),
        SIMD4(0, 0, 0, 1))
}

private func translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    var m = matrix_identity_float4x4
    m.columns.3 = SIMD4(x, y, z, 1)
    return m
}

private func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
    let y = 1 / tan(fovY * 0.5)
    let x = y / aspect
    let z = far / (near - far)
    let w = (far * near) / (near - far)
    return simd_float4x4(
        SIMD4(x, 0, 0, 0),
        SIMD4(0, y, 0, 0),
        SIMD4(0, 0, z, -1),
        SIMD4(0, 0, w, 0))
}

// MARK: - Shader

// 36 hard-coded cube vertices (12 triangles), normals derived in the fragment
// shader from screen-space position derivatives so we don't need a normal
// attribute or a vertex buffer at all.
private let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    constant float3 cubePositions[36] = {
        // -Z
        float3(-1,-1,-1), float3( 1,-1,-1), float3( 1, 1,-1),
        float3(-1,-1,-1), float3( 1, 1,-1), float3(-1, 1,-1),
        // +Z
        float3(-1,-1, 1), float3( 1, 1, 1), float3( 1,-1, 1),
        float3(-1,-1, 1), float3(-1, 1, 1), float3( 1, 1, 1),
        // -X
        float3(-1,-1,-1), float3(-1, 1,-1), float3(-1, 1, 1),
        float3(-1,-1,-1), float3(-1, 1, 1), float3(-1,-1, 1),
        // +X
        float3( 1,-1,-1), float3( 1, 1, 1), float3( 1, 1,-1),
        float3( 1,-1,-1), float3( 1,-1, 1), float3( 1, 1, 1),
        // -Y
        float3(-1,-1,-1), float3(-1,-1, 1), float3( 1,-1, 1),
        float3(-1,-1,-1), float3( 1,-1, 1), float3( 1,-1,-1),
        // +Y
        float3(-1, 1,-1), float3( 1, 1, 1), float3(-1, 1, 1),
        float3(-1, 1,-1), float3( 1, 1,-1), float3( 1, 1, 1),
    };

    struct Uniforms {
        float4x4 mvp;
        float4x4 model;
    };

    struct VertexOut {
        float4 position [[position]];
        float3 worldPos;
    };

    vertex VertexOut vertex_main(uint vid [[vertex_id]],
                                 constant Uniforms& u [[buffer(0)]]) {
        float3 p = cubePositions[vid];
        VertexOut out;
        out.position = u.mvp * float4(p, 1);
        out.worldPos = (u.model * float4(p, 1)).xyz;
        return out;
    }

    fragment float4 fragment_main(VertexOut in [[stage_in]]) {
        float3 N = normalize(cross(dfdx(in.worldPos), dfdy(in.worldPos)));
        float3 L = normalize(float3(0.4, 0.8, 0.6));
        float diff = saturate(dot(N, L));
        float3 base = float3(0.3, 0.6, 1.0);
        return float4(base * (0.2 + 0.8 * diff), 1);
    }
    """
