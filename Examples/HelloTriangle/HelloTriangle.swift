// This demo stays on the macro-free `MiniMetal` path — it builds a
// `MetalShader` by hand instead of via `#shader`, so it carries no swift-syntax
// build cost. See `SpinningCube` for the opt-in `import MiniMetalMacros` path.
import MiniMetal

@main
struct HelloTriangle {
    static func main() async throws {
        let window = try Window(
            title: "MiniMetal - Hello Triangle",
            resolution: .init(width: 1024, height: 768))

        let shader = MetalShader(
            source: """
                #include <metal_stdlib>
                using namespace metal;

                constant float3 vertices[] = {
                    float3( 1.0, -1.0, 0.0),
                    float3( 0.0,  1.0, 0.0),
                    float3(-1.0, -1.0, 0.0)
                };

                vertex float4 vertex_main(uint vid [[vertex_id]]) {
                    return float4(vertices[vid], 1.0);
                }

                fragment float4 fragment_main() {
                    return float4(1.0, 0.0, 0.0, 1.0);
                }
                """,
            vertex: ["vertex_main"],
            fragment: ["fragment_main"])

        let pipelineState = try await window.device.makeRenderPipeline(
            shader: shader,
            vertex: "vertex_main",
            fragment: "fragment_main",
            color: window.view.colorPixelFormat,
            depth: window.view.depthStencilPixelFormat)

        await window.show { (frame: Frame) in
            frame.encoder.setRenderPipelineState(pipelineState)
            frame.encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            return .continue
        }

    }
}
