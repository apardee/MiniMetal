// Smallest viable MiniMetal example: open a window and clear it to a solid
// color every frame.

import Metal
import MiniMetal

@main
struct HelloWindow {

    static func main() async throws {
        let window = try MiniMetalWindow(
            title: "MiniMetal — Hello Window",
            resolution: .init(width: 1024, height: 768))
        window.view.clearColor = MTLClearColor(red: 1.0, green: 0.0, blue: 1.0, alpha: 1.0)

        let queue = window.device.makeCommandQueue()!

        await window.show { view in
            // The render pass descriptor's load action is what clears the
            // drawable to `clearColor` — opening and immediately ending an
            // encoder triggers the clear without issuing any draw calls.
            guard let pass = view.currentRenderPassDescriptor,
                let drawable = view.currentDrawable,
                let buffer = queue.makeCommandBuffer(),
                let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
            else { return .continue }

            encoder.endEncoding()
            buffer.present(drawable)
            buffer.commit()
            return .continue
        }
    }
}
