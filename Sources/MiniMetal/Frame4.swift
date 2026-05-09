import MetalKit

/// A single render frame's worth of Metal 4 objects.
///
/// Mirrors ``Frame`` but for the Metal 4 lifecycle, where command buffers are
/// long-lived, memory is owned by an explicit allocator, and drawable
/// presentation is split across the queue (`signalDrawable`) and the drawable
/// itself (`present`).
///
/// Acquire one with ``MetalKit/MTKView/beginFrame4(queue:commandBuffer:allocator:)``
/// (low-level) or receive one in the closure passed to
/// ``MiniMetalWindow/show(_:)-(Frame4)->FrameAction`` (high-level).
@available(macOS 26.0, *)
public struct Frame4 {
    /// The view this frame is rendering into.
    public let view: MTKView
    /// The Metal 4 render pass descriptor sourced from ``view``.
    public let pass: MTL4RenderPassDescriptor
    /// The drawable that will be presented at the end of the frame.
    public let drawable: any CAMetalDrawable
    /// The command buffer being recorded (caller-owned, reused across frames).
    public let commandBuffer: any MTL4CommandBuffer
    /// A render command encoder open against ``pass``.
    public let encoder: any MTL4RenderCommandEncoder

    /// End encoding, close the command buffer, commit it, signal the
    /// drawable, and present.
    ///
    /// Call once per frame after issuing draw calls. Typically used with
    /// `defer` so it runs on early returns.
    /// - Parameter queue: The queue the buffer was recorded against.
    public func finish(queue: any MTL4CommandQueue) {
        encoder.endEncoding()
        commandBuffer.endCommandBuffer()
        queue.commit([commandBuffer])
        queue.signalDrawable(drawable)
        drawable.present()
    }
}

@available(macOS 26.0, *)
extension MTKView {
    /// Acquire a Metal 4 frame using a caller-owned queue, command buffer, and
    /// allocator.
    ///
    /// Returns `nil` if the drawable or render pass descriptor isn't ready.
    /// Allocator/buffer setup happens *after* drawable validation so a missed
    /// frame doesn't leave the buffer in a half-bracketed state.
    public func beginFrame4(
        queue: any MTL4CommandQueue,
        commandBuffer: any MTL4CommandBuffer,
        allocator: any MTL4CommandAllocator
    ) -> Frame4? {
        guard let pass = currentMTL4RenderPassDescriptor,
            let drawable = currentDrawable
        else { return nil }
        allocator.reset()
        commandBuffer.beginCommandBuffer(allocator: allocator)
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: pass) else {
            // Buffer is already open; close it so the allocator can be reset
            // cleanly next frame.
            commandBuffer.endCommandBuffer()
            return nil
        }
        queue.waitForDrawable(drawable)
        return Frame4(
            view: self,
            pass: pass,
            drawable: drawable,
            commandBuffer: commandBuffer,
            encoder: encoder)
    }
}
