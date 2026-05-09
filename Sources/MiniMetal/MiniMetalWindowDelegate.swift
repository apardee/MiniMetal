import CoreGraphics
import MetalKit

/// Receives drawable-resize and per-frame draw callbacks from a
/// ``Window``.
///
/// The shape mirrors `MTKViewDelegate` so that existing rendering code can be
/// adapted with minimal change, but it does **not** require `NSObjectProtocol`
/// conformance — any class can adopt it directly:
///
///     final class Renderer: MiniMetalWindowDelegate {
///         func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { ... }
///         func draw(in view: MTKView) { ... }
///     }
///
/// All methods are invoked on the main actor.
@MainActor
public protocol MiniMetalWindowDelegate: AnyObject {
    /// Called whenever the view's drawable size changes — typically when the
    /// window is resized or moved between displays of differing scale factors.
    /// - Parameters:
    ///   - view: The Metal-backed view whose drawable changed.
    ///   - size: The new drawable size, in pixels.
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize)

    /// Called once per frame to render content into `view`.
    /// - Parameter view: The Metal-backed view to draw into.
    func draw(in view: MTKView)
}
