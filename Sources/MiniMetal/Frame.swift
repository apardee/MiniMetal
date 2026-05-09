import MetalKit

/// A single render frame's worth of Metal objects, bundled together so callers
/// don't have to chain four `guard let`s and remember the present/commit
/// dance themselves.
///
/// Acquire one with ``MetalKit/MTKView/beginFrame(queue:)`` (low-level) or
/// receive one in the closure passed to
/// ``MiniMetalWindow/show(_:)-(MTKView)->FrameAction``'s ``Frame`` overload
/// (high-level).
public struct Frame {
    /// The view this frame is rendering into.
    public let view: MTKView
    /// The render pass descriptor sourced from ``view``'s current drawable.
    public let pass: MTLRenderPassDescriptor
    /// The drawable that ``commandBuffer`` will present to.
    public let drawable: any CAMetalDrawable
    /// A fresh command buffer ready to encode into.
    public let commandBuffer: any MTLCommandBuffer
    /// A render command encoder open against ``pass``.
    public let encoder: any MTLRenderCommandEncoder

    /// End encoding, present the drawable, commit the buffer.
    ///
    /// Call this once per frame after issuing your draw calls. Typically used
    /// with `defer` so it runs even when the body returns early.
    public func finish() {
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}

extension MTKView {
    /// Acquire a frame's worth of Metal objects.
    ///
    /// Returns `nil` if the drawable isn't ready or any object fails to
    /// allocate — callers should skip the frame and try again next tick.
    /// - Parameter queue: The command queue to source the buffer from.
    public func beginFrame(queue: any MTLCommandQueue) -> Frame? {
        guard let pass = currentRenderPassDescriptor,
            let drawable = currentDrawable,
            let buffer = queue.makeCommandBuffer(),
            let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)
        else { return nil }
        return Frame(
            view: self,
            pass: pass,
            drawable: drawable,
            commandBuffer: buffer,
            encoder: encoder)
    }
}
